import AppKit

extension SteamWorkshopToolbarController {
    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .steamAuthorBack:
            configureAuthorBackItem()
            return authorBackToolbarItem
        case .steamSort:
            syncSortPopup()
            return sortToolbarItem
        case .steamPersonalList:
            syncPersonalListPopup()
            return personalListToolbarItem
        case .steamTrendingWindow:
            syncTrendingWindowPopup()
            return trendingWindowToolbarItem
        case .steamFilter:
            configureFilterItem()
            return filterToolbarItem
        case .steamAccount:
            configureAuthItems()
            return accountToolbarItem
        case .steamDownloadTasks:
            configureDownloadTasksItem()
            return downloadTasksToolbarItem
        case .steamZoom: return zoomToolbarItem
        case .steamSearch:
            syncSearchField()
            return searchToolbarItem
        default: return nil
        }
    }

    var personalBrowserIdentifiers: [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            NSToolbarItem.Identifier("ToolbarTitle"),
            .flexibleSpace,
            .steamAccount, .steamDownloadTasks,
            .space,
            .steamAuthorBack,
            .space,
            .steamPersonalList,
            .space,
            .steamSort, .steamFilter,
            .space,
            .steamZoom,
            .space,
            .steamSearch
        ]
    }

}
