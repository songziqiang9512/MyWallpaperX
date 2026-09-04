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
        let isAuthenticated = !service.requiresLogin && !service.isAnonymousBrowsing
        let isBusy = service.isPreparingRuntime || service.isAuthenticating

        let symbolName: String
        if service.isPreparingRuntime {
            symbolName = "hourglass.circle"
        } else if isAuthenticated {
            symbolName = "person.crop.circle.badge.checkmark"
        } else {
            symbolName = "person.crop.circle"
        }
        accountButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Steam 账号")
        accountButton.contentTintColor = isAuthenticated ? .controlAccentColor : .labelColor
        accountButton.toolTip = isAuthenticated ? "Steam 账号菜单" : "登录或匿名浏览"
        accountButton.isEnabled = !isBusy
        accountToolbarItem.toolTip = accountButton.toolTip
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

    func configureRefreshItem() {
        let service = SteamWorkshopService.shared
        let isRefreshing = service.isRefreshingBrowserFeed
        refreshToolbarItem.isEnabled = !isDownloadsMode && !isRefreshing
        refreshToolbarItem.image = NSImage(
            systemSymbolName: isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise",
            accessibilityDescription: "刷新"
        )
        refreshToolbarItem.toolTip = isRefreshing
            ? (service.isBrowsingAuthorWorkshop ? "正在刷新作者工坊列表…" : "正在刷新 Steam 创意工坊列表…")
            : "刷新 Steam 创意工坊列表"
    }

    func syncSortPopup() {
        let service = SteamWorkshopService.shared
        let source = service.source
        sortPopupButton.menu?.removeAllItems()
        if source.isPersonal {
            populatePersonalSortMenu(sortPopupButton.menu)
        } else {
            populateSourceMenu(sortPopupButton.menu)
        }
        let selectedRawValue = source.isPersonal ? service.personalSort.rawValue : source.rawValue
        sortPopupButton.itemArray.first { ($0.representedObject as? String) == selectedRawValue }.map {
            sortPopupButton.select($0)
        }
        let isEnabled = !service.isBrowsingAuthorWorkshop
        sortToolbarItem.isEnabled = isEnabled
        sortPopupButton.isEnabled = isEnabled
        sortToolbarItem.label = source.isPersonal ? "排序" : "浏览来源"
        sortToolbarItem.paletteLabel = sortToolbarItem.label
        sortToolbarItem.toolTip = isEnabled
            ? (source.isPersonal ? "当前个人库排序：\(service.personalSort.displayName)" : "当前浏览来源：\(source.displayName)")
            : "作者工坊模式暂不支持切换浏览来源"
    }

    func syncPersonalListPopup() {
        let service = SteamWorkshopService.shared
        let isEnabled = service.source.isPersonal && !service.isBrowsingAuthorWorkshop
        personalListPopupButton.itemArray.first {
            ($0.representedObject as? String) == service.source.rawValue
        }.map { personalListPopupButton.select($0) }
        personalListToolbarItem.isEnabled = isEnabled
        personalListPopupButton.isEnabled = isEnabled
        personalListToolbarItem.toolTip = isEnabled
            ? "当前个人列表：\(service.source.displayName)"
            : "进入 Steam 已订阅后选择个人列表"
    }

    func syncContentModePopup() {
        let allModes = SteamWorkshopBrowserContentMode.allCases
        contentModePopupButton.selectItem(at: allModes.firstIndex(of: SteamWorkshopService.shared.browserContentMode) ?? 0)
        let isEnabled = !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        contentModeToolbarItem.isEnabled = isEnabled
        contentModePopupButton.isEnabled = isEnabled
        contentModeToolbarItem.toolTip = isEnabled
            ? "当前浏览内容：\(SteamWorkshopService.shared.browserContentMode.displayName)"
            : "作者工坊模式暂不支持切换内容类型"
    }

    func syncTrendingWindowPopup() {
        let allWindows = SteamWorkshopTrendingWindow.allCases
        trendingWindowPopupButton.selectItem(at: allWindows.firstIndex(of: SteamWorkshopService.shared.trendingWindow) ?? 0)
        let isEnabled =
            SteamWorkshopService.shared.source.supportsTimeRange
            && !SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        trendingWindowToolbarItem.isEnabled = isEnabled
        trendingWindowPopupButton.isEnabled = isEnabled
    }

    func configureFilterItem() {
        let service = SteamWorkshopService.shared
        let selectedCount = service.activeFilterDisplayParts.count
        filterButton.title = selectedCount == 0 ? "筛选" : "筛选 \(selectedCount)"
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
        let isBrowsingAuthorWorkshop = SteamWorkshopService.shared.isBrowsingAuthorWorkshop
        searchToolbarItem.isEnabled = true
        searchField.isEnabled = true
        searchField.placeholderString = isBrowsingAuthorWorkshop
            ? "搜索当前作者作品"
            : SteamWorkshopService.shared.browserContentMode.searchPlaceholder
    }

    func syncBrowserContextControls() {
        guard isSteamWorkshopMode, !isDownloadsMode else { return }
        titleUpdateHandler?(SteamWorkshopService.shared.browserSectionTitle)
        configureAuthorBackItem()
        syncContentModePopup()
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
            contentModePopupButton,
            sortPopupButton,
            personalListPopupButton,
            trendingWindowPopupButton,
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

    func configureDownloadsInfoItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canShowSelectedDownloadInfo
        downloadsInfoItem.isEnabled = enabled
        downloadsInfoItem.toolTip = enabled
            ? "查看当前选中下载项的详细信息"
            : "请先单选一个下载项"
    }

    func configureDownloadsRevealItem() {
        let enabled = isDownloadsMode && SteamWorkshopService.shared.canRevealSelectedDownload
        downloadsRevealItem.isEnabled = enabled
        downloadsRevealItem.toolTip = enabled
            ? "在访达中显示当前选中的下载项"
            : "请先单选一个下载项"
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
