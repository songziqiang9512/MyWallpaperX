import AppKit

// Only the existing pixel/source leaves are controlled. The complete production
// consumer, identity, leases, drawing and tint source run below.
enum ThumbnailCacheRequestPriority { case visible, prefetch }
final class ThumbnailCacheRequestCancellation { var cancelled = false; func cancel() { cancelled = true } }
struct VideoWallpaper { let id: String }
final class WallpaperManager { var wallpapers: [VideoWallpaper] = [] }
final class AppKitThumbnailProvider {
    static var ids: [String] = []; static var priorities: [ThumbnailCacheRequestPriority] = []
    init(wallpaperManager: WallpaperManager) {}
    func loadThumbnail(for row: VideoWallpaper, priority: ThumbnailCacheRequestPriority,
                       completion: @escaping (NSImage?) -> Void) -> ThumbnailCacheRequestCancellation {
        Self.ids.append(row.id); Self.priorities.append(priority); completion(.init(size: .init(width: 10, height: 10)))
        return .init()
    }
}
struct SILWallpaper { let id: String; let path: String }
final class SILService { var wallpapers: [SILWallpaper] = [] }
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
final class SILThumbnailProvider {
    static var paths: [String] = []
    func load(path: String, priority: ThumbnailCacheRequestPriority, cancellation: ThumbnailCacheRequestCancellation,
              completion: @escaping (SILThumbnailLoadResult) -> Void) {
        Self.paths.append(path); completion(.image(.init(size: .init(width: 10, height: 10))))
    }
}
struct SteamWorkshopBrowserItem { let id: String }
struct SteamWorkshopDownloadRecord { let id: String; var displayItem: SteamWorkshopBrowserItem? { .init(id: id) }; var videoURL: URL? { nil } }
final class SteamWorkshopService { var downloads: [SteamWorkshopDownloadRecord] = [] }
enum SteamWorkshopDownloadGridSupport { static func fallbackDisplayItem(for row: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem { .init(id: row.id) } }
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord) -> (primary: URL?, fallback: URL?) { (URL(fileURLWithPath: "/preview/" + item.id), nil) }
final class SteamWorkshopPreviewState {
    struct Loaders { static func live(priority: ThumbnailCacheRequestPriority) -> Self { .init() } }
    static var pixels: [Int] = []; static var resets = 0
    var onChange: (() -> Void)?; var image: NSImage? = .init(size: .init(width: 10, height: 10))
    init(loaders: Loaders) {}
    func configure(previewURL: URL?, fallbackImageURL: URL?, fallbackVideoURL: URL?, maxPixelSize: Int) { Self.pixels.append(maxPixelSize); onChange?() }
    func reset() { Self.resets += 1 }
}
struct OLDownloadedEntry { let id: Int }
struct OLContent { var entries: [OLDownloadedEntry] = [] }
final class OnlineLibraryService { var downloadedContent = OLContent() }
enum OLDownloadedThumbnailStore {
    static var ids: [Int] = []
    static func prefetch(_ row: OLDownloadedEntry, cancellation: ThumbnailCacheRequestCancellation,
                         completion: @escaping (String, NSImage?) -> Void) { ids.append(row.id); completion("key", .init(size: .init(width: 10, height: 10))) }
}

final class ArtworkRequests {
    final class Request {
        let content: WallpaperContentItem
        let completion: (NSImage?) -> Void
        var cancelled = false
        init(_ content: WallpaperContentItem, _ completion: @escaping (NSImage?) -> Void) { self.content = content; self.completion = completion }
    }
    var requests: [Request] = []
    func load(_ content: WallpaperContentItem, _ completion: @escaping (NSImage?) -> Void) -> () -> Void {
        let request = Request(content, completion); requests.append(request)
        return { request.cancelled = true }
    }
}

@main enum WallpaperLibraryArtworkHarness {
    static func item(_ id: String, provider: WallpaperProvider = .videoLibrary, revision: String = "1",
                     available: Bool = true, canonical: WallpaperReference? = nil) -> WallpaperContentItem {
        let reference = WallpaperReference(provider: provider, sourceID: id)
        var metadata = WallpaperContentMetadata(); metadata.resourceRevision = revision
        return .init(reference: canonical ?? reference, providerReference: reference, locator: .init(path: "/" + id), title: id,
            kind: .video, publishedAvailability: available ? .available : .unavailable, capabilities: [.inspect, .play],
            metadata: metadata, acquisition: .idle, update: .idle, aliases: [])
    }
    static func solid(_ color: NSColor, size: NSSize = .init(width: 20, height: 10)) -> NSImage {
        let image = NSImage(size: size); image.lockFocus(); color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy); image.unlockFocus(); return image
    }
    static func color(_ image: NSImage?, _ x: Int, _ y: Int) -> NSColor? {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).colorAt(x: x * cg.width / 256, y: y * cg.height / 256)?.usingColorSpace(.deviceRGB)
    }
    static func main() {
        _ = NSApplication.shared
        var checks: [String: Bool] = [:]
        let requests = ArtworkRequests(), provider = WallpaperLibraryArtworkProvider(loader: { requests.load($0, $1) })
        var catalog = Dictionary(uniqueKeysWithValues: (0..<8).map { let row = item(String($0)); return (row.providerReference, row) })
        let firstID = UUID(), secondID = UUID(), emptyID = UUID()
        var first = WallpaperPlaylistDirectoryEntry(id: firstID, name: "First", count: 8, coverReference: item("0").reference)
        let second = WallpaperPlaylistDirectoryEntry(id: secondID, name: "Second", count: 1, coverReference: item("7").reference)
        let empty = WallpaperPlaylistDirectoryEntry(id: emptyID, name: "Empty", count: 0, coverReference: nil)
        var rendered: [UUID: WallpaperPlaylistArtwork] = [:]
        provider.onCoversChanged = { rendered = $0 }
        var resolutionBatches = 0
        func update() { provider.update(entries: [first, second, empty]) { refs in resolutionBatches += 1; return refs.compactMap { catalog[$0] } } }
        update()
        checks["directory-snapshot-does-not-eagerly-load-every-playlist"] = requests.requests.isEmpty
        let sidebar = UUID(), directory = UUID()
        provider.setDemand(sourceToken: sidebar, playlistIDs: [firstID, emptyID, UUID()])
        checks["many-members-demand-only-the-original-first-and-no-empty-or-unknown-id"] = requests.requests.map { $0.content.reference.sourceID } == ["0"]
        provider.setDemand(sourceToken: directory, playlistIDs: [firstID])
        checks["sidebar-and-directory-share-one-cover-and-request"] = requests.requests.count == 1
        checks["visible-demand-uses-one-shared-catalog-resolution-per-batch"] = resolutionBatches == 2
        let red = solid(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let green = solid(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)), blue = solid(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        requests.requests[0].completion(red)
        checks["one-image-fills-the-full-square-with-aspect-fill"] = (color(rendered[firstID]?.image, 250, 250)?.redComponent ?? 0) > 0.9
        let oldImage = rendered[firstID]?.image
        requests.requests[0].completion(red)
        checks["same-source-image-echo-does-not-recompose"] = rendered[firstID]?.image === oldImage
        first = .init(id: firstID, name: "Renamed", count: 9, coverReference: first.coverReference)
        update()
        checks["rename-count-and-later-member-updates-preserve-pixels-and-lease"] = requests.requests.count == 1 && rendered[firstID]?.image === oldImage
        provider.setDemand(sourceToken: sidebar, playlistIDs: [])
        checks["one-hidden-consumer-cannot-cancel-other-visible-demand"] = !requests.requests[0].cancelled
        provider.setDemand(sourceToken: directory, playlistIDs: [])
        checks["last-hidden-consumer-releases-original-lease-and-pixels"] = requests.requests[0].cancelled && rendered.isEmpty
        requests.requests[0].completion(blue)
        checks["late-completion-cannot-resurrect-an-offscreen-cover"] = rendered.isEmpty
        provider.setDemand(sourceToken: sidebar, playlistIDs: [firstID])
        let oldRequest = requests.requests.last!, before = requests.requests.count
        catalog[item("0").reference] = item("0", revision: "2")
        update()
        checks["same-reference-resource-replacement-cancels-original-generation"] = requests.requests.count == before + 1 && oldRequest.cancelled
        let stableCount = requests.requests.count
        catalog[item("0").reference] = item("0", revision: "2", canonical: item("canonical").reference)
        update()
        checks["canonical-alias-does-not-reload-unchanged-provider-artwork"] = requests.requests.count == stableCount
        let retired = requests.requests.last!
        first = .init(id: firstID, name: first.name, count: 8, coverReference: item("3").reference)
        update()
        checks["manual-first-change-requests-exactly-the-new-first"] = requests.requests.count == stableCount + 1 && requests.requests.last?.content.providerReference.sourceID == "3" && retired.cancelled
        retired.completion(red)
        checks["obsolete-first-cannot-paint-the-new-first"] = rendered[firstID]?.image == nil
        requests.requests.last!.completion(nil)
        checks["failed-first-does-not-request-a-healthy-later-member"] = requests.requests.count == stableCount + 1 && rendered[firstID]?.image == nil
        catalog[item("3").reference] = item("3", available: false)
        update()
        checks["unavailable-first-stays-placeholder-with-healthy-later-catalog-items"] = requests.requests.count == stableCount + 1 && rendered[firstID]?.image == nil
        provider.setDemand(sourceToken: sidebar, playlistIDs: [])
        provider.updateCurrentDirectory(firstPlaylistID: secondID)
        checks["directory-tint-demands-only-first-real-list-without-visible-card"] = requests.requests.last?.content.reference.sourceID == "7"
        let tintCount = requests.requests.count, requestRevision = provider.currentListTintSource.request?.revision
        var tintImage: NSImage?
        let tintLease = provider.currentListTintSource.request!.load { tintImage = $0 }
        requests.requests.last!.completion(red)
        let coloredRevision = provider.currentListTintSource.request?.revision
        provider.updateCurrentDirectory(firstPlaylistID: secondID)
        checks["directory-completion-invalidates-same-tint-source-without-recursive-loading"] = requestRevision != coloredRevision && requests.requests.count == tintCount
        let secondTintLease = provider.currentListTintSource.request!.load { tintImage = $0 }
        checks["directory-tint-and-card-use-identical-image"] = tintImage === rendered[secondID]?.image
        tintLease(); secondTintLease()
        provider.updateCurrentList(first: item("0"))
        checks["wallpaper-tint-releases-directory-only-cover-demand"] = requests.requests[tintCount - 1].cancelled && rendered.isEmpty
        let firstTint = provider.currentListTintSource.request!.revision
        provider.updateCurrentList(first: item("0"))
        checks["same-first-does-not-resample-on-scroll-or-selection"] = firstTint == provider.currentListTintSource.request!.revision
        provider.updateCurrentList(first: item("1"))
        checks["sort-changing-first-updates-original-tint-identity"] = firstTint != provider.currentListTintSource.request!.revision
        provider.updateCurrentList(first: nil)
        checks["empty-page-clears-tint-to-native-background"] = provider.currentListTintSource.request == nil
        let modeRequests = ArtworkRequests(), modeProvider = WallpaperLibraryArtworkProvider(loader: { modeRequests.load($0, $1) })
        var modeRendered: [UUID: WallpaperPlaylistArtwork] = [:]
        modeProvider.onCoversChanged = { modeRendered = $0 }
        modeProvider.update(entries: [second]) { refs in refs.compactMap { catalog[$0] } }
        modeProvider.updateCurrentDirectory(firstPlaylistID: secondID)
        let modeOnlyRequest = modeRequests.requests[0]
        modeProvider.updateCurrentDirectory(firstPlaylistID: nil)
        modeOnlyRequest.completion(red)
        checks["native-mode-releases-directory-tint-only-lease-and-rejects-late-cover"] = modeOnlyRequest.cancelled
            && modeProvider.currentListTintSource.request == nil && modeRendered.isEmpty
        let realVisibleDemand = UUID()
        modeProvider.setDemand(sourceToken: realVisibleDemand, playlistIDs: [secondID])
        let realVisibleRequest = modeRequests.requests[1]
        modeProvider.updateCurrentDirectory(firstPlaylistID: secondID)
        modeProvider.updateCurrentDirectory(firstPlaylistID: nil)
        checks["native-mode-keeps-real-visible-directory-cover-lease"] = !realVisibleRequest.cancelled && modeRequests.requests.count == 2
        modeProvider.updateCurrentDirectory(firstPlaylistID: secondID)
        checks["returning-to-tint-shares-existing-visible-cover-without-reloading"] = !realVisibleRequest.cancelled
            && modeProvider.currentListTintSource.request?.identity.itemID == "playlist-cover:" + secondID.uuidString && modeRequests.requests.count == 2
        modeProvider.updateCurrentDirectory(firstPlaylistID: nil)
        modeProvider.setDemand(sourceToken: realVisibleDemand, playlistIDs: [])
        checks["native-mode-last-real-demand-retirement-releases-original-lease"] = realVisibleRequest.cancelled
        provider.updateCurrentList(first: item("é")); let unicodeRevision = provider.currentListTintSource.request!.revision
        provider.updateCurrentList(first: item("e\u{301}"))
        checks["opaque-unicode-source-identity-is-not-canonicalized"] = unicodeRevision != provider.currentListTintSource.request!.revision
        var transient: WallpaperLibraryArtworkProvider? = .init(loader: { requests.load($0, $1) })
        transient!.update(entries: [second]) { refs in refs.compactMap { catalog[$0] } }; transient!.setDemand(sourceToken: UUID(), playlistIDs: [secondID])
        let last = requests.requests.last!; transient = nil
        checks["provider-teardown-cancels-unfinished-original-consumer"] = last.cancelled
        catalog[item("3").reference] = item("3")
        var synchronous: WallpaperLibraryArtworkProvider!
        let syncToken = UUID()
        var synchronousStarts = 0, synchronousCancels = 0
        synchronous = .init(loader: { _, completion in synchronousStarts += 1; completion(red); return { synchronousCancels += 1 } })
        synchronous.update(entries: [first]) { refs in refs.compactMap { catalog[$0] } }
        synchronous.onCoversChanged = { covers in if !covers.isEmpty { synchronous.setDemand(sourceToken: syncToken, playlistIDs: []) } }
        synchronous.setDemand(sourceToken: syncToken, playlistIDs: [firstID])
        checks["synchronous-memory-hit-revoking-demand-cancels-returned-lease"] = synchronousStarts == 1 && synchronousCancels == 1
        synchronous.onCoversChanged = nil
        let alphaRequests = ArtworkRequests(), alphaProvider = WallpaperLibraryArtworkProvider(loader: { alphaRequests.load($0, $1) })
        var alphaCover: NSImage?
        alphaProvider.onCoversChanged = { alphaCover = $0[firstID]?.image }
        alphaProvider.update(entries: [first]) { refs in refs.compactMap { catalog[$0] } }
        let alphaToken = UUID(); alphaProvider.setDemand(sourceToken: alphaToken, playlistIDs: [firstID])
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            alphaRequests.requests[0].completion(solid(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.35)))
        }
        let translucent = color(alphaCover, 100, 100), firstAlphaCover = alphaCover
        checks["source-alpha-is-not-baked-into-dark-background"] = translucent.map { $0.redComponent > 0.9 && $0.alphaComponent > 0.3 && $0.alphaComponent < 0.4 } == true
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { alphaProvider.update(entries: [first]) { refs in refs.compactMap { catalog[$0] } } }
        checks["appearance-does-not-rerequest-transparent-artwork"] = alphaRequests.requests.count == 1 && alphaCover === firstAlphaCover
        alphaRequests.requests[0].completion(solid(.clear))
        checks["fully-transparent-pixels-stay-transparent"] = color(alphaCover, 200, 200)?.alphaComponent == 0
        alphaProvider.setDemand(sourceToken: alphaToken, playlistIDs: [])
        let customRequests = ArtworkRequests(), custom = WallpaperLibraryArtworkProvider(loader: { customRequests.load($0, $1) })
        let customID = UUID(), customToken = UUID()
        var customCompletion: ((NSImage?) -> Void)?, customCancelCount = 0, customStarts: [UUID] = []
        var customRendered: WallpaperPlaylistArtwork?
        custom.loadCustomCover = { id, done in customStarts.append(id); customCompletion = done; return { customCancelCount += 1 } }
        custom.onCoversChanged = { customRendered = $0[firstID] }
        custom.update(entries: [first], customCovers: [firstID: customID]) { refs in refs.compactMap { catalog[$0] } }
        custom.setDemand(sourceToken: customToken, playlistIDs: [firstID]); customCompletion?(green)
        checks["custom-cover-loads-one-owned-asset-with-zero-member-leases"] = customStarts == [customID] && customRequests.requests.isEmpty && customRendered?.isCustom == true && (color(customRendered?.image, 240, 240)?.greenComponent ?? 0) > 0.9
        let headerOnly = UUID(), customImage = customRendered?.image
        custom.setDemand(sourceToken: headerOnly, playlistIDs: [firstID]); custom.setDemand(sourceToken: customToken, playlistIDs: [])
        checks["header-keeps-custom-cover-after-other-consumers-release"] = customCancelCount == 0 && customRendered?.image === customImage
        let oldCustomCompletion = customCompletion
        custom.update(entries: [first]) { refs in refs.compactMap { catalog[$0] } }; oldCustomCompletion?(red)
        checks["restoring-auto-rejects-late-custom-pixels"] = customCancelCount == 1 && customRequests.requests.count == 1 && customRendered?.isCustom == false && customRendered?.image == nil
        custom.setDemand(sourceToken: headerOnly, playlistIDs: [])
        let resetProvider = WallpaperLibraryArtworkProvider(loader: { requests.load($0, $1) })
        var resetLoads: [(NSImage?) -> Void] = [], resetCancels = 0, resetImage: NSImage?
        resetProvider.loadCustomCover = { _, done in resetLoads.append(done); return { resetCancels += 1 } }
        resetProvider.onCoversChanged = { resetImage = $0[firstID]?.image }
        let resetToken = UUID(), firstEpoch = UUID(), nextEpoch = UUID()
        resetProvider.update(entries: [first], resetEpoch: firstEpoch, customCovers: [firstID: customID]) { _ in [] }
        resetProvider.setDemand(sourceToken: resetToken, playlistIDs: [firstID]); resetLoads[0](red)
        let oldResetImage = resetImage
        resetProvider.update(entries: [first], resetEpoch: nextEpoch, customCovers: [firstID: customID]) { _ in [] }; resetLoads[0](blue)
        checks["reset-same-ids-retires-old-lease-and-image"] = resetLoads.count == 2 && resetCancels == 1 && oldResetImage != nil && resetImage == nil
        resetLoads[1](green)
        checks["new-epoch-same-asset-loads-new-bytes"] = (color(resetImage, 240, 240)?.greenComponent ?? 0) > 0.9
        resetProvider.setDemand(sourceToken: resetToken, playlistIDs: [])

        let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), online = OnlineLibraryService()
        manager.wallpapers = [.init(id: "v")]; images.wallpapers = [.init(id: "i", path: "/image")]
        steam.downloads = [.init(id: "s")]; online.downloadedContent.entries = [.init(id: 7)]
        let live = WallpaperLibraryArtworkProvider(manager: manager, images: images, steam: steam, online: online)
        var leases: [() -> Void] = [], completions = 0
        for content in [item("v"), item("i", provider: .staticImageLibrary), item("s", provider: .steamWorkshop), item("7", provider: .pixabay)] {
            leases.append(live.load(content: content) { if $0 != nil { completions += 1 } })
        }
        checks["live-composition-delegates-to-original-four-thumbnail-owners"] = completions == 4 && AppKitThumbnailProvider.ids == ["v"]
            && SILThumbnailProvider.paths == ["/image"] && SteamWorkshopPreviewState.pixels == [256] && OLDownloadedThumbnailStore.ids == [7]
        let invalid = live.load(content: item("007", provider: .pixabay)) { _ in }
        invalid(); leases.forEach { $0() }
        checks["live-original-cancellation-and-canonical-numeric-source-boundaries"] = SteamWorkshopPreviewState.resets == 1 && OLDownloadedThumbnailStore.ids == [7]
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
