//
//  SteamWorkshopToolbarController+Actions.swift
//  MyWallpaperX
//

import AppKit

extension SteamWorkshopToolbarController {
    @objc func handleSortAction(_ sender: NSButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        menuPopover.toggle(anchor: sender) { [weak self] in self?.sortRows() ?? [] }
    }

    func sortRows() -> [ToolbarMenuPopoverPresenter.Row] {
        let service = SteamWorkshopService.shared
        let enabled = !service.isBrowsingAuthorWorkshop
        if service.source.isPersonal {
            return SteamWorkshopPersonalSort.allCases.map { sort in
                .init(title: sort.displayName, kind: .check, isChecked: service.personalSort == sort, isEnabled: enabled,
                    handler: { [weak self] in
                        guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode,
                              !service.isBrowsingAuthorWorkshop, service.source.isPersonal else { return }
                        service.personalSort = sort
                        self.syncSortPopup()
                    })
            }
        }
        return SteamWorkshopSource.publicSources.map { source in
            .init(title: source.displayName, kind: .check, isChecked: service.source == source, isEnabled: enabled,
                handler: { [weak self] in
                    guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode,
                          !service.isBrowsingAuthorWorkshop, !service.source.isPersonal else { return }
                    service.source = source
                    self.syncSortPopup()
                    self.syncTrendingWindowPopup()
                })
        }
    }

    @objc func handlePersonalListAction(_ sender: NSButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else { return }
        menuPopover.toggle(anchor: sender) { [weak self] in self?.personalListRows() ?? [] }
    }

    func personalListRows() -> [ToolbarMenuPopoverPresenter.Row] {
        let service = SteamWorkshopService.shared
        return SteamWorkshopSource.personalSources.map { source in
            .init(title: source == .myFavorites ? "Steam 收藏" : source.toolbarDisplayName, kind: .check, isChecked: service.source == source,
                isEnabled: service.source.isPersonal && !service.isBrowsingAuthorWorkshop,
                handler: { [weak self] in
                    guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode,
                          service.source.isPersonal, !service.isBrowsingAuthorWorkshop else { return }
                    service.source = source
                    self.syncPersonalListPopup()
                    self.syncSortPopup()
                })
        }
    }

    @objc func handleTrendingWindowAction(_ sender: NSButton) {
        guard !SteamWorkshopService.shared.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        menuPopover.toggle(anchor: sender) { [weak self] in self?.trendingWindowRows() ?? [] }
    }

    func trendingWindowRows() -> [ToolbarMenuPopoverPresenter.Row] {
        let service = SteamWorkshopService.shared
        return SteamWorkshopTrendingWindow.allCases.map { window in
            .init(title: window.displayName, kind: .check, isChecked: service.trendingWindow == window,
                isEnabled: service.source.supportsTimeRange && !service.isBrowsingAuthorWorkshop,
                handler: { [weak self] in
                    guard let self, self.isSteamWorkshopMode, !self.isDownloadsMode,
                          service.source.supportsTimeRange, !service.isBrowsingAuthorWorkshop else { return }
                    service.trendingWindow = window
                    self.syncTrendingWindowPopup()
                })
        }
    }

    @objc func handleDownloadTasks() {
        guard isSteamWorkshopMode, let window else { return }
        downloadTasksPopoverController.toggle(relativeTo: downloadTasksToolbarItem, in: window)
    }

    @objc func handleBackToDiscovery() {
        guard isSteamWorkshopMode, SteamWorkshopService.shared.canReturnFromBrowse else { return }
        SteamWorkshopService.shared.returnFromBrowseSubpage()
    }

    @objc func handleAccountMenu() {
        guard isSteamWorkshopMode, accountActionsEnabled else { return }
        menuPopover.toggle(anchor: accountButton) { [weak self] in self?.accountRows() ?? [] }
    }

    func accountRows() -> [ToolbarMenuPopoverPresenter.Row] {
        let auth = SteamWorkshopService.shared.steamAuth
        let accountID = auth.steamId
        var rows: [ToolbarMenuPopoverPresenter.Row] = []
        // Personal browsing is an authenticated subpage of this same browser.
        if auth.isOnline {
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "Steam：\(auth.accountName ?? "已登录")",
                kind: .info
            ))
            if let steamId = auth.steamId {
                rows.append(ToolbarMenuPopoverPresenter.Row(title: "SteamID：\(steamId)", kind: .info))
            }
            rows.append(.separator())
            rows.append(ToolbarMenuPopoverPresenter.Row(title: "我的订阅", kind: .action, handler: { [weak self] in
                guard let self, self.isSteamWorkshopMode, auth.isOnline, auth.steamId == accountID else { return }
                SteamWorkshopService.shared.showMySubscriptions()
            }))
            rows.append(.separator())
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "切换账号",
                kind: .action,
                handler: { [weak self] in
                    guard auth.isOnline, auth.steamId == accountID else { return }
                    self?.handlePresentLogin()
                }
            ))
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: "退出登录",
                kind: .action,
                handler: { [weak self] in
                    guard auth.isOnline, auth.steamId == accountID else { return }
                    self?.handleLogout()
                }
            ))
        } else {
            rows.append(ToolbarMenuPopoverPresenter.Row(
                title: auth.expired ? "重新登录" : "登录 Steam",
                kind: .action,
                handler: { [weak self] in
                    guard !auth.isOnline, auth.steamId == accountID else { return }
                    self?.handlePresentLogin()
                }
            ))
        }
        return rows
    }

    @objc func handleFilterMenu() {
        guard isSteamWorkshopMode, !isDownloadsMode else { return }
        let service = SteamWorkshopService.shared
        guard !service.isBrowsingAuthorWorkshop else {
            syncBrowserContextControls()
            return
        }
        if filterPanelPopover.isShown {
            filterPanelPopover.performClose(nil)
            return
        }
        guard let window, let toolbar = filterToolbarItem.toolbar,
              toolbar === window.toolbar, let contentView = window.contentView else { return }
        filterPanelPopover.contentViewController = filterPanelController
        // 面板高度按分面内容拟合；先确保 loadView 已跑，否则读到的是默认值。
        filterPanelController.loadViewIfNeeded()
        filterPanelPopover.contentSize = NSSize(
            width: SteamWorkshopFilterPanelController.panelWidth,
            height: filterPanelController.preferredPanelHeight
        )
        filterScrollDismissal.watch(relativeTo: contentView)
        filterPanelPopover.show(relativeTo: filterToolbarItem)
    }

    @objc func handlePresentLogin() {
        guard isSteamWorkshopMode, accountActionsEnabled else { return }
        // SK2.2：唯一登录入口 = 模块持有的登录面板（二维码/账号密码）。
        SteamWorkshopService.shared.showLoginPanel()
    }

    @objc func handleLogout() {
        guard isSteamWorkshopMode, accountActionsEnabled, SteamWorkshopService.shared.steamAuth.isOnline else { return }
        SteamWorkshopService.shared.signOutEverywhere()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        let key = ObjectIdentifier(field)
        searchDebounceWorkItems[key]?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak field] in
            guard let self, let field else { return }
            self.searchDebounceWorkItems[key] = nil
            if field === self.searchField {
                SteamWorkshopService.shared.browserQuery = text
            }
        }
        searchDebounceWorkItems[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

}
