//
//  SteamWorkshopToolbarController+Configuration.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    var accountActionsEnabled: Bool {
        switch SteamWorkshopService.shared.steamAuth.displayState {
        case .connecting, .awaitingInput: return false
        default: return true
        }
    }

    func focusSearch() {
        guard isSteamWorkshopMode else { return }
        guard !isDownloadsMode else { return }
        searchToolbarItem.beginSearchInteraction()
    }

    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) {
        zoomControl.update(preferredColumns: preferredColumns, clipWidth: clipWidth, canDispatch: makeZoomAction != nil)
        zoomToolbarItem.isEnabled = zoomControl.isEnabled
        zoomToolbarItem.menuFormRepresentation = zoomControl.menuRepresentation()
    }

    func configureAuthItems() {
        let service = SteamWorkshopService.shared
        let auth = service.steamAuth
        let requiresLoginAttention = service.statusMessage.hasPrefix("需要登录")

        // SK2.2：账号按钮状态由新登录路线驱动（§3.1）。
        let symbolName: String
        let tint: NSColor
        let tooltip: String
        switch auth.displayState {
        case .online:
            symbolName = "person.crop.circle.badge.checkmark"
            tint = .controlAccentColor
            tooltip = "Steam 账号菜单"
        case .connecting, .awaitingInput:
            symbolName = "hourglass"
            tint = .secondaryLabelColor
            tooltip = "正在登录 Steam…"
        case .expired:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = "重新登录"
        case .failed:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = "登录出现问题，点击重新登录"
        case .signedOut:
            symbolName = "person.crop.circle"
            tint = requiresLoginAttention ? .systemOrange : .labelColor
            tooltip = requiresLoginAttention ? service.statusMessage : "登录 Steam"
        }
        accountButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Steam 账号")
        accountButton.contentTintColor = tint
        accountButton.toolTip = tooltip
        accountButton.setAccessibilityLabel("Steam 账号，\(tooltip)")
        let canExecute = accountActionsEnabled
        accountButton.isEnabled = canExecute
        accountToolbarItem.isEnabled = canExecute
        accountToolbarItem.toolTip = accountButton.toolTip
        accountToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "Steam 账号", rows: accountRows())
        accountToolbarItem.menuFormRepresentation?.isEnabled = canExecute
        accountToolbarItem.visibilityPriority = .low
    }

    func configureDownloadTasksItem() {
        let service = SteamWorkshopService.shared
        let count = SteamWorkshopDownloadTaskProjection.unfinishedCount(
            in: service.downloadJobStore.jobs,
            accountSteamID: service.steamAuth.steamId
        )
        let title = count == 0 ? "下载任务" : "下载任务（\(count) 项）"
        downloadTasksToolbarItem.toolTip = title
        downloadTasksToolbarItem.menuFormRepresentation?.title = title
    }

    func configureAuthorBackItem() {
        let service = SteamWorkshopService.shared
        let canReturn = service.canReturnFromBrowse
        authorBackToolbarItem.isEnabled = canReturn
        authorBackButton.isEnabled = canReturn
        authorBackButton.alphaValue = canReturn ? 1.0 : 0.45
        authorBackButton.toolTip = canReturn
            ? (service.isBrowsingAuthorWorkshop ? service.authorWorkshopReturnDestination?.title ?? "返回创意工坊" : "返回创意工坊")
            : "当前不在二级浏览页"
        authorBackToolbarItem.toolTip = authorBackButton.toolTip
        let back = ActionMenuItem(title: authorBackButton.toolTip ?? "返回创意工坊", symbol: "chevron.backward") { [weak self] in self?.handleBackToDiscovery() }
        back.isEnabled = canReturn
        authorBackToolbarItem.menuFormRepresentation = back
    }

    func syncSortPopup() {
        let service = SteamWorkshopService.shared
        let source = service.source
        sortButton.title = source.isPersonal ? service.personalSort.displayName : source.displayName
        let isEnabled = !service.isBrowsingAuthorWorkshop
        sortToolbarItem.isEnabled = isEnabled
        sortButton.isEnabled = isEnabled
        sortToolbarItem.label = source.isPersonal ? "排序" : "浏览来源"
        sortToolbarItem.paletteLabel = sortToolbarItem.label
        sortToolbarItem.toolTip = isEnabled
            ? (source.isPersonal ? "当前个人库排序：\(service.personalSort.displayName)" : "当前浏览来源：\(source.displayName)")
            : "作者工坊模式暂不支持切换浏览来源"
        sortButton.toolTip = sortToolbarItem.toolTip
        sortButton.sizeToFit()
        sortToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: sortToolbarItem.label, rows: sortRows())
    }

    func syncPersonalListPopup() {
        let service = SteamWorkshopService.shared
        let isEnabled = service.source.isPersonal && !service.isBrowsingAuthorWorkshop
        personalListButton.title = service.source == .myFavorites ? "Steam 收藏" : service.source.toolbarDisplayName
        personalListToolbarItem.isEnabled = isEnabled
        personalListButton.isEnabled = isEnabled
        personalListToolbarItem.toolTip = isEnabled
            ? "当前个人列表：\(service.source.displayName)"
            : "进入「我的订阅」后选择个人列表"
        personalListButton.toolTip = personalListToolbarItem.toolTip
        personalListButton.sizeToFit()
        personalListToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "个人列表", rows: personalListRows())
    }

    func syncTrendingWindowPopup() {
        trendingWindowButton.title = SteamWorkshopService.shared.trendingWindow.displayName
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowButton.isEnabled = isEnabled
        trendingWindowButton.sizeToFit()
        trendingWindowToolbarItem.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: "时间段", rows: trendingWindowRows())
    }

    func configureFilterItem() {
        let service = SteamWorkshopService.shared
        filterButton.title = "筛选"
        let isEnabled = !service.isBrowsingAuthorWorkshop
        filterButton.toolTip = service.isBrowsingAuthorWorkshop
            ? "作者工坊模式暂不支持排序筛选"
            : "当前内容：\(service.browserContentMode.displayName) · 当前筛选：\(service.activeFilterSummary)"
        filterToolbarItem.isEnabled = isEnabled
        filterButton.isEnabled = isEnabled
        filterToolbarItem.toolTip = filterButton.toolTip
        let filter = ActionMenuItem(title: "筛选", symbol: "line.3.horizontal.decrease.circle") { [weak self] in self?.handleFilterMenu() }
        filter.isEnabled = isEnabled
        filterToolbarItem.menuFormRepresentation = filter
    }

    func syncSearchField() {
        searchField.stringValue = SteamWorkshopService.shared.browserQuery
        searchToolbarItem.isEnabled = true
        searchField.isEnabled = true
        searchField.placeholderString = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
            ? "在已加载作品中查找" : "在\(SteamWorkshopService.shared.browserSectionTitle)中查找"
        searchField.setAccessibilityLabel(searchField.placeholderString)
    }

    func syncBrowserContextControls() {
        guard isSteamWorkshopMode, !isDownloadsMode else { return }
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        configureAuthorBackItem()
        syncSortPopup()
        syncPersonalListPopup()
        syncTrendingWindowPopup()
        configureFilterItem()
        syncSearchField()
        refreshToolbarContextViews()
    }

    func refreshToolbarContextViews() {
        let views: [NSView] = [
            authorBackButton,
            sortButton,
            personalListButton,
            trendingWindowButton,
            filterButton,
            searchField
        ]
        views.forEach {
            $0.needsLayout = true
            $0.needsDisplay = true
        }
        toolbar?.items.forEach { item in
            item.view?.needsLayout = true
            item.view?.needsDisplay = true
        }
    }

}
