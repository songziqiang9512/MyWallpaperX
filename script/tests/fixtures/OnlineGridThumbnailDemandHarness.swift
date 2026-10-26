import AppKit
import Foundation

// These leaves control ready pixels and completion, not production viewport
// demand, task ownership, identity checks, or the NSView lifecycle callbacks.
struct OnlineLibraryVideoItem { let id: Int; let previewThumbnailURL: URL? }
enum OLThumbnailRequestPriority { case visible, prefetch }
@MainActor final class OLThumbnailCache {
    static let shared = OLThumbnailCache()
    struct Pending { let url: URL; let continuation: CheckedContinuation<NSImage?, Never> }
    var pending: [UUID: Pending] = [:]
    var ready: [URL: NSImage] = [:]
    var history: [URL: Int] = [:]
    var generation = 0
    func publicationGeneration() async -> Int { generation }
    func readyImage(for url: URL, maxPixelSize: Int) -> NSImage? { ready[url] }
    func image(for url: URL, maxPixelSize: Int, priority: OLThumbnailRequestPriority) async -> NSImage? {
        if let value = ready[url] { return value }
        history[url, default: 0] += 1
        return await withCheckedContinuation { pending[UUID()] = Pending(url: url, continuation: $0) }
    }
    func complete(_ url: URL, image: NSImage?) {
        if let image { ready[url] = image }
        let matching = pending.filter { $0.value.url == url }
        for (id, request) in matching { pending.removeValue(forKey: id); request.continuation.resume(returning: image) }
    }
    func drain() {
        let all = pending.values
        pending.removeAll()
        all.forEach { $0.continuation.resume(returning: nil) }
    }
}

@MainActor final class OnlineLibraryService {
    private enum Constants { static let visibleThumbnailPrefetchLimit = 18 }
    var items: [OnlineLibraryVideoItem] = []
    var downloadedContent = DownloadedSnapshot()
    // ONLINE_PREFETCH_STATE
    // ONLINE_PREFETCH_METHODS
    func seed() {
        items = (0..<60).map { OnlineLibraryVideoItem(id: $0, previewThumbnailURL: URL(string: "https://fixture.test/\($0)")!) }
        itemIndexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }
    func requestCount(_ id: Int) -> Int { OLThumbnailCache.shared.history[items[id].previewThumbnailURL!, default: 0] }
    func requestID(_ id: Int) -> UUID? { thumbnailPrefetches[id]?.id }
    func requestCompleted(_ id: Int) -> Bool { thumbnailPrefetches[id]?.completed == true }
    var pendingCount: Int { thumbnailPrefetches.count }
}

nonisolated final class ThumbnailCacheRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
struct OLDownloadedEntry: Equatable {
    let id: Int
    let localURL: URL
    let fileSize: Int
    var thumbnailSourceKey: String?
}
@MainActor final class DownloadedCache {
    var ready: [String: NSImage] = [:]
    var failed: Set<String> = []
    var actualKeys: [String: String] = [:]
    var loads: [String: Int] = [:]
    var generations: [String: Int] = [:]
    var pending: [String: [(ThumbnailCacheRequestCancellation, (NSImage?) -> Void)]] = [:]
    var tokens: [String: ThumbnailCacheRequestCancellation] = [:]
    func cachedImage(forKey key: String) -> NSImage? { ready[key] }
    func load(_ key: String, cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (NSImage?) -> Void) {
        loads[key, default: 0] += 1
        tokens[key] = cancellation
        if let image = ready[key] { completion(image); return }
        if failed.contains(key) { completion(nil); return }
        generations[key, default: 0] += 1
        pending[key, default: []].append((cancellation, completion))
    }
    func complete(_ key: String, image: NSImage?) {
        if let image { ready[key] = image } else { failed.insert(key) }
        let all = pending.removeValue(forKey: key) ?? []
        for (cancellation, completion) in all where !cancellation.cancelled { completion(image) }
    }
}
@MainActor enum OLDownloadedThumbnailStore {
    static let sharedCache = DownloadedCache()
    static func cacheKey(for url: URL) -> String { url.path }
    static func prefetch(_ entry: OLDownloadedEntry, cancellation: ThumbnailCacheRequestCancellation,
        completion: @escaping (String, NSImage?) -> Void) {
        let hint = entry.thumbnailSourceKey ?? entry.localURL.path
        let key = sharedCache.actualKeys[hint] ?? hint
        sharedCache.load(key, cancellation: cancellation) { completion(key, $0) }
    }
}
@MainActor class DemandCard: NSCollectionViewItem {
    var begins = 0
    var ends = 0
    var unfinished = true
    override func loadView() { view = NSView() }
    func beginDisplayingThumbnail() { if unfinished { begins += 1 } }
    func endDisplayingThumbnail() { ends += 1 }
}
@MainActor final class AppKitOLDownloadsItem: DemandCard { static let reuseIdentifier = NSUserInterfaceItemIdentifier("downloads") }
@MainActor final class AppKitOLBrowserItem: DemandCard {}
@MainActor final class DemandCollection: NSCollectionView {
    var indexes = Set([IndexPath(item: 25, section: 0), IndexPath(item: 26, section: 0)])
    var cards: [NSCollectionViewItem] = []
    override func indexPathsForVisibleItems() -> Set<IndexPath> { indexes }
    override func visibleItems() -> [NSCollectionViewItem] { cards }
}
// Non-Pixabay providers are leaves; the actual adapter functions below retain
// canonical source lookup and all published-key/cancellation/ready semantics.
struct VideoWallpaper: Equatable { let id: String; let path: String }
struct SILWallpaper: Equatable { let id: String; let path: String }
struct SteamWorkshopBrowserItem: Equatable { let id: String }
struct SteamWorkshopDownloadRecord: Equatable {
    let id: String; var displayItem: SteamWorkshopBrowserItem? = nil; var videoURL: URL? = nil
}
struct DownloadedSnapshot { var entries: [OLDownloadedEntry] = [] }
final class WallpaperManager { var wallpapers: [VideoWallpaper] = [] }
final class SILService { var wallpapers: [SILWallpaper] = [] }
final class SteamWorkshopService { var downloads: [SteamWorkshopDownloadRecord] = []; var previewReloadToken = 0 }
enum AppKitWallpaperItem { static let reuseIdentifier = NSUserInterfaceItemIdentifier("video") }
enum SILGridItem { static let reuseID = NSUserInterfaceItemIdentifier("image") }
enum AppKitSteamWorkshopBrowserItem { static let reuseIdentifier = NSUserInterfaceItemIdentifier("steam") }
enum WallpaperLibraryUnavailableItem { static let reuseIdentifier = NSUserInterfaceItemIdentifier("missing") }
enum ThumbnailCacheRequestPriority { case visible, prefetch }
final class AppKitThumbnailProvider {
    func replacePrefetch(with: [VideoWallpaper], retainingVisible: [VideoWallpaper]) {}
    func updateVisiblePreviewDemand(with: [VideoWallpaper]) {}
}
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
final class OnlineImageGridItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("fixture-online-image")
}
final class SILThumbnailProvider {
    let cache = DownloadedCache()
    func load(path: String, priority: ThumbnailCacheRequestPriority, cancellation: ThumbnailCacheRequestCancellation,
              completion: @escaping (SILThumbnailLoadResult) -> Void) { preconditionFailure("non-Pixabay source") }
}
enum SteamWorkshopDownloadGridSupport {
    static func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem { .init(id: record.id) }
}
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord) -> (primary: URL?, fallback: URL?) { (nil, nil) }
final class SteamWorkshopPreviewState {
    struct Loaders { static func live(priority: ThumbnailCacheRequestPriority) -> Loaders { .init() } }
    init(loaders: Loaders) {}
    func configure(previewURL: URL?, fallbackImageURL: URL?, fallbackVideoURL: URL?, refreshToken: Int, maxPixelSize: Int) {}
    func reset() {}
}
@MainActor final class DownloadsDemandProbe {
    let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), online = OnlineLibraryService()
    let videoThumbnails = AppKitThumbnailProvider(), imageThumbnails = SILThumbnailProvider()
    var prefetches: [WallpaperReference: Prefetch] = [:]
    // ADAPTER_DEMAND_DECLARATIONS
    init() {
        online.downloadedContent.entries = (0..<60).map { id in
            .init(id: id, localURL: URL(fileURLWithPath: "/owned/\(id).mp4"), fileSize: 100, thumbnailSourceKey: "source-\(id)")
        }
    }
    func content() -> [WallpaperContentItem] {
        online.downloadedContent.entries.map { entry in
            let ref = WallpaperReference(provider: .pixabay, sourceID: String(entry.id))
            var metadata = WallpaperContentMetadata(); metadata.resourceRevision = entry.thumbnailSourceKey
            return .init(reference: ref, providerReference: ref, locator: .init(path: entry.localURL.path, mediaKind: .video),
                title: String(entry.id), kind: .video, publishedAvailability: .available, capabilities: [.play],
                metadata: metadata, acquisition: .idle, update: .idle, aliases: [])
        }
    }
    func apply(visible: [Int] = [25, 26], near: [Int] = [27, 24, 28, 23, 29, 22]) {
        let all = content()
        updateViewport(visible: visible.map { all[$0] }, prefetch: near.map { all[$0] })
    }
    func set(_ entry: OLDownloadedEntry) { online.downloadedContent.entries[entry.id] = entry }
    func cancellation(_ id: Int) -> ThumbnailCacheRequestCancellation? {
        let entry = online.downloadedContent.entries[id], hint = entry.thumbnailSourceKey ?? entry.localURL.path
        return OLDownloadedThumbnailStore.sharedCache.tokens[OLDownloadedThumbnailStore.sharedCache.actualKeys[hint] ?? hint]
    }
}
@MainActor final class UnifiedDownloadsDemandView: NSView {
    let demand = DownloadsDemandProbe()
    let controller = WallpaperLibraryGridController { collection, path, _, _ in
        collection.makeItem(withIdentifier: AppKitOLDownloadsItem.reuseIdentifier, for: path)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        controller.loadViewIfNeeded(); controller.view.frame = bounds
        controller.collection.register(AppKitOLDownloadsItem.self, forItemWithIdentifier: AppKitOLDownloadsItem.reuseIdentifier)
        controller.setCellVisible = { cell, visible in
            guard let card = cell as? AppKitOLDownloadsItem else { return }
            if visible { card.beginDisplayingThumbnail() } else { card.endDisplayingThumbnail() }
        }
        controller.onViewport = { [weak self] in self?.demand.updateViewport(visible: $0, prefetch: $1) }
        addSubview(controller.view)
        controller.update(page: .downloads, items: demand.content(), selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil)
        controller.view.layoutSubtreeIfNeeded()
    }
    required init?(coder: NSCoder) { nil }
    var cards: [AppKitOLDownloadsItem] { controller.collection.visibleItems().compactMap { $0 as? AppKitOLDownloadsItem } }
}
@MainActor final class AppKitOLBrowserContainerView: NSView {
    let collectionView = DemandCollection()
    let service = OnlineLibraryService()
    let flowLayout = NSCollectionViewFlowLayout()
    var orderedIDs = Array(0..<60)
    var lastPrioritizedVisibleIDs: [Int]?
    var lastPrioritizedPixelLimit = 0
    var isThumbnailDemandUpdateScheduled = false
    var thumbnailWindowObservation: NSKeyValueObservation?
    var thumbnailWindowObservers: [NSObjectProtocol] = []
    // BROWSER_LIFECYCLE
    // BROWSER_DEMAND_METHODS
}
nonisolated enum GridThumbnailDecoder {
    static func pixelLimit(width: CGFloat, scale: CGFloat) -> Int { 512 }
}

private enum Failure: Error { case assertion(String) }
@MainActor private func expect(_ condition: Bool, _ name: String) throws {
    if !condition { throw Failure.assertion(name) }
}
@MainActor private func pump(_ seconds: TimeInterval = 0.03) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.002)) }
}
@MainActor private func eventually(_ name: String, _ condition: () -> Bool) throws {
    for _ in 0..<500 { if condition() { return }; pump(0.002) }
    throw Failure.assertion("timeout: " + name)
}
@main private struct OnlineGridThumbnailDemandHarness {
    @MainActor static func online() throws {
        let service = OnlineLibraryService()
        service.seed()
        let cache = OLThumbnailCache.shared
        service.prioritizeVisibleItemIDs([25, 26])
        try eventually("near request") { service.requestCount(27) == 1 }
        let requestID = service.requestID(27)
        service.prioritizeVisibleItemIDs([27, 28])
        try expect(service.requestID(27) == requestID, "near->visible removed producer lease")
        service.prioritizeVisibleItemIDs([25, 26])
        cache.complete(service.items[27].previewThumbnailURL!, image: NSImage(size: NSSize(width: 1, height: 1)))
        try eventually("near completes") { service.requestCompleted(27) }
        cache.ready.removeAll()
        try expect(service.thumbnailPrefetchNeedsRefresh(), "identical viewport failed to notice decoded eviction")
        service.prioritizeVisibleItemIDs([25, 26])
        try eventually("evicted ready preheated again") { service.requestCount(27) == 2 }
        cache.complete(service.items[28].previewThumbnailURL!, image: nil)
        try eventually("bad source completes") { service.requestCompleted(28) }
        let failuresBefore = service.requestCount(28)
        service.prioritizeVisibleItemIDs([25, 26]); pump()
        try expect(service.requestCount(28) == failuresBefore, "terminal bad source retried without new epoch")
        cache.generation += 1
        service.prioritizeVisibleItemIDs([25, 26])
        try eventually("clear permits bad source retry") { service.requestCount(28) == failuresBefore + 1 }
        service.cancelThumbnailPrefetch()
        cache.drain()
    }

    @MainActor static func lifecycle() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 500, height: 500),
            styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let ancestor = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        window.contentView = ancestor
        window.orderFront(nil)
        let online = AppKitOLBrowserContainerView(frame: ancestor.bounds)
        online.service.seed()
        let onlineCard = AppKitOLBrowserItem()
        online.collectionView.cards = [onlineCard]
        ancestor.addSubview(online)
        online.viewDidUnhide(); pump()
        try eventually("online mounted demand") { online.service.pendingCount > 0 }
        let oldBegins = onlineCard.begins
        ancestor.isHidden = true; pump()
        try expect(online.service.pendingCount == 0 && onlineCard.ends > 0,
            "ancestor hide did not cancel online near and visible")
        let hiddenBegins = onlineCard.begins
        window.miniaturize(nil)
        try eventually("window miniaturized") { window.isMiniaturized }
        window.deminiaturize(nil)
        try eventually("window restored") { !window.isMiniaturized && window.isVisible }
        pump()
        try expect(online.service.pendingCount == 0 && onlineCard.begins == hiddenBegins,
            "window restore restarted hidden online category")
        ancestor.isHidden = false; pump()
        try expect(online.service.pendingCount > 0 && onlineCard.begins > oldBegins,
            "ancestor unhide did not restore online unfinished and near")
        window.orderOut(nil); pump()
        try expect(online.service.pendingCount == 0, "actual orderOut did not pause online")
        let orderedBegins = onlineCard.begins
        window.orderFront(nil); pump()
        try expect(online.service.pendingCount > 0 && onlineCard.begins > orderedBegins,
            "actual orderIn did not resume online")
        online.removeFromSuperview(); pump()
        try expect(online.service.pendingCount == 0, "detached online retained leases")
        OLThumbnailCache.shared.drain()

        let probe = DownloadsDemandProbe(), cache = OLDownloadedThumbnailStore.sharedCache
        probe.apply()
        try eventually("download near") { cache.generations["source-27", default: 0] == 1 }
        let token = probe.cancellation(27)!
        probe.apply(visible: [27, 28], near: [29, 26, 30, 25, 31, 24])
        try expect(probe.cancellation(27) === token && !token.cancelled, "download near->visible cancelled old producer")
        probe.apply()
        cache.complete("source-27", image: NSImage(size: NSSize(width: 1, height: 1)))
        cache.ready.removeAll()
        probe.apply()
        try expect(cache.generations["source-27", default: 0] == 2, "evicted downloaded preview not preheated")
        cache.complete("source-28", image: nil)
        let badLoads = cache.loads["source-28", default: 0]
        probe.apply()
        try expect(cache.loads["source-28", default: 0] == badLoads, "terminal failure repeatedly entered the cache")
        probe.set(.init(id: 27, localURL: URL(fileURLWithPath: "/owned/27.mp4"), fileSize: 100, thumbnailSourceKey: "replacement-27"))
        cache.actualKeys["replacement-27"] = "live-27"
        probe.apply()
        try expect(cache.generations["live-27", default: 0] == 1, "source replacement reused scan hint instead of live preview key")
        cache.complete("live-27", image: NSImage(size: NSSize(width: 1, height: 1)))
        probe.apply()
        try expect(cache.loads["live-27", default: 0] == 1, "actual ready key was lost and reloaded every viewport")
        cache.ready.removeValue(forKey: "live-27")
        probe.apply()
        try expect(cache.generations["live-27", default: 0] == 2, "actual key eviction did not reheat")
        probe.cancellation(27)?.cancel()
        probe.apply()
        try expect(cache.generations["live-27", default: 0] == 3, "source-invalidated consumer could not retry")
        let unpreparedURL = URL(fileURLWithPath: "/fixture/unprepared-29.mp4")
        probe.set(.init(id: 29, localURL: unpreparedURL, fileSize: 0, thumbnailSourceKey: nil))
        probe.apply()
        try expect(cache.loads[unpreparedURL.path, default: 0] == 1, "missing scan hint could not request")
        let movedURL = URL(fileURLWithPath: "/fixture/moved-29.mp4")
        probe.set(.init(id: 29, localURL: movedURL, fileSize: 0, thumbnailSourceKey: nil))
        probe.apply()
        try expect(cache.loads[movedURL.path, default: 0] == 1, "missing hint hid same-id source path replacement")
        probe.updateViewport(visible: [], prefetch: [])
        let downloads = UnifiedDownloadsDemandView(frame: ancestor.bounds)
        ancestor.addSubview(downloads); pump()
        try eventually("mounted actual unified downloads grid") { !downloads.demand.prefetches.isEmpty && !downloads.cards.isEmpty }
        let downloadedCard = downloads.cards.first!
        let starts = downloadedCard.begins
        let oldTokens = downloads.demand.prefetches.keys.compactMap { Int($0.sourceID) }.compactMap(downloads.demand.cancellation)
        ancestor.isHidden = true; pump()
        try expect(downloads.demand.prefetches.isEmpty && oldTokens.allSatisfy(\.cancelled)
            && downloadedCard.ends > 0, "ancestor hide did not cancel downloaded near and visible")
        ancestor.isHidden = false; pump()
        try expect(!downloads.demand.prefetches.isEmpty && downloadedCard.begins > starts,
            "unhide did not restore downloaded near and unfinished visible")
        window.orderOut(nil); pump()
        try expect(downloads.demand.prefetches.isEmpty, "actual orderOut did not pause downloads")
        let orderedDownloadBegins = downloadedCard.begins
        window.orderFront(nil); pump()
        try expect(!downloads.demand.prefetches.isEmpty && downloadedCard.begins > orderedDownloadBegins,
            "actual orderIn did not resume downloads")
        downloads.removeFromSuperview(); pump()
        try expect(downloads.demand.prefetches.isEmpty, "detached downloaded retained interests")
        window.close()
    }
    static func main() async throws {
        try online()
        try lifecycle()
        print("{\"onlineEvictionFailureAndNearVisible\":true,\"downloadEvictionSourceAndNearVisible\":true,\"ancestorHideUnhideAndDetach\":true}")
    }
}
