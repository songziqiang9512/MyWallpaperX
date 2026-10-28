import Foundation

// Only transport, source values and geometry are leaves. The production viewport,
// footer and scroll-settled callback bodies are injected unmodified below.
struct WallpaperContentItem {
    let reference: String
    var publishedAvailability: Availability = .remote
    enum Availability { case remote; var isAvailable: Bool { false } }
}
struct PagingArtwork {
    let id: String
    var firstAssetID: WallpaperContentItem { .init(reference: id) }
    var thumbnailURL: URL? { nil }; var previewURL: URL? { nil }
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
struct PagingLibrary {
    func thumbnailRequest(url: URL, source: String) -> URL { url }
}
actor OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()
    enum Priority { case prefetch }
    func image(for request: URL, maxPixelSize: Int, priority: Priority) {}
}
@MainActor final class PagingGrid { var onScrollSettled: (() -> Void)? }
@MainActor final class PagingProbe {
    let session = OnlineImageBrowserSession(), library = PagingLibrary(), grid = PagingGrid()
    var shown = true, acceptsInput = true
    var prefetched: [String: Task<Void, Never>] = [:]
    var autoLoadedCount: Int?, prefetchPixelSize = 0
    let thumbnailPixelSize = 512
    func artwork(_ content: WallpaperContentItem) -> PagingArtwork? { nil }
    func bind() {
        // PRODUCTION_SCROLL_SETTLED
    }
    // PRODUCTION_VIEWPORT
    // PRODUCTION_CANCEL_PREFETCH
    // PRODUCTION_FOOTER
}
@main struct PagingViewportHarness {
    @MainActor static func main() throws {
        let probe = PagingProbe(); probe.bind()
        let a = WallpaperContentItem(reference: "1"), b = WallpaperContentItem(reference: "2")
        probe.session.state.items = [.init(id: "1"), .init(id: "2")]
        var checks: [String: Bool] = [:]
        probe.viewport([a], [b])
        checks["nearby-last-item-does-not-prefetch-another-data-page"] = probe.session.calls == 0
        probe.viewport([b], [])
        checks["visible-last-item-loads-one-page"] = probe.session.calls == 1
        probe.session.state.isLoading = false; probe.session.state.error = "failed"
        probe.viewport([b], [])
        checks["failed-page-cannot-self-trigger-a-render-retry-loop"] = probe.session.calls == 1
        probe.grid.onScrollSettled?(); probe.viewport([b], [])
        checks["next-real-scroll-retries-failed-last-page"] = probe.session.calls == 2
        probe.session.state.isLoading = false; probe.session.state.error = nil; probe.session.state.next = 3
        probe.viewport([b], [])
        checks["zero-new-items-do-not-self-drain-continuation"] = probe.session.calls == 2
        probe.grid.onScrollSettled?(); probe.viewport([b], [])
        checks["zero-new-items-retain-user-scroll-continuation"] = probe.session.calls == 3
        probe.session.state.items = []; probe.session.state.isLoading = false; probe.autoLoadedCount = nil
        probe.viewport([], [])
        let emptyCalls = probe.session.calls
        probe.session.state.isLoading = false; probe.session.state.next = 4; probe.viewport([], [])
        checks["filtered-empty-page-auto-continues-once-without-draining"] = emptyCalls == 4 && probe.session.calls == emptyCalls
        probe.grid.onScrollSettled?(); probe.viewport([], [])
        checks["filtered-empty-page-can-continue-on-next-gesture"] = probe.session.calls == emptyCalls + 1
        probe.session.state.isLoading = false; probe.session.state.next = nil; probe.session.state.error = "initial failure"
        probe.grid.onScrollSettled?()
        checks["first-page-failure-can-retry-by-scrolling-with-no-button"] = probe.session.refreshes == 1
        probe.acceptsInput = false; probe.grid.onScrollSettled?()
        checks["modal-scroll-cannot-retry-underlying-page"] = probe.session.refreshes == 1
        probe.shown = false; probe.session.state.isLoading = false; probe.session.state.next = 5
        probe.viewport([], [])
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
