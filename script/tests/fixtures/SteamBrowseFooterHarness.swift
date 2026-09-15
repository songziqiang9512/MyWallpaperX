import AppKit

@main
struct SteamBrowseFooterHarness {
    static func main() {
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
        ) == .hidden, "a page-level error belongs to the full-page state when no old page exists")

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
        print("Steam browse failure footer state PASS")
    }
}
