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
struct OLDownloadedEntry {
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
    func cachedImage(forKey key: String) -> NSImage? { ready[key] }
    func load(_ key: String, cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (NSImage?) -> Void) {
        loads[key, default: 0] += 1
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
@MainActor final class OnlineDownloadsBridge {
    static let shared = OnlineDownloadsBridge()
    var isActive = false
}
@MainActor class DemandCard: NSCollectionViewItem {
    var begins = 0
    var ends = 0
    var unfinished = true
    override func loadView() { view = NSView() }
    func beginDisplayingThumbnail() { if unfinished { begins += 1 } }
    func endDisplayingThumbnail() { ends += 1 }
}
@MainActor final class AppKitOLDownloadsItem: DemandCard {}
@MainActor final class AppKitOLBrowserItem: DemandCard {}
@MainActor final class DemandCollection: NSCollectionView {
    var indexes = Set([IndexPath(item: 25, section: 0), IndexPath(item: 26, section: 0)])
    var cards: [NSCollectionViewItem] = []
    override func indexPathsForVisibleItems() -> Set<IndexPath> { indexes }
    override func visibleItems() -> [NSCollectionViewItem] { cards }
}
@MainActor final class AppKitOLDownloadsContainerView: NSView {
    let collectionView = DemandCollection()
    var thumbnailDemand = OLDownloadedThumbnailDemandState()
    var thumbnailWindowObservation: NSKeyValueObservation?
    var thumbnailWindowObservers: [NSObjectProtocol] = []
    var orderedIDs = Array(0..<60)
    var lastComputedColumns = 3
    var entriesByID = Dictionary(uniqueKeysWithValues: (0..<60).map { id in
        (id, OLDownloadedEntry(id: id, localURL: URL(fileURLWithPath: "/owned/\(id).mp4"),
            fileSize: 100, thumbnailSourceKey: "source-\(id)"))
    })
    // DOWNLOADS_LIFECYCLE
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

        let downloads = AppKitOLDownloadsContainerView(frame: ancestor.bounds)
        let downloadedCard = AppKitOLDownloadsItem()
        downloads.collectionView.cards = [downloadedCard]
        ancestor.addSubview(downloads)
        downloads.viewDidUnhide(); pump()
        let cache = OLDownloadedThumbnailStore.sharedCache
        try eventually("download near") { cache.generations["source-27", default: 0] == 1 }
        let token = downloads.thumbnailDemand.requests[27]!.cancellation
        downloads.collectionView.indexes = [IndexPath(item: 27, section: 0), IndexPath(item: 28, section: 0)]
        downloads.scheduleThumbnailDemand(); pump()
        try expect(downloads.thumbnailDemand.requests[27]?.cancellation === token && !token.cancelled,
            "download near->visible cancelled old producer")
        downloads.collectionView.indexes = [IndexPath(item: 25, section: 0), IndexPath(item: 26, section: 0)]
        downloads.scheduleThumbnailDemand(); pump()
        cache.complete("source-27", image: NSImage(size: NSSize(width: 1, height: 1)))
        try expect(downloads.thumbnailDemand.requests[27]?.completed == true, "download completion not recorded")
        cache.ready.removeAll()
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.generations["source-27", default: 0] == 2, "evicted downloaded preview not preheated")
        cache.complete("source-28", image: nil)
        let badLoads = cache.loads["source-28", default: 0]
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.loads["source-28", default: 0] == badLoads, "terminal failure repeatedly entered the cache")
        downloads.entriesByID[27]?.thumbnailSourceKey = "replacement-27"
        cache.actualKeys["replacement-27"] = "live-27"
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.generations["live-27", default: 0] == 1, "source replacement reused scan hint instead of live preview key")
        cache.complete("live-27", image: NSImage(size: NSSize(width: 1, height: 1)))
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.loads["live-27", default: 0] == 1, "actual ready key was lost and reloaded every viewport")
        cache.ready.removeValue(forKey: "live-27")
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.generations["live-27", default: 0] == 2, "actual key eviction did not reheat")
        downloads.thumbnailDemand.requests[27]?.cancellation.cancel()
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.generations["live-27", default: 0] == 3, "source-invalidated consumer could not retry")
        let unpreparedURL = URL(fileURLWithPath: "/fixture/unprepared-29.mp4")
        downloads.entriesByID[29] = .init(id: 29, localURL: unpreparedURL, fileSize: 0, thumbnailSourceKey: nil)
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.loads[unpreparedURL.path, default: 0] == 1, "missing scan hint could not request")
        let movedURL = URL(fileURLWithPath: "/fixture/moved-29.mp4")
        downloads.entriesByID[29] = .init(id: 29, localURL: movedURL, fileSize: 0, thumbnailSourceKey: nil)
        downloads.scheduleThumbnailDemand(); pump()
        try expect(cache.loads[movedURL.path, default: 0] == 1, "missing hint hid same-id source path replacement")
        let starts = downloadedCard.begins
        let oldTokens = downloads.thumbnailDemand.requests.values.map(\.cancellation)
        ancestor.isHidden = true; pump()
        try expect(downloads.thumbnailDemand.requests.isEmpty && oldTokens.allSatisfy(\.cancelled)
            && downloadedCard.ends > 0, "ancestor hide did not cancel downloaded near and visible")
        ancestor.isHidden = false; pump()
        try expect(!downloads.thumbnailDemand.requests.isEmpty && downloadedCard.begins > starts,
            "unhide did not restore downloaded near and unfinished visible")
        window.orderOut(nil); pump()
        try expect(downloads.thumbnailDemand.requests.isEmpty, "actual orderOut did not pause downloads")
        let orderedDownloadBegins = downloadedCard.begins
        window.orderFront(nil); pump()
        try expect(!downloads.thumbnailDemand.requests.isEmpty && downloadedCard.begins > orderedDownloadBegins,
            "actual orderIn did not resume downloads")
        downloads.removeFromSuperview(); pump()
        try expect(downloads.thumbnailDemand.requests.isEmpty, "detached downloaded retained interests")
        window.close()
    }
    static func main() async throws {
        try online()
        try lifecycle()
        print("{\"onlineEvictionFailureAndNearVisible\":true,\"downloadEvictionSourceAndNearVisible\":true,\"ancestorHideUnhideAndDetach\":true}")
    }
}
