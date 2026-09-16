import Foundation

extension SteamWorkshopService {
    func loadMoreBrowserItemsIfNeeded() {
        if shouldUseSteamKitStructuredBrowse {
            loadMoreDiscoveryViaSteamKitIfNeeded()
        } else {
            loadMorePersonalViaSteamKitIfNeeded()
        }
    }

    /// 用户显式重试绕过短暂的自动滚动冷却，但仍复用当前 route、QueryKey、
    /// generation 与单请求 guard，不创建第二套分页执行权。
    func retryLoadingMoreBrowserItems() {
        guard browserState == .loaded,
              !isLoadingMoreBrowserItems,
              hasMoreBrowserItems else { return }
        consecutiveEmptyLoadMorePages = 0
        browserLoadMoreRetryAfter = .distantPast
        loadMoreBrowserItemsIfNeeded()
    }
}
