import AppKit

extension SteamWorkshopToolbarController {
    func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case .steamAuthorBack:
            configureAuthorBackItem()
            return authorBackToolbarItem
        case .steamContentMode:
            syncContentModePopup()
            return contentModeToolbarItem
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
        case .steamRefresh: return refreshToolbarItem
        case .steamZoom: return zoomToolbarItem
        case .steamSearch:
            syncSearchField()
            return searchToolbarItem
        case .steamDownloadsTitle: return downloadsTitleItem
        case .steamDownloadsReveal: return downloadsRevealItem
        case .steamDownloadsSelect:
            configureDownloadsSelectItem()
            return downloadsSelectItem
        case .steamDownloadsDelete:
            configureDownloadsDeleteItem()
            return downloadsDeleteItem
        case .steamDownloadsInfo:
            configureDownloadsInfoItem()
            return downloadsInfoItem
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
            .steamRefresh,
            .space,
            .steamContentMode,
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
            .steamDownloadsSelect,
            .space,
            .steamDownloadsDelete,
            .steamDownloadsInfo,
            .steamDownloadsReveal,
            .steamDownloadsFilter,
            .steamDownloadsSort,
            .space,
            .steamZoom,
            .space,
            .steamDownloadsSearch
        ]
    }
}
