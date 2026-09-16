//
//  SteamWorkshopToolbarController+Actions.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    @objc func handleSortAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        menuPopover.toggle(anchor: sender) { [weak self] in
            guard let self else { return [] }
            if service.source.isPersonal {
                return SteamWorkshopPersonalSort.allCases.map { sort in
                    ToolbarMenuPopoverPresenter.Row(
                        title: sort.displayName,
                        kind: .check,
                        isChecked: service.personalSort == sort,
                        handler: { [weak self] in
                            SteamWorkshopService.shared.personalSort = sort
                            self?.syncSortPopup()
                        }
                    )
                }
            }
            return SteamWorkshopSource.publicSources.map { source in
                ToolbarMenuPopoverPresenter.Row(
                    title: source.displayName,
                    kind: .check,
                    isChecked: service.source == source,
                    handler: { [weak self] in
                        SteamWorkshopService.shared.source = source
                        self?.syncSortPopup()
                        self?.syncTrendingWindowPopup()
                    }
                )
            }
        }
    }

    @objc func handlePersonalListAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else { return }
        menuPopover.toggle(anchor: sender) { [weak self] in
            SteamWorkshopSource.personalSources.map { source in
                ToolbarMenuPopoverPresenter.Row(
                    title: source.toolbarDisplayName,
                    kind: .check,
                    isChecked: service.source == source,
                    handler: { [weak self] in
                        SteamWorkshopService.shared.source = source
                        self?.syncPersonalListPopup()
                        self?.syncSortPopup()
                    }
                )
            }
        }
    }

    @objc func handleTrendingWindowAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        menuPopover.toggle(anchor: sender) { [weak self] in
            SteamWorkshopTrendingWindow.allCases.map { window in
                ToolbarMenuPopoverPresenter.Row(
                    title: window.displayName,
                    kind: .check,
                    isChecked: service.trendingWindow == window,
                    handler: { [weak self] in
                        SteamWorkshopService.shared.trendingWindow = window
                        self?.syncTrendingWindowPopup()
                    }
                )
            }
        }
    }

    @objc func handleDownloadTasks() {
        guard isSteamWorkshopMode else { return }
        if downloadTasksButton.window != nil {
            downloadTasksPopoverController.toggle(relativeTo: downloadTasksButton)
            return
        }
        // The toolbar's menu-form item has no attached button. Anchor its
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
        menuPopover.toggle(anchor: accountButton) { [weak self] in
            var rows: [ToolbarMenuPopoverPresenter.Row] = []
            // SK2.2：唯一账号入口（§3.1）——未登录只有「登录 Steam」；已登录仅
            // 账号信息/切换账号/退出登录。没有社区账号独立入口。
            if auth.isOnline {
                rows.append(ToolbarMenuPopoverPresenter.Row(
                    title: "Steam：\(auth.accountName ?? "已登录")",
                    kind: .info
                ))
                if let steamId = auth.steamId {
                    rows.append(ToolbarMenuPopoverPresenter.Row(title: "SteamID：\(steamId)", kind: .info))
                }
                rows.append(.separator())
                rows.append(ToolbarMenuPopoverPresenter.Row(
                    title: "切换账号",
                    kind: .action,
                    handler: { [weak self] in self?.handlePresentLogin() }
                ))
                rows.append(ToolbarMenuPopoverPresenter.Row(
                    title: "退出登录",
                    kind: .action,
                    handler: { [weak self] in self?.handleLogout() }
                ))
            } else {
                rows.append(ToolbarMenuPopoverPresenter.Row(
                    title: auth.expired ? "重新登录" : "登录 Steam",
                    kind: .action,
                    handler: { [weak self] in self?.handlePresentLogin() }
                ))
            }
            return rows
        }
    }

    @objc func handleFilterMenu() {
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        if filterPanelPopover.isShown {
            filterPanelPopover.performClose(nil)
            return
        }
        // 工具栏溢出成菜单项时按钮不在窗口内，退化为锚窗口右上角
        //（与下载任务面板的溢出锚点同构）。
        let anchorView: NSView
        let positioningRect: NSRect
        if filterButton.window != nil {
            anchorView = filterButton
            positioningRect = filterButton.bounds
        } else if let contentView = window?.contentView {
            anchorView = contentView
            positioningRect = NSRect(
                x: max(0, contentView.bounds.maxX - 32),
                y: contentView.bounds.maxY,
                width: 1,
                height: 1
            )
        } else {
            return
        }
        filterPanelPopover.contentViewController = filterPanelController
        // 面板高度按分面内容拟合；先确保 loadView 已跑，否则读到的是默认值。
        filterPanelController.loadViewIfNeeded()
        filterPanelPopover.contentSize = NSSize(
            width: SteamWorkshopFilterPanelController.panelWidth,
            height: filterPanelController.preferredPanelHeight
        )
        filterPanelPopover.show(
            relativeTo: positioningRect,
            of: anchorView,
            preferredEdge: .maxY
        )
    }

    @objc func handlePresentLogin() {
        // SK2.2：唯一登录入口 = 模块持有的登录面板（二维码/账号密码）。
        SteamWorkshopService.shared.showLoginPanel()
    }

    @objc func handleLogout() {
        SteamWorkshopService.shared.signOutEverywhere()
    }

    @objc func handleDeleteSelectedDownload() {
        SteamWorkshopService.shared.deleteSelectedDownload()
        configureDownloadsDeleteItem()
    }

    @objc func handleToggleDownloadsSelectMode() {
        SteamWorkshopService.shared.toggleDownloadsMultiSelectMode()
        configureDownloadsSelectItem()
        configureDownloadsDeleteItem()
    }

    @objc func handleShowSelectedDownloadInfo() {
        SteamWorkshopService.shared.presentSelectedDownloadInfo()
    }

    @objc func handleDownloadsFilterAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        menuPopover.toggle(anchor: sender) { [weak self] in
            SteamWorkshopDownloadsDisplayMode.allCases.map { mode in
                ToolbarMenuPopoverPresenter.Row(
                    title: mode.title,
                    kind: .check,
                    isChecked: service.downloadsDisplayMode == mode,
                    handler: {
                        service.downloadsDisplayMode = mode
                        self?.configureDownloadsFilterItem()
                    }
                )
            }
        }
    }

    @objc func handleDownloadsSortAction(_ sender: NSButton) {
        let service = SteamWorkshopService.shared
        menuPopover.toggle(anchor: sender) { [weak self] in
            var rows: [ToolbarMenuPopoverPresenter.Row] = SteamWorkshopDownloadsSortMode.allCases.map { mode in
                ToolbarMenuPopoverPresenter.Row(
                    title: mode.displayName,
                    kind: .check,
                    isChecked: service.downloadsSortMode == mode,
                    handler: {
                        service.downloadsSortMode = mode
                        self?.configureDownloadsSortItem()
                    }
                )
            }
            rows.append(.separator())
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "升序",
                kind: .check,
                isChecked: service.downloadsSortAscending,
                handler: {
                    service.downloadsSortAscending = true
                    self?.configureDownloadsSortItem()
                }
            ))
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "降序",
                kind: .check,
                isChecked: !service.downloadsSortAscending,
                handler: {
                    service.downloadsSortAscending = false
                    self?.configureDownloadsSortItem()
                }
            ))
            return rows
        }
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
            .steamSort,
            .steamTrendingWindow,
            .steamFilter,
            .steamAccount,
            .steamDownloadTasks,
            .steamZoom,
            .steamSearch,
            .steamDownloadsTitle,
            .steamDownloadsSelect,
            .steamDownloadsDelete,
            .steamDownloadsSort,
            .steamDownloadsSearch,
            .space,
            .flexibleSpace
        ]
    }
}
