import AppKit

final class SteamBrowseRetryProbe {
    enum BrowserState { case loaded, loading, failed }
    var browserState = BrowserState.loaded
    var isLoadingMoreBrowserItems = false
    var hasMoreBrowserItems = true
    var consecutiveEmptyLoadMorePages = 3
    var browserLoadMoreRetryAfter = Date.distantFuture
    var calls = 0
    func loadMoreBrowserItemsIfNeeded() {
        precondition(consecutiveEmptyLoadMorePages == 0 && browserLoadMoreRetryAfter == .distantPast)
        calls += 1
    }
    // ACTUAL_RETRY
}

@main
struct SteamBrowseFooterHarness {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for state in [SteamBrowseRetryProbe.BrowserState.loaded, .loading, .failed] {
            for busy in [false, true] {
                for hasMore in [false, true] {
                    let retry = SteamBrowseRetryProbe()
                    retry.browserState = state; retry.isLoadingMoreBrowserItems = busy; retry.hasMoreBrowserItems = hasMore
                    retry.retryLoadingMoreBrowserItems()
                    let shouldRetry = state == .loaded && !busy && hasMore
                    precondition(retry.calls == (shouldRetry ? 1 : 0), "only a loaded, idle, continuing page may retry")
                    if !shouldRetry {
                        precondition(retry.consecutiveEmptyLoadMorePages == 3 && retry.browserLoadMoreRetryAfter == .distantFuture,
                                     "inactive/busy/exhausted retry cannot reset the current owner's state")
                    }
                }
            }
        }
        let ids = ["1", "2"]
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: nil,
            isLoadingMore: false,
            hasMore: true,
            itemIDs: ids
        ) == .ready)
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: "加载失败 · 重试",
            isLoadingMore: true,
            hasMore: true,
            itemIDs: ids
        ) == .loading, "active retry must replace the stale failure presentation")

        let failed = SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: "加载失败 · 重试",
            isLoadingMore: false,
            hasMore: true,
            itemIDs: ids
        )
        precondition(failed == .failed("加载失败 · 重试"))
        precondition(SteamWorkshopBrowserFooterSupport.text(for: failed) == "加载失败 · 重试")
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: "加载失败 · 重试",
            isLoadingMore: false,
            hasMore: false,
            itemIDs: ids
        ) == .exhausted, "a stale failure cannot override an exhausted result")
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: "加载失败 · 重试",
            isLoadingMore: false,
            hasMore: true,
            itemIDs: []
        ) == .failed("加载失败 · 重试"), "an empty filtered page must keep its continuation status")
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: nil, isLoadingMore: false, hasMore: true, itemIDs: []
        ) == .ready, "filtered empty pages must retain continuation status")
        precondition(SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: nil, isLoadingMore: false, hasMore: false, itemIDs: []
        ) == .hidden)

        let inset = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        let failedSize = SteamWorkshopBrowserFooterSupport.size(
            for: failed,
            boundsWidth: 600,
            sectionInset: inset
        )
        let readySize = SteamWorkshopBrowserFooterSupport.size(
            for: .ready,
            boundsWidth: 600,
            sectionInset: inset
        )
        precondition(failedSize.width == 580 && failedSize.height > readySize.height)
        let item = AppKitSteamWorkshopBrowserFooterItem()
        item.loadViewIfNeeded()
        SteamWorkshopBrowserFooterSupport.configure(item, state: .ready, itemCount: 24)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(item.view)
        precondition(!views.contains { $0 is NSButton || $0 is NSProgressIndicator })
        precondition(views.compactMap { $0 as? NSTextField }.first?.stringValue == "已加载 24 个作品")
        SteamWorkshopBrowserFooterSupport.configure(item, state: .loading, itemCount: 24)
        precondition(views.compactMap { $0 as? NSTextField }.first?.stringValue == "正在加载更多项目")
        print("Steam browse failure footer state PASS")
    }
}
