//
//  SteamWorkshopToolbarController+Configuration.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    func focusSearch() {
        guard isSteamWorkshopMode else { return }
        if isDownloadsMode {
            window?.makeFirstResponder(downloadsSearchField)
        } else {
            window?.makeFirstResponder(searchField)
        }
    }

    func performZoom(delta: Int) {
        guard isSteamWorkshopMode else { return }
        let width = gridWidth()
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: width
        )
        let canZoom = delta > 0 ? availability.canZoomIn : availability.canZoomOut
        guard canZoom else { return }
        let segment = delta > 0 ? 1 : 0
        zoomControl.setSelected(true, forSegment: segment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.zoomControl.setSelected(false, forSegment: segment)
        }
        SteamWorkshopService.shared.zoomOffset += delta
        configureZoomItem()
    }

    private func gridWidth() -> CGFloat {
        (window?.contentView?.bounds.width ?? 800) - 220
    }

    func configureZoomItem() {
        let availability = GridLayoutHelper.zoomAvailability(
            currentOffset: SteamWorkshopService.shared.zoomOffset,
            for: gridWidth()
        )
        zoomControl.setEnabled(availability.canZoomOut, forSegment: 0)
        zoomControl.setEnabled(availability.canZoomIn, forSegment: 1)
    }

    func configureAuthItems() {
        let service = SteamWorkshopService.shared
        let auth = service.steamAuth
        let requiresLoginAttention = service.statusMessage.hasPrefix("需要登录 Steam")

        // SK2.2：账号按钮状态由新登录路线驱动（§3.1）。
        let symbolName: String
        let tint: NSColor
        let tooltip: String
        let isBusy: Bool
        switch auth.displayState {
        case .online:
            symbolName = "person.crop.circle.badge.checkmark"
            tint = .controlAccentColor
            tooltip = "Steam 账号菜单"
            isBusy = false
        case .connecting, .awaitingInput:
            symbolName = "hourglass"
            tint = .secondaryLabelColor
            tooltip = "正在登录 Steam…"
            isBusy = true
        case .expired:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = "重新登录"
            isBusy = false
        case .failed:
            symbolName = "person.crop.circle.badge.exclamationmark"
            tint = .systemOrange
            tooltip = "登录出现问题，点击重新登录"
            isBusy = false
        case .signedOut:
            symbolName = "person.crop.circle"
            tint = requiresLoginAttention ? .systemOrange : .labelColor
            tooltip = requiresLoginAttention ? service.statusMessage : "登录 Steam"
            isBusy = false
        }
        accountButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Steam 账号")
        accountButton.contentTintColor = tint
        accountButton.toolTip = tooltip
        accountButton.setAccessibilityLabel("Steam 账号，\(tooltip)")
        accountButton.isEnabled = !isBusy
        accountToolbarItem.toolTip = accountButton.toolTip
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
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        authorBackToolbarItem.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.isEnabled = isBrowsingAuthorWorkshop
        authorBackButton.alphaValue = isBrowsingAuthorWorkshop ? 1.0 : 0.45
        authorBackButton.toolTip = isBrowsingAuthorWorkshop
            ? "返回 Steam 创意工坊总榜"
            : "当前不在作者工坊模式"
        authorBackToolbarItem.toolTip = authorBackButton.toolTip
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
    }

    func syncPersonalListPopup() {
        let service = SteamWorkshopService.shared
        let isEnabled = service.source.isPersonal && !service.isBrowsingAuthorWorkshop
        personalListButton.title = service.source.toolbarDisplayName
        personalListToolbarItem.isEnabled = isEnabled
        personalListButton.isEnabled = isEnabled
        personalListToolbarItem.toolTip = isEnabled
            ? "当前个人列表：\(service.source.displayName)"
            : "进入「我的订阅」后选择个人列表"
        personalListButton.toolTip = personalListToolbarItem.toolTip
        personalListButton.sizeToFit()
    }

    func syncTrendingWindowPopup() {
        trendingWindowButton.title = SteamWorkshopService.shared.trendingWindow.displayName
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowButton.isEnabled = isEnabled
        trendingWindowButton.sizeToFit()
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
    }

    func syncSearchField() {
        searchField.stringValue = SteamWorkshopService.shared.browserQuery
        searchToolbarItem.isEnabled = true
        searchField.isEnabled = true
        searchField.placeholderString = "搜索"
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

    func syncDownloadsSearchField() {
        downloadsSearchField.stringValue = SteamWorkshopService.shared.downloadsQuery
    }

    func configureDownloadsTitleItem() {
        downloadsTitleLabel.stringValue = Title.downloads
        downloadsTitleItem.toolTip = Title.downloads
    }

    func configureDownloadsSelectItem() {
        let isMultiSelectMode = SteamWorkshopService.shared.isDownloadsMultiSelectMode
        let symbolName = isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle"
        downloadsSelectItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "选择")
        downloadsSelectItem.toolTip = isMultiSelectMode ? "退出选择模式" : "进入选择模式"
    }

    func configureDownloadsDeleteItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canDeleteSelectedDownload
        downloadsDeleteItem.isEnabled = enabled
        downloadsDeleteItem.toolTip = enabled
            ? "删除当前选中的下载项"
            : "请先选中一个已下载或失败的项目"
    }

    func configureDownloadsFilterItem() {
        let service = SteamWorkshopService.shared
        let mode = service.downloadsDisplayMode
        let title: String
        switch mode {
        case .all:
            title = "全部 \(service.downloadsCount)"
        case .video:
            title = "视频 \(service.visibleVideoDownloadsCount)"
        case .web:
            title = "HTML \(service.visibleWebDownloadsCount)"
        case .scene:
            title = "Scene \(service.visibleSceneDownloadsCount)"
        case .missingDependency:
            title = "缺依赖 \(service.visibleMissingDependencyDownloadsCount)"
        }
        downloadsFilterButton.title = title
        downloadsFilterButton.toolTip = "当前筛选：\(mode.title)"
        downloadsFilterItem.toolTip = downloadsFilterButton.toolTip
        downloadsFilterItem.isEnabled = isDownloadsMode
        downloadsFilterButton.isEnabled = isDownloadsMode
    }

    func configureDownloadsSortItem() {
        let service = SteamWorkshopService.shared
        let direction = service.downloadsSortAscending ? "升序" : "降序"
        downloadsSortMenuButton.toolTip = "排序方式：\(service.downloadsSortMode.displayName) · \(direction)"
        downloadsSortItem.toolTip = downloadsSortMenuButton.toolTip
    }
}
