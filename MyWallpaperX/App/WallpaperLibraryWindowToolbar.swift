import AppKit
import Combine

/// The window owns exactly one NSToolbar. Remote providers supply their
/// existing controls; local controls consume the same page value as the grid.
@MainActor final class WallpaperLibraryWindowToolbar: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private enum Action: String, CaseIterable {
        case title = "ToolbarTitle", importFiles, select, previous, next, remove, favorite, addToPlaylist
        case back, play, random, create, more, filter, sort, zoom, zoomOut, zoomIn, search
        var id: NSToolbarItem.Identifier { .init(rawValue) }
    }
    private let workspace: WallpaperLibraryWorkspace
    private let commands: WallpaperLibraryCommands
    private let gridWidth: () -> CGFloat
    private let makeDirectoryReturnAction: () -> (() -> Void)?
    private weak var window: NSWindow?
    private var subscription: AnyCancellable?
    private var availabilitySubscription: AnyCancellable?
    private var browserObserver: NSObjectProtocol?
    private var layoutObservers: [NSObjectProtocol] = []
    private let titleLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private var lastIdentifiers: [NSToolbarItem.Identifier] = []
    private var items: [Action: NSToolbarItem] = [:]
    private var menuActions: [ObjectIdentifier: Action] = [:]
    let toolbar: NSToolbar
    private let steam: SteamWorkshopToolbarController
    private let online: OnlineLibraryToolbarController
    private lazy var zoomControl: WallpaperLibraryZoomControl = {
        let control = WallpaperLibraryZoomControl()
        control.makeAction = { [weak self] in self?.makeZoomAction(delta: $0) }
        return control
    }()

    init(window: NSWindow, workspace: WallpaperLibraryWorkspace, commands: WallpaperLibraryCommands,
         gridWidth: @escaping () -> CGFloat, makeDirectoryReturnAction: @escaping () -> (() -> Void)? = { nil }) {
        self.window = window; self.workspace = workspace; self.commands = commands
        self.gridWidth = gridWidth
        self.makeDirectoryReturnAction = makeDirectoryReturnAction
        let toolbar = NSToolbar(identifier: .init("MainWindowToolbar"))
        self.toolbar = toolbar
        steam = SteamWorkshopToolbarController(toolbar: toolbar, window: window)
        online = OnlineLibraryToolbarController(window: window)
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let minimumTitleWidth = titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        minimumTitleWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([minimumTitleWidth, titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280)])
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        steam.titleUpdateHandler = { [weak self] _ in
            guard let self, [.workshop, .workshopSubscriptions].contains(self.workspace.presentation.page) else { return }
            self.refresh()
        }
        online.titleUpdateHandler = { [weak self] _ in self?.refresh() }
        steam.makeZoomAction = { [weak self] in self?.makeZoomAction(delta: $0) }
        online.makeZoomAction = { [weak self] in self?.makeZoomAction(delta: $0) }
        commands.onFocusSearch = { [weak self] in self?.focusSearch() }
        subscription = workspace.presentation.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        availabilitySubscription = commands.availabilityChanges.sink { [weak self] _ in self?.refresh() }
        browserObserver = NotificationCenter.default.addObserver(forName: .steamWorkshopBrowseContextDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        layoutObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSourceLayout() }
        })
        layoutObservers.append(NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main) { [weak self, weak window] note in
            MainActor.assumeIsolated {
                guard let window, (note.object as? NSSplitView)?.window === window else { return }
                self?.refreshSourceLayout()
            }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            layoutObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    deinit {
        if let browserObserver { NotificationCenter.default.removeObserver(browserObserver) }
        layoutObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private var title: String {
        let page = workspace.presentation.page
        if case .playlist(let id) = page { return page.title(playlistName: workspace.relationships.playlists.first { $0.id == id }?.name) }
        if page == .workshop || page == .workshopSubscriptions { return SteamWorkshopService.shared.browserSectionTitle }
        return page.title()
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        let page = workspace.presentation.page
        let prefix: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator, Action.title.id, .flexibleSpace]
        if page == .workshop || page == .workshopSubscriptions {
            return prefix + steam.browserIdentifiers.filter { $0 != .sidebarTrackingSeparator && $0 != Action.title.id && $0 != .flexibleSpace }
        }
        if page == .pixabay {
            return prefix + online.onlineIdentifiers.filter { $0 != .sidebarTrackingSeparator && $0 != Action.title.id && $0 != .flexibleSpace }
        }
        let groups: [[Action]]
        switch page {
        case .videos, .images: groups = [[.importFiles, .select, .addToPlaylist], [.previous, .next], [.remove, .favorite, .more], [.sort], [.zoom], [.search]]
        case .downloads:
            return prefix + [.steamAccount, .steamDownloadTasks, .space]
                + grouped([[.select, .remove, .more], [.filter, .sort], [.zoom], [.search]])
        case .recent: groups = [[.play, .random], [.select, .addToPlaylist], [.remove, .favorite, .more], [.filter], [.zoom], [.search]]
        case .favorites: groups = [[.play, .random], [.select, .addToPlaylist], [.remove, .more], [.filter, .sort], [.zoom], [.search]]
        case .playlist: groups = [[.select, .addToPlaylist], [.remove, .favorite, .more], [.filter, .sort], [.zoom], [.search]]
        case .playlists: groups = [[.create], [.sort], [.zoom], [.search]]
        default: groups = []
        }
        let returnGroup: [[Action]] = makeDirectoryReturnAction() == nil ? [] : [[.back]]
        return prefix + grouped(returnGroup + groups)
    }

    private func grouped(_ groups: [[Action]]) -> [NSToolbarItem.Identifier] {
        groups.filter { !$0.isEmpty }.enumerated().flatMap { index, group in
            (index == 0 ? [] : [.space]) + group.map(\.id)
        }
    }

    func refresh() {
        let state = workspace.presentation.selectionState
        let requested = identifiers
        if requested != lastIdentifiers {
            for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
            for (index, id) in requested.enumerated() { toolbar.insertItem(withItemIdentifier: id, at: index) }
            lastIdentifiers = requested
        }
        updateTitle(state.isSelecting ? "\(title) · 已选 \(state.references.count) 项" : title)
        let model = workspace.presentation
        if searchField.stringValue != model.queryState.search { searchField.stringValue = model.queryState.search }
        searchField.placeholderString = "在\(title)中查找"
        searchField.setAccessibilityLabel(searchField.placeholderString)
        items[.select]?.label = model.selectionState.isSelecting ? "完成选择" : "选择"
        items[.select]?.image = NSImage(systemSymbolName: model.selectionState.isSelecting ? "checkmark.circle.fill" : "checkmark.circle", accessibilityDescription: nil)
        items[.remove]?.label = commands.removalTitle
        items[.remove]?.toolTip = commands.removalTitle
        items[.remove]?.image = NSImage(systemSymbolName: symbol(.remove), accessibilityDescription: commands.removalTitle)
        let selection = commands.selection
        let favorite = commands.favoriteActionState(for: selection)
        let hasPlayable = model.queryResult.items.contains { $0.capabilities.contains(.play) }
        items[.favorite]?.label = favorite.title
        items[.favorite]?.paletteLabel = favorite.title
        items[.favorite]?.toolTip = favorite.title
        items[.favorite]?.image = NSImage(systemSymbolName: favorite.isRemoving ? "heart.fill" : "heart", accessibilityDescription: favorite.title)
        for (action, item) in items {
            item.isEnabled = enabled(action, selection: selection, favoriteEnabled: favorite.canExecute, hasPlayable: hasPlayable)
            (item.view as? NSControl)?.isEnabled = item.isEnabled
            if action != .title, action == .back || item.action == #selector(invoke(_:)) {
                item.menuFormRepresentation = actionMenuRepresentation(action, title: action == .favorite ? favorite.title : label(action),
                    symbol: action == .favorite ? (favorite.isRemoving ? "heart.fill" : "heart") : symbol(action),
                    enabled: item.isEnabled, selection: selection)
            }
        }
        refreshQueryDescriptions()
        refreshSourceLayout()
    }

    private func updateTitle(_ value: String) {
        let model = workspace.presentation
        let summary: String?
        if model.page.isRemoteBrowse { summary = nil }
        else if model.page == .playlists {
            summary = "显示 \(model.directoryEntries.count) / 共 \(workspace.relationships.playlists.count) 个播放列表"
        } else {
            summary = "显示 \(model.queryResult.items.count) / 共 \(model.queryResult.unfilteredCount) 张壁纸"
        }
        titleLabel.stringValue = value
        titleLabel.setAccessibilityLabel(value)
        titleLabel.setAccessibilityHelp(summary)
        items[.title]?.label = value
        items[.title]?.paletteLabel = value
        items[.title]?.toolTip = summary.map { "\(value)\n\($0)" } ?? value
    }

    func refreshSourceLayout() {
        let columns = workspace.presentation.queryState.preferredColumns, width = gridWidth()
        zoomControl.update(preferredColumns: columns, clipWidth: width, canDispatch: width.isFinite && width > 0)
        items[.zoom]?.isEnabled = width.isFinite && width > 0 && permitsInput
        items[.zoom]?.menuFormRepresentation = zoomControl.menuRepresentation()
        switch workspace.presentation.page {
        case .pixabay: online.updateCategoryScrollWidth(); online.configureZoom(preferredColumns: columns, clipWidth: width)
        case .workshop, .workshopSubscriptions: steam.configureZoom(preferredColumns: columns, clipWidth: width)
        default: break
        }
    }

    func canZoom(delta: Int) -> Bool { enabled(delta > 0 ? .zoomIn : .zoomOut) }

    private var permitsInput: Bool { WallpaperLibrarySheetPresentation.permitsInput(in: window) }

    private func enabled(_ action: Action, selection: [WallpaperContentItem]? = nil,
                         favoriteEnabled: Bool? = nil, hasPlayable: Bool? = nil) -> Bool {
        guard action == .title || permitsInput else { return false }
        switch action {
        case .back: return makeDirectoryReturnAction() != nil
        case .importFiles: return commands.canImport
        case .select: return commands.canToggleSelection
        case .more: return !(selection ?? commands.selection).isEmpty
        case .remove: return commands.canOrganize && !(selection ?? commands.selection).isEmpty
        case .favorite: return favoriteEnabled ?? commands.canFavorite
        case .addToPlaylist:
            let items = selection ?? commands.selection
            return commands.canOrganize && !items.isEmpty && items.allSatisfy { $0.capabilities.contains(.organize) }
        case .create: return commands.canOrganize
        case .play, .random: return hasPlayable ?? workspace.presentation.queryResult.items.contains { $0.capabilities.contains(.play) }
        case .zoom: return gridWidth() > 0
        case .zoomOut, .zoomIn:
            let availability = WallpaperLibraryGridMetrics.zoomAvailability(
                preferredColumns: workspace.presentation.queryState.preferredColumns, clipWidth: gridWidth())
            return gridWidth() > 0 && (action == .zoomOut ? availability.canZoomOut : availability.canZoomIn)
        default: return true
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let action = Action(rawValue: id.rawValue) else { return steam.makeItem(for: id) ?? online.makeItem(for: id) }
        if let existing = items[action] { return existing }
        let item: NSToolbarItem
        if action == .back {
            item = NSToolbarItem(itemIdentifier: id)
            let button = NSButton(title: "返回", target: self, action: #selector(returnToDirectory))
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            item.view = button
        } else if action == .zoom {
            item = NSToolbarItem(itemIdentifier: id)
            item.view = zoomControl
        } else if action == .search {
            let search = NSSearchToolbarItem(itemIdentifier: id)
            search.searchField = searchField
            search.preferredWidthForSearchField = 240
            item = search
        } else if [.more, .filter, .sort, .addToPlaylist].contains(action) {
            let menuItem = NSMenuToolbarItem(itemIdentifier: id)
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            menuActions[ObjectIdentifier(menu)] = action
            menuItem.menu = menu
            menuItem.showsIndicator = false
            menuItem.isBordered = true
            menuItem.image = NSImage(systemSymbolName: symbol(action), accessibilityDescription: nil)
            item = menuItem
        } else {
            item = NSToolbarItem(itemIdentifier: id)
            item.target = self; item.action = #selector(invoke(_:))
            item.isBordered = action != .title
            if action == .title { item.view = titleLabel }
            else { item.image = NSImage(systemSymbolName: symbol(action), accessibilityDescription: nil) }
        }
        item.label = label(action)
        item.paletteLabel = item.label
        item.toolTip = item.label
        item.autovalidates = false
        item.visibilityPriority = [.title, .search, .importFiles, .create, .play].contains(action) ? .high
            : ([.zoom, .favorite, .addToPlaylist, .more].contains(action) ? .low : .standard)
        items[action] = item
        return item
    }

    private func label(_ action: Action) -> String {
        switch action {
        case .title: return title
        case .back: return "返回所有播放列表"
        case .importFiles: return "导入"
        case .select: return "选择"
        case .previous: return "上一张壁纸"
        case .next: return "下一张壁纸"
        case .remove: return commands.removalTitle
        case .favorite: return commands.favoriteActionState.title
        case .addToPlaylist: return "添加到列表"
        case .play: return "播放"
        case .random: return "随机播放"
        case .create: return "新建列表"
        case .more: return "更多"
        case .filter: return "筛选"
        case .sort: return "排序"
        case .zoom: return "缩放"
        case .zoomOut: return "缩小"
        case .zoomIn: return "放大"
        case .search: return "搜索"
        }
    }

    private func symbol(_ action: Action) -> String {
        switch action {
        case .back: return "chevron.backward"
        case .importFiles, .create: return "plus"
        case .select: return "checkmark.circle"
        case .previous: return "backward.end"
        case .next: return "forward.end"
        case .remove: return "trash"
        case .favorite: return commands.favoriteActionState.isRemoving ? "heart.fill" : "heart"
        case .addToPlaylist: return "text.badge.plus"
        case .play: return "play.fill"
        case .random: return "shuffle"
        case .more: return "ellipsis.circle"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .sort: return "arrow.up.arrow.down"
        case .zoomOut: return "minus.magnifyingglass"
        case .zoomIn: return "plus.magnifyingglass"
        default: return "square.grid.2x2"
        }
    }

    @objc private func returnToDirectory() {
        guard permitsInput else { return }; makeDirectoryReturnAction()?()
    }

    @objc private func invoke(_ sender: NSToolbarItem) {
        guard let action = Action(rawValue: sender.itemIdentifier.rawValue), enabled(action) else { return }
        perform(action)
    }

    private func actionMenuRepresentation(_ action: Action, title: String, symbol: String,
                                          enabled: Bool, selection: [WallpaperContentItem]) -> NSMenuItem {
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let back = action == .back ? makeDirectoryReturnAction() : nil
        let favorite = action == .favorite ? commands.makeFavoriteAction(selection.map(\.reference)) : nil
        let removedItems = action == .remove ? selection : []
        let selectionSession = workspace.presentation.selectionState.sessionID
        let item = ActionMenuItem(title: title, symbol: symbol) { [weak self] in
            guard let self, self.workspace.presentation.page == page, self.workspace.relationships.resetEpoch == epoch,
                  self.enabled(action) else { return }
            if action == .back { back?() }
            else if action == .favorite { favorite?() }
            else if action == .remove {
                guard self.commands.canOrganize, self.workspace.presentation.selectionState.sessionID == selectionSession else { return }
                self.commands.remove(removedItems, from: page)
            } else { self.perform(action) }
        }
        item.isEnabled = action == .favorite ? favorite != nil : enabled
        return item
    }

    private func perform(_ action: Action) {
        switch action {
        case .back: makeDirectoryReturnAction()?()
        case .importFiles: commands.importFiles()
        case .select: commands.toggleSelectionMode()
        case .previous, .next:
            let direction: ManualNavigationDirection = action == .next ? .next : .previous
            if workspace.presentation.page == .videos { commands.manager.navigateWallpaperManually(direction) }
            else { commands.manager.navigateLibraryPlayback(direction, policy: .adjacent) }
        case .remove: commands.remove()
        case .favorite: commands.toggleFavorite()
        case .create: commands.playlists?.handle(.create)
        case .play, .random: commands.playDisplayed(random: action == .random)
        case .zoomOut, .zoomIn: performZoom(delta: action == .zoomIn ? 1 : -1)
        default: break
        }
    }

    func performZoom(delta: Int) {
        makeZoomAction(delta: delta)?()
    }

    private func makeZoomAction(delta: Int) -> (() -> Void)? {
        guard delta != 0, canZoom(delta: delta) else { return nil }
        let page = workspace.presentation.page
        let epoch = workspace.relationships.resetEpoch
        return { [weak self] in
            guard let self, self.workspace.presentation.page == page,
                  self.workspace.relationships.resetEpoch == epoch, self.canZoom(delta: delta) else { return }
            var query = self.workspace.presentation.queryState
            query.preferredColumns = WallpaperLibraryGridMetrics.zoomedColumns(
                preferredColumns: query.preferredColumns, delta: delta, clipWidth: self.gridWidth())
            _ = self.workspace.presentation.setQueryState(query)
        }
    }

    func focusSearch() {
        let page = workspace.presentation.page
        if page == .workshop || page == .workshopSubscriptions { steam.focusSearch(); return }
        if page == .pixabay { online.focusSearch(); return }
        (items[.search] as? NSSearchToolbarItem)?.beginSearchInteraction()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard permitsInput, notification.object as? NSSearchField === searchField else { return }
        var query = workspace.presentation.queryState; query.search = searchField.stringValue
        _ = workspace.presentation.setQueryState(query)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let action = menuActions[ObjectIdentifier(menu)] else { return }
        let source: NSMenu
        switch action {
        case .more: source = makeMoreMenu()
        case .sort: source = makeSortMenu()
        case .filter: source = makeFilterMenu()
        case .addToPlaylist: source = commands.makePlaylistMenu() ?? NSMenu()
        default: return
        }
        menu.removeAllItems()
        // These private factories all enter through this gate. Their handlers
        // retain the fixed page/epoch checks without repeating modal admission.
        source.requireAppActionPermission { [weak self] in self?.permitsInput == true }
        for item in source.items { source.removeItem(item); menu.addItem(item) }
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        if let context = commands.contextMenu(for: commands.selection) {
            for item in context.items { context.removeItem(item); menu.addItem(item) }
        }
        if let recent = commands.makeRecentMenu() {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for item in recent.items { recent.removeItem(item); menu.addItem(item) }
        }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        if !page.isRemoteBrowse && page != .playlists {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(ActionMenuItem(title: "刷新文件状态", symbol: "arrow.clockwise") { [weak workspace] in
                guard let workspace, workspace.presentation.page == page, workspace.relationships.resetEpoch == epoch else { return }
                workspace.refreshSources()
            })
        }
        if case .playlist(let id) = workspace.presentation.page {
            let epoch = workspace.relationships.resetEpoch
            for (title, symbol, action) in [("添加壁纸…", "plus", 0), ("编辑列表…", "pencil", 1), ("复制列表", "doc.on.doc", 2), ("删除列表…", "trash", 3)] {
                menu.addItem(ActionMenuItem(title: title, symbol: symbol) { [weak commands] in
                    guard let commands, commands.canOrganize, commands.workspace.relationships.resetEpoch == epoch else { return }
                    switch action { case 0: commands.onAddWallpapers?(id); case 1: commands.playlists?.handle(.rename(id))
                    case 2: commands.playlists?.handle(.duplicate(id)); default: commands.playlists?.handle(.delete(id)) }
                })
            }
        }
        return menu
    }

    private func sortOptions(page: WallpaperLibraryPage, query: WallpaperLibraryQueryState) -> [(WallpaperLibrarySort, String)] {
        var sorts: [(WallpaperLibrarySort, String)]
        switch page {
        case .playlists: sorts = [(.sourceOrder, "手动顺序"), (.name, "名称"), (.createdAt, "创建时间"), (.modifiedAt, "修改时间")]
        case .playlist: sorts = [(.sourceOrder, "手动顺序"), (.name, "名称"), (.addedAt, "加入列表时间"), (.lastUsed, "成功使用时间"), (.fileSize, "文件大小")]
        case .favorites: sorts = [(.favoritedAt, "标记喜爱时间"), (.name, "名称"), (.lastUsed, "成功使用时间"), (.fileSize, "文件大小")]
        case .downloads: sorts = [(.createdAt, "本地记录时间"), (.name, "名称"), (.fileSize, "文件大小"), (.lastUsed, "成功使用时间")]
        default: sorts = [(.sourceOrder, "默认顺序"), (.name, "名称"), (.fileSize, "文件大小"), (.createdAt, "本地记录时间"), (.lastUsed, "成功使用时间")]
        }
        if query.sort == .legacyTime, query.legacyTimeOrder != nil { sorts.insert((.legacyTime, "旧版时间顺序"), at: 0) }
        return sorts
    }

    private func refreshQueryDescriptions() {
        let page = workspace.presentation.page, query = workspace.presentation.queryState
        var filters: [String] = []
        if let provider = query.provider { filters.append(provider.libraryDisplayName) }
        if let kind = query.kind {
            filters.append([WallpaperMediaKind.image: "图片", .video: "视频", .web: "Web", .scene: "Scene", .unknown: "未知类型"][kind] ?? kind.rawValue)
        }
        if query.status != .all {
            filters.append([WallpaperLibraryStatusFilter.playable: "可播放", .unavailable: "不可用",
                .transferring: "正在下载或更新", .failed: "下载或更新失败"][query.status] ?? query.status.rawValue)
        }
        let filterDescription = filters.isEmpty ? "筛选：全部内容" : "筛选：" + filters.joined(separator: "、")
        items[.filter]?.toolTip = filterDescription
        items[.filter]?.image = NSImage(systemSymbolName: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill",
            accessibilityDescription: filterDescription)
        let sort = query.sort ?? WallpaperLibraryQuery.defaultSort(page)
        let name = sortOptions(page: page, query: query).first { $0.0 == sort }?.1 ?? "默认顺序"
        let ascending = query.sort == nil && (page == .downloads || page == .favorites) ? false : query.ascending
        items[.sort]?.toolTip = "排序：\(name)" + (sort == .sourceOrder ? "" : (ascending ? "，升序" : "，降序"))
    }

    private func makeSortMenu() -> NSMenu {
        let page = workspace.presentation.page, captured = workspace.presentation.queryState
        let sorts = sortOptions(page: page, query: captured)
        let effective = captured.sort ?? WallpaperLibraryQuery.defaultSort(page)
        let ascending = captured.sort == nil && (page == .downloads || page == .favorites) ? false : captured.ascending
        let epoch = workspace.relationships.resetEpoch
        let menu = NSMenu()
        for (sort, title) in sorts {
            let item = ActionMenuItem(title: title, symbol: "") { [weak workspace] in
                guard let workspace, workspace.presentation.page == page, workspace.relationships.resetEpoch == epoch else { return }
                var query = workspace.presentation.queryState
                query.sort = sort
                if sort != .legacyTime { query.legacyTimeOrder = nil }
                if captured.sort == nil { query.ascending = ascending }
                _ = workspace.presentation.setQueryState(query)
            }
            item.state = effective == sort ? .on : .off
            menu.addItem(item)
        }
        if commands.canBeginManualOrdering {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(title: "切回手动并清除筛选以整理", symbol: "hand.draw") { [weak commands] in
                guard let commands, commands.workspace.presentation.page == page,
                      commands.workspace.relationships.resetEpoch == epoch, commands.canBeginManualOrdering else { return }
                commands.beginManualOrdering()
            })
        }
        menu.addItem(.separator())
        let direction = ActionMenuItem(title: ascending ? "改为降序" : "改为升序", symbol: "arrow.up.arrow.down") { [weak workspace] in
            guard let workspace, workspace.presentation.page == page, workspace.relationships.resetEpoch == epoch else { return }
            var query = workspace.presentation.queryState; query.sort = effective; query.ascending = !ascending
            _ = workspace.presentation.setQueryState(query)
        }
        direction.isEnabled = effective != .sourceOrder
        menu.addItem(direction)
        menu.autoenablesItems = false
        return menu
    }

    private func makeFilterMenu() -> NSMenu {
        let page = workspace.presentation.page, query = workspace.presentation.queryState
        let epoch = workspace.relationships.resetEpoch
        let menu = NSMenu()
        func add(_ title: String, selected: Bool, mutate: @escaping (inout WallpaperLibraryQueryState) -> Void) {
            let item = ActionMenuItem(title: title, symbol: "") { [weak workspace] in
                guard let workspace, workspace.presentation.page == page, workspace.relationships.resetEpoch == epoch else { return }
                var query = workspace.presentation.queryState; mutate(&query); _ = workspace.presentation.setQueryState(query)
            }
            item.state = selected ? .on : .off
            menu.addItem(item)
        }
        add("全部来源", selected: query.provider == nil) { $0.provider = nil }
        let providers: [WallpaperProvider] = page == .downloads ? [.steamWorkshop, .pixabay] : WallpaperProvider.allCases
        for provider in providers { add(provider.libraryDisplayName, selected: query.provider == provider) { $0.provider = provider } }
        menu.addItem(.separator())
        let counts = workspace.presentation.mediaKindCounts
        add("全部类型（\(counts.values.reduce(0, +))）", selected: query.kind == nil) { $0.kind = nil }
        for (kind, title) in [(WallpaperMediaKind.image, "图片"), (.video, "视频"), (.web, "Web"), (.scene, "Scene")] {
            if page == .downloads, kind == .image { continue }
            add("\(title)（\(counts[kind, default: 0])）", selected: query.kind == kind) { $0.kind = kind }
        }
        menu.addItem(.separator())
        add("全部状态", selected: query.status == .all) { $0.status = .all }
        for (status, title) in [(WallpaperLibraryStatusFilter.playable, "可播放"), (.unavailable, "不可用"), (.transferring, "正在下载或更新"), (.failed, "下载或更新失败")] {
            add(title, selected: query.status == status) { $0.status = status }
        }
        if page == .downloads {
            menu.addItem(.separator())
            let service = SteamWorkshopService.shared
            let adult = ActionMenuItem(title: "成人内容", symbol: "") { [weak workspace] in
                guard let workspace, workspace.presentation.page == page, workspace.relationships.resetEpoch == epoch else { return }
                service.downloadsShowsAdultContent.toggle()
            }
            adult.state = service.downloadsShowsAdultContent ? .on : .off
            menu.addItem(adult)
        }
        return menu
    }
}
