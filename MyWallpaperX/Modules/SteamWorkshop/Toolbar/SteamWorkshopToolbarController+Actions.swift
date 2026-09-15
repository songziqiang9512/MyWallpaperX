//
//  SteamWorkshopToolbarController+Actions.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    @objc func handleContentModeAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let modes = SteamWorkshopBrowserContentMode.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < modes.count else { return }
        SteamWorkshopService.shared.browserContentMode = modes[sender.indexOfSelectedItem]
        syncContentModePopup()
    }

    @objc func handleSortAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        let service = SteamWorkshopService.shared
        if service.source.isPersonal {
            guard let sort = SteamWorkshopPersonalSort(rawValue: rawValue) else { return }
            service.personalSort = sort
        } else {
            guard let source = SteamWorkshopSource(rawValue: rawValue), source.isPersonal == false else { return }
            service.source = source
        }
        syncSortPopup()
        syncTrendingWindowPopup()
    }

    @objc func handlePersonalListAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop,
              let rawValue = sender.selectedItem?.representedObject as? String,
              let source = SteamWorkshopSource(rawValue: rawValue),
              source.isPersonal else { return }
        SteamWorkshopService.shared.source = source
        syncPersonalListPopup()
        syncSortPopup()
    }

    @objc func handleTrendingWindowAction(_ sender: NSPopUpButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let windows = SteamWorkshopTrendingWindow.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < windows.count else { return }
        SteamWorkshopService.shared.trendingWindow = windows[sender.indexOfSelectedItem]
    }

    @objc func handleRefresh() {
        SteamWorkshopService.shared.refresh()
    }

    @objc func handleDownloadTasks() {
        guard isSteamWorkshopMode else { return }
        if downloadTasksButtonView.button.window != nil {
            downloadTasksPopoverController.toggle(relativeTo: downloadTasksButtonView.button)
            return
        }
        // The toolbar's menu-form item has no attached custom view. Anchor its
        // popover to the owning window's top trailing edge instead.
        DispatchQueue.main.async { [weak self] in
            guard let self, let contentView = self.window?.contentView else { return }
            let anchor = NSRect(
                x: max(0, contentView.bounds.maxX - 32),
                y: contentView.bounds.maxY,
                width: 1,
                height: 1
            )
            self.downloadTasksPopoverController.toggle(relativeTo: contentView, positioningRect: anchor)
        }
    }

    @objc func handleBackToDiscovery() {
        SteamWorkshopService.shared.returnToDiscoveryBrowse()
    }

    @objc func handleAccountMenu() {
        let service = SteamWorkshopService.shared
        let auth = service.steamAuth
        let menu = NSMenu()
        menu.autoenablesItems = false

        // SK2.2：唯一账号入口（§3.1）——未登录只有「登录 Steam」；已登录仅
        // 账号信息/切换账号/退出登录。没有社区账号独立入口。
        if auth.isOnline {
            let statusItem = NSMenuItem(
                title: "Steam：\(auth.accountName ?? "已登录")",
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            if let steamId = auth.steamId {
                let idItem = NSMenuItem(title: "SteamID：\(steamId)", action: nil, keyEquivalent: "")
                idItem.isEnabled = false
                menu.addItem(idItem)
            }
            menu.addItem(.separator())
            let switchItem = NSMenuItem(title: "切换账号", action: #selector(handlePresentLogin), keyEquivalent: "")
            switchItem.target = self
            menu.addItem(switchItem)
            let logoutItem = NSMenuItem(title: "退出登录", action: #selector(handleLogout), keyEquivalent: "")
            logoutItem.target = self
            menu.addItem(logoutItem)
        } else {
            let loginItem = NSMenuItem(
                title: auth.expired ? "重新登录" : "登录 Steam",
                action: #selector(handlePresentLogin),
                keyEquivalent: ""
            )
            loginItem.target = self
            menu.addItem(loginItem)
        }

        let buttonBounds = accountButton.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height + 4), in: accountButton)
    }

    @objc func handleFilterMenu() {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let themeMenuItem = NSMenuItem(title: "类型", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        SteamWorkshopThemeFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleThemeFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.themeFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            themeMenu.addItem(item)
        }
        themeMenuItem.submenu = themeMenu
        menu.addItem(themeMenuItem)

        let ageMenuItem = NSMenuItem(title: "分级", action: nil, keyEquivalent: "")
        let ageMenu = NSMenu()
        SteamWorkshopAgeRatingFilter.selectableRatings.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleAgeFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.ageRatingFilter.contains(filter) ? .on : .off
            item.representedObject = Int(filter.rawValue)
            ageMenu.addItem(item)
        }
        ageMenuItem.title = "分级（暂不支持）"
        ageMenuItem.isEnabled = false
        ageMenuItem.submenu = ageMenu
        menu.addItem(ageMenuItem)

        let resolutionMenuItem = NSMenuItem(title: "分辨率", action: nil, keyEquivalent: "")
        let resolutionMenu = NSMenu()
        SteamWorkshopResolutionFilter.allCases.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleResolutionFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.resolutionFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            resolutionMenu.addItem(item)
        }
        resolutionMenuItem.submenu = resolutionMenu
        menu.addItem(resolutionMenuItem)

        let categoryMenuItem = NSMenuItem(title: "分类", action: nil, keyEquivalent: "")
        let categoryMenu = NSMenu()
        SteamWorkshopCategoryFilter.allCases.filter { $0 != .web }.forEach { filter in
            let item = NSMenuItem(title: filter.displayName, action: #selector(handleCategoryFilterItem(_:)), keyEquivalent: "")
            item.target = self
            item.state = service.categoryFilter == filter ? .on : .off
            item.representedObject = filter.rawValue
            categoryMenu.addItem(item)
        }
        categoryMenuItem.submenu = categoryMenu
        menu.addItem(categoryMenuItem)

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "清空筛选", action: #selector(handleClearFilters), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = service.activeFilterSummary != "未筛选"
        menu.addItem(clearItem)

        let buttonBounds = filterButton.bounds
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttonBounds.height + 4), in: filterButton)
    }

    @objc func handlePresentLogin() {
        // SK2.2：唯一登录入口 = 模块持有的登录面板（二维码/账号密码）。
        SteamWorkshopService.shared.showLoginPanel()
    }

    @objc func handleLogout() {
        SteamWorkshopService.shared.signOutEverywhere()
    }

    @objc func handleRevealDownloads() {
        SteamWorkshopService.shared.revealSelectedDownload()
        configureDownloadsRevealItem()
    }

    @objc func handleDeleteSelectedDownload() {
        SteamWorkshopService.shared.deleteSelectedDownload()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc func handleToggleDownloadsSelectMode() {
        SteamWorkshopService.shared.toggleDownloadsMultiSelectMode()
        configureDownloadsSelectItem()
        configureDownloadsInfoItem()
        configureDownloadsRevealItem()
        configureDownloadsDeleteItem()
    }

    @objc func handleShowSelectedDownloadInfo() {
        SteamWorkshopService.shared.presentSelectedDownloadInfo()
        configureDownloadsInfoItem()
    }

    @objc func handleDownloadsFilterAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        SteamWorkshopDownloadsDisplayMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.title, action: #selector(handleDownloadsFilterModeItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = service.downloadsDisplayMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func handleDownloadsFilterModeItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SteamWorkshopDownloadsDisplayMode(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.downloadsDisplayMode = mode
        configureDownloadsFilterItem()
    }

    @objc func handleDownloadsSortAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        SteamWorkshopDownloadsSortMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.displayName, action: #selector(handleDownloadsSortModeItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = service.downloadsSortMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let ascendingItem = NSMenuItem(title: "升序", action: #selector(handleDownloadsSortDirectionItem(_:)), keyEquivalent: "")
        ascendingItem.target = self
        ascendingItem.representedObject = true
        ascendingItem.state = service.downloadsSortAscending ? .on : .off
        menu.addItem(ascendingItem)

        let descendingItem = NSMenuItem(title: "降序", action: #selector(handleDownloadsSortDirectionItem(_:)), keyEquivalent: "")
        descendingItem.target = self
        descendingItem.representedObject = false
        descendingItem.state = service.downloadsSortAscending ? .off : .on
        menu.addItem(descendingItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func handleDownloadsSortModeItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = SteamWorkshopDownloadsSortMode(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.downloadsSortMode = mode
        configureDownloadsSortItem()
    }

    @objc func handleDownloadsSortDirectionItem(_ sender: NSMenuItem) {
        guard let ascending = sender.representedObject as? Bool else { return }
        SteamWorkshopService.shared.downloadsSortAscending = ascending
        configureDownloadsSortItem()
    }

    @objc func handleThemeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopThemeFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.themeFilter = filter
        configureFilterItem()
    }

    @objc func handleAgeFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let value = UInt8(exactly: rawValue) else { return }
        SteamWorkshopService.shared.ageRatingFilter.formSymmetricDifference(.init(rawValue: value))
        configureFilterItem()
    }

    @objc func handleResolutionFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopResolutionFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.resolutionFilter = filter
        configureFilterItem()
    }

    @objc func handleClearFilters() {
        SteamWorkshopService.shared.clearFilters()
        configureFilterItem()
    }

    @objc func handleCategoryFilterItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let filter = SteamWorkshopCategoryFilter(rawValue: rawValue) else { return }
        SteamWorkshopService.shared.categoryFilter = filter
        configureFilterItem()
    }

    @objc func handleZoomAction(_ sender: NSSegmentedControl) {
        performZoom(delta: sender.selectedSegment == 0 ? -1 : 1)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if field === downloadsSearchField {
            SteamWorkshopService.shared.downloadsQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        } else {
            SteamWorkshopService.shared.browserQuery = field.stringValue.trimmingCharacters(in: .whitespaces)
        }
    }

    var allowedItemIdentifiers: [NSToolbarItem.Identifier] {
        [
            .steamAuthorBack,
            .steamContentMode,
            .steamSort,
            .steamTrendingWindow,
            .steamFilter,
            .steamAccount,
            .steamDownloadTasks,
            .steamRefresh,
            .steamZoom,
            .steamSearch,
            .steamDownloadsTitle,
            .steamDownloadsSelect,
            .steamDownloadsDelete,
            .steamDownloadsInfo,
            .steamDownloadsReveal,
            .steamDownloadsSort,
            .steamDownloadsSearch,
            .space,
            .flexibleSpace
        ]
    }
}
