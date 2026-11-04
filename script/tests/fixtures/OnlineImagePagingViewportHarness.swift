import AppKit
import ImageIO
import UniformTypeIdentifiers

// Only transport, source values and geometry are leaves. The production viewport,
// footer and scroll-settled callback bodies are injected unmodified below.
struct WallpaperContentItem {
    let reference: String
    var publishedAvailability: Availability = .remote
    var locator = Locator()
    var metadata = Metadata()
    struct Locator { var path: String? }
    struct Metadata { var resourceRevision: String? }
    enum Availability { case remote, available; var isAvailable: Bool { self == .available } }
}
struct PagingArtwork {
    let id: String
    var firstAssetID: WallpaperContentItem { .init(reference: id) }
    var thumbnailURL: URL?; var previewURL: URL? { nil }
    var source: String { "fixture" }
}
@MainActor final class OnlineImageBrowserSession {
    struct State {
        var items: [PagingArtwork] = []
        var next: Int? = 2
        var notice: String?, error: String?
        var isLoading = false, hasLoaded = true
    }
    var state = State()
    var calls = 0, refreshes = 0
    func loadMore() { calls += 1; state.isLoading = true }
    func refresh() { refreshes += 1; state.isLoading = true }
}
nonisolated struct PagingRequest: Sendable { let cacheURL: URL }
struct PagingLibrary {
    func thumbnailRequest(url: URL, source: String) -> PagingRequest { .init(cacheURL: url) }
}
nonisolated final class RemoteLoadProbe: @unchecked Sendable {
    static let shared = RemoteLoadProbe()
    private let lock = NSLock()
    private var starts: Set<URL> = [], cancellations: Set<URL> = []
    func start(_ url: URL) { lock.lock(); starts.insert(url); lock.unlock() }
    func cancel(_ url: URL) { lock.lock(); cancellations.insert(url); lock.unlock() }
    func started(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return starts.contains(url) }
    func cancelled(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return cancellations.contains(url) }
}
actor OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()
    enum Priority { case prefetch }
    nonisolated func hasReadyImage(for remote: PagingRequest, request: ThumbnailRequest) -> Bool { false }
    func image(for remote: PagingRequest, request: ThumbnailRequest, priority: Priority) async -> NSImage? {
        RemoteLoadProbe.shared.start(remote.cacheURL)
        do { try await Task.sleep(nanoseconds: 10_000_000_000) }
        catch { RemoteLoadProbe.shared.cancel(remote.cacheURL) }
        return nil
    }
}
@MainActor final class PagingGrid {
    let scrollView = WallpaperGridScrollView()
    var onScrollSettled: (() -> Void)?
}
@MainActor final class PagingProbe {
    let session = OnlineImageBrowserSession(), library = PagingLibrary(), grid = PagingGrid()
    var shown = true, acceptsInput = true
    // PRODUCTION_PREFETCH_RECORD
    let localThumbnails = SILThumbnailProvider()
    var prefetched: [String: Prefetch] = [:]
    var artworks: [String: PagingArtwork] = [:]
    var autoLoadedCount: Int?
    func artwork(_ content: WallpaperContentItem) -> PagingArtwork? { artworks[content.reference] }
    func bind() {
        // PRODUCTION_REFRESH
        // PRODUCTION_SCROLL_SETTLED
    }
    // PRODUCTION_VIEWPORT
    // PRODUCTION_CANCEL_PREFETCH
    // PRODUCTION_FOOTER
}
// PRODUCTION_SIL_STORE
@main struct PagingViewportHarness {
    @MainActor static func wait(_ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(4)
        while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        return condition()
    }
    @MainActor static func main() throws {
        let probe = PagingProbe(); probe.bind()
        let request = ThumbnailRequest(width: 320, height: 320, mode: .fill)
        let a = WallpaperContentItem(reference: "1"), b = WallpaperContentItem(reference: "2")
        probe.session.state.items = [.init(id: "1"), .init(id: "2")]
        var checks: [String: Bool] = [:]
        probe.viewport([a], [b], request: request)
        checks["nearby-last-item-does-not-prefetch-another-data-page"] = probe.session.calls == 0
        probe.viewport([b], [], request: request)
        checks["visible-last-item-loads-one-page"] = probe.session.calls == 1
        probe.session.state.isLoading = false; probe.session.state.error = "failed"
        probe.viewport([b], [], request: request)
        checks["failed-page-cannot-self-trigger-a-render-retry-loop"] = probe.session.calls == 1
        probe.grid.onScrollSettled?(); probe.viewport([b], [], request: request)
        checks["next-real-scroll-retries-failed-last-page"] = probe.session.calls == 2
        probe.session.state.isLoading = false; probe.session.state.error = nil; probe.session.state.next = 3
        probe.viewport([b], [], request: request)
        checks["zero-new-items-do-not-self-drain-continuation"] = probe.session.calls == 2
        probe.grid.onScrollSettled?(); probe.viewport([b], [], request: request)
        checks["zero-new-items-retain-user-scroll-continuation"] = probe.session.calls == 3
        probe.session.state.items = []; probe.session.state.isLoading = false; probe.autoLoadedCount = nil
        probe.viewport([], [], request: request)
        let emptyCalls = probe.session.calls
        probe.session.state.isLoading = false; probe.session.state.next = 4; probe.viewport([], [], request: request)
        checks["filtered-empty-page-auto-continues-once-without-draining"] = emptyCalls == 4 && probe.session.calls == emptyCalls
        probe.grid.onScrollSettled?(); probe.viewport([], [], request: request)
        checks["filtered-empty-page-can-continue-on-next-gesture"] = probe.session.calls == emptyCalls + 1
        probe.session.state.isLoading = false; probe.session.state.next = nil; probe.session.state.error = "initial failure"
        probe.grid.onScrollSettled?()
        checks["first-page-failure-can-retry-by-scrolling-with-no-button"] = probe.session.refreshes == 1
        probe.acceptsInput = false; probe.grid.onScrollSettled?()
        checks["modal-scroll-cannot-retry-underlying-page"] = probe.session.refreshes == 1
        probe.shown = false; probe.session.state.isLoading = false; probe.session.state.next = 5
        probe.viewport([], [], request: request)
        checks["hidden-browser-does-not-paginate"] = probe.session.calls == emptyCalls + 1
        probe.session.state.error = nil; probe.session.state.isLoading = true
        checks["initial-loading-has-no-pagination-footer"] = probe.footerText(probe.session.state, count: 0) == nil
        checks["loading-footer-is-passive-status"] = probe.footerText(probe.session.state, count: 2) == "正在加载更多项目"
        probe.session.state.isLoading = false; probe.session.state.error = "failure"
        checks["empty-failure-has-no-pagination-footer"] = probe.footerText(probe.session.state, count: 0) == nil
        checks["failure-footer-describes-real-scroll-retry"] = probe.footerText(probe.session.state, count: 2)?.contains("继续下滑可重试") == true
        probe.session.state.error = nil
        checks["empty-result-has-no-pagination-footer"] = probe.footerText(probe.session.state, count: 0) == nil
        checks["loaded-footer-counts-current-source-items"] = probe.footerText(probe.session.state, count: 24) == "已加载 24 个作品"
        probe.shown = true; probe.acceptsInput = true
        let beforePull = probe.session.refreshes
        probe.grid.scrollView.onRefresh?()
        checks["shared-online-browser-refresh-dispatches-to-its-current-source"] = probe.session.refreshes == beforePull + 1
        probe.acceptsInput = false; probe.grid.scrollView.onRefresh?()
        checks["blocked-online-browser-cannot-submit-refresh"] = probe.session.refreshes == beforePull + 1
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            checks["shared-online-browser-installs-the-native-refresh-controller"] = probe.grid.scrollView.refreshController != nil
        }
        #endif
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("paging-local-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("same-local.png")
        let context = CGContext(data: nil, width: 512, height: 384, bitsPerComponent: 8, bytesPerRow: 2048,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 512, height: 384))
        let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); precondition(CGImageDestinationFinalize(destination))
        var local = WallpaperContentItem(reference: "local", publishedAvailability: .available)
        local.locator.path = path.path; local.metadata.resourceRevision = "v1"
        probe.shown = true; probe.session.state.next = nil; probe.session.state.isLoading = false
        probe.viewport([], [local], request: request)
        checks["downloaded-local-nearby-uses-real-sil-request"] = wait {
            probe.localThumbnails.cache.hasCachedResult(forKey: path.path, request: request)
        } && probe.prefetched[local.reference]?.request == request
        let lease = probe.prefetched[local.reference]!
        probe.viewport([], [local], request: request)
        checks["unchanged-local-nearby-retains-its-original-interest"] = probe.prefetched[local.reference] === lease
        probe.viewport([local], [], request: request)
        checks["local-nearby-to-visible-retains-the-original-interest-before-card-join"] = probe.prefetched[local.reference] === lease
        let consumer = ThumbnailCacheRequestCancellation()
        var independent: SILThumbnailLoadResult?
        probe.localThumbnails.load(path: path.path, request: request, cancellation: consumer) { independent = $0 }
        checks["local-ready-result-is-shared-with-a-visible-consumer"] = independent != nil
        probe.viewport([], [], request: request)
        checks["local-exit-withdraws-only-its-own-interest"] = probe.prefetched.isEmpty && !consumer.cancelled
            && probe.localThumbnails.cache.hasCachedResult(forKey: path.path, request: request)
        let remoteURL = URL(string: "https://fixture.invalid/controlled-remote")!
        let remote = WallpaperContentItem(reference: "remote")
        probe.artworks[remote.reference] = .init(id: remote.reference, thumbnailURL: remoteURL)
        probe.viewport([], [remote], request: request)
        checks["remote-nearby-still-enters-the-original-task-route"] = wait { RemoteLoadProbe.shared.started(remoteURL) }
        let remoteLease = probe.prefetched[remote.reference]
        probe.viewport([remote], [], request: request)
        checks["pending-remote-nearby-to-visible-keeps-original-producer-interest"] = remoteLease != nil
            && probe.prefetched[remote.reference] === remoteLease
        probe.viewport([], [], request: request)
        checks["remote-exit-still-cancels-its-original-task"] = wait { RemoteLoadProbe.shared.cancelled(remoteURL) }
        probe.viewport([local, remote], [], request: request)
        checks["visible-only-items-do-not-start-new-prefetch-interests"] = probe.prefetched.isEmpty
        let changingURL = URL(string: "https://fixture.invalid/changing-remote")!
        let replacementURL = URL(string: "https://fixture.invalid/replacement-remote")!
        let changing = WallpaperContentItem(reference: "changing")
        probe.artworks[changing.reference] = .init(id: changing.reference, thumbnailURL: changingURL)
        probe.viewport([], [changing], request: request)
        checks["source-replacement-control-starts-a-real-pending-remote-task"] = wait { RemoteLoadProbe.shared.started(changingURL) }
        probe.artworks[changing.reference] = .init(id: changing.reference, thumbnailURL: replacementURL)
        probe.viewport([changing], [], request: request)
        checks["changed-visible-source-revokes-old-interest-without-starting-prefetch"] = probe.prefetched.isEmpty
            && wait { RemoteLoadProbe.shared.cancelled(changingURL) } && !RemoteLoadProbe.shared.started(replacementURL)
        probe.viewport([], [local], request: request)
        let old = probe.prefetched[local.reference]!
        let larger = ThumbnailRequest(width: 640, height: 640, mode: .fill)
        probe.viewport([], [local], request: larger)
        checks["local-target-change-regrants-through-the-same-owner"] = probe.prefetched[local.reference] !== old
            && probe.prefetched[local.reference]?.request == larger
        probe.viewport([local], [], request: request)
        checks["changed-visible-target-revokes-old-interest-without-starting-prefetch"] = probe.prefetched.isEmpty
        probe.cancelPrefetch(); consumer.cancel()
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
