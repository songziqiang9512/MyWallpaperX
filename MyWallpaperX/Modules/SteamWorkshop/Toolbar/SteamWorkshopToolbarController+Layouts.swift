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
        case .steamAccount: return accountToolbarItem
        case .steamDownloadTasks:
            configureDownloadTasksItem()
            return downloadTasksToolbarItem
        case .steamZoom: return zoomToolbarItem
        case .steamSearch:
            syncSearchField()
            return searchToolbarItem
        case .steamDownloadsTitle: return downloadsTitleItem
        case .steamDownloadsSelect:
            configureDownloadsSelectItem()
            return downloadsSelectItem
        case .steamDownloadsDelete:
            configureDownloadsDeleteItem()
            return downloadsDeleteItem
        case .steamDownloadsFilter:
            configureDownloadsFilterItem()
            return downloadsFilterItem
        case .steamDownloadsSort:
            configureDownloadsSortItem()
            return downloadsSortItem
        case .steamDownloadsSearch: return downloadsSearchItem
        default: return nil
        }
    }

    var personalBrowserIdentifiers: [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            NSToolbarItem.Identifier("ToolbarTitle"),
            .flexibleSpace,
            .steamAccount,
            .space,
            .steamDownloadTasks,
            .space,
            .steamPersonalList,
            .space,
            .steamSort,
            .space,
            .steamFilter,
            .space,
            .steamZoom,
            .space,
            .steamSearch
        ]
    }

    var downloadsIdentifiers: [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            .steamDownloadsTitle,
            .flexibleSpace,
            .steamAccount,
            .space,
            .steamDownloadTasks,
            .space,
            .steamDownloadsSelect,
            .space,
            .steamDownloadsDelete,
            .steamDownloadsFilter,
            .steamDownloadsSort,
            .space,
            .steamZoom,
            .space,
            .steamDownloadsSearch
        ]
    }
}
