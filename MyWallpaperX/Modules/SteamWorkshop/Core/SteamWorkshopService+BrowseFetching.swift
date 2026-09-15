import Foundation

extension SteamWorkshopService {
    func navigateToBrowse() {
        browserFetchTask?.cancel()
        selectedItemDetailTask?.cancel()
        currentWorkshopItemID = nil
        navigationVersion += 1
        currentPageTitle = browseContext.isAuthorWorkshop ? browseContext.title : source.pageTitle
        fetchBrowserItems()
    }

    func refresh() {
        fetchBrowserItems(forceRefresh: true)
    }

    func prepareForBrowserEntry() {
        guard !isLoadingMoreBrowserItems, browserFetchTask == nil else { return }
        if browserItems.isEmpty || browserState == .idle {
            fetchBrowserItems(forceRefresh: true)
        }
    }

    /// SK6.2: every product browse context is owned by the structured SteamKit
    /// store. There is no per-request fallback to the retired acquisition path.
    func fetchBrowserItems(forceRefresh: Bool = false) {
        if shouldUseSteamKitStructuredBrowse {
            fetchDiscoveryViaSteamKit(forceRefresh: forceRefresh)
        } else {
            fetchPersonalViaSteamKit(forceRefresh: forceRefresh)
        }
    }
}
