import AppKit

/// Native controls over the same typed browser queries; no second search/filter state.
@MainActor final class OnlineImageToolbarController: NSObject, NSSearchFieldDelegate {
    enum Item: String, CaseIterable {
        case back = "OnlineImageBack", account = "OnlineImageAccount"
        case sort = "OnlineImageSort", filter = "OnlineImageFilter", search = "OnlineImageSearch"
        var id: NSToolbarItem.Identifier { .init(rawValue) }
    }
    private let images: WallpaperLibraryOnlineImages
    private let workspace: WallpaperLibraryWorkspace
    private weak var window: NSWindow?
    private var items: [Item: NSToolbarItem] = [:]
    private let search = NSSearchField()
    private var debounce: Task<Void, Never>?
    private var page: WallpaperLibraryPage?
    private var observedQuery: OnlineImageBrowserSession.Query?
    private var observedAccountStatus: [String]?
    private lazy var popover = ToolbarMenuPopoverPresenter(fallbackAnchorProvider: { [weak self] in self?.window?.contentView })
    private let filterPopover: NSPopover = { let value = NSPopover(); value.behavior = .transient; return value }()
    private lazy var filterScrollDismissal = ToolbarPopoverScrollDismissal(popover: filterPopover)

    init(images: WallpaperLibraryOnlineImages, workspace: WallpaperLibraryWorkspace, window: NSWindow) {
        self.images = images; self.workspace = workspace; self.window = window
        super.init()
        search.delegate = self; search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.placeholderString = "搜索作品"
        search.widthAnchor.constraint(equalToConstant: WallpaperLibraryControlStyle.toolbarSearchWidth).isActive = true
    }
    var identifiers: [NSToolbarItem.Identifier] {
        guard images.session(for: workspace.presentation.page) != nil else { return [] }
        return (images.hasReturnContext(for: workspace.presentation.page) ? [Item.back.id, .space] : [])
            + [Item.account.id, .init("downloadTasks"), .space, Item.sort.id, Item.filter.id, .space,
               .init("zoom"), .space, Item.search.id]
    }

    func refresh() {
        let next = workspace.presentation.page
        if page != next { debounce?.cancel(); debounce = nil; page = next; popover.close(); filterPopover.performClose(nil) }
        guard let session = images.session(for: next) else { return }
        let queryChanged = observedQuery != session.state.query
        if case .pixiv(let previous)? = observedQuery, case .pixiv(let current) = session.state.query,
           (previous.authorID?.isEmpty == false || !previous.searchWord.isEmpty)
            != (current.authorID?.isEmpty == false || !current.searchWord.isEmpty) { filterPopover.performClose(nil) }
        let accountStatus = images.accountStatus(for: session.source)
        let accountChanged = observedAccountStatus != accountStatus
        observedAccountStatus = accountStatus
        if accountChanged { popover.refresh() }
        if queryChanged || window?.isVisible != true || window?.isMiniaturized == true {
            debounce?.cancel(); debounce = nil; observedQuery = session.state.query
        }
        if search.currentEditor() == nil { search.stringValue = session.state.query.search }
        search.placeholderString = next == .wallhaven ? "搜索 Wallhaven" : "搜索 Pixiv"
        for type in [Item.account, .sort] {
            guard items[type]?.menuFormRepresentation == nil || queryChanged || (type == .account && accountChanged) else { continue }
            items[type]?.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: label(type), rows: rows(type))
        }
        if queryChanged || items[.filter]?.menuFormRepresentation == nil {
            items[.filter]?.menuFormRepresentation = makeFilterPanel()?.menuRepresentation(title: "筛选")
        }
        if queryChanged { (filterPopover.contentViewController as? WallpaperFilterPanelController)?.synchronize() }
        items[.back]?.menuFormRepresentation = ActionMenuItem(title: label(.back), symbol: symbol(.back)) { [weak self] in self?.perform(.back) }
    }

    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard let type = Item(rawValue: id.rawValue) else { return nil }
        if let item = items[type] { return item }
        let item: NSToolbarItem
        if type == .search {
            let searchItem = NSSearchToolbarItem(itemIdentifier: id)
            searchItem.searchField = search
            item = searchItem
        } else { item = NSToolbarItem(itemIdentifier: id) }
        item.label = label(type); item.paletteLabel = label(type); item.toolTip = label(type)
        if type != .search {
            let button = NSButton(title: type == .filter ? "筛选" : type == .back ? "返回" : "", target: self, action: #selector(invoke(_:)))
            button.identifier = .init(type.rawValue)
            button.image = NSImage(systemSymbolName: symbol(type), accessibilityDescription: label(type))
            button.toolTip = label(type)
            if type == .account { WallpaperLibraryControlStyle.toolbarAccountButton(button) }
            else { button.imagePosition = (type == .filter || type == .back) ? .imageLeading : .imageOnly }
            WallpaperLibraryControlStyle.capsule(button)
            item.view = button
        }
        items[type] = item
        if type == .filter {
            item.menuFormRepresentation = makeFilterPanel()?.menuRepresentation(title: "筛选")
        } else if [.account, .sort].contains(type) {
            item.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: label(type), rows: rows(type))
        }
        return item
    }

    func focusSearch() { (items[.search] as? NSSearchToolbarItem)?.beginSearchInteraction() }

    @objc private func invoke(_ sender: NSButton) {
        guard let type = sender.identifier.flatMap({ Item(rawValue: $0.rawValue) }),
              images.session(for: workspace.presentation.page) != nil else { return }
        if type == .filter {
            guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            popover.close()
            if filterPopover.isShown { filterPopover.performClose(nil); return }
            guard let panel = makeFilterPanel() else { return }
            filterPopover.contentViewController = panel; panel.loadViewIfNeeded()
            filterPopover.contentSize = panel.preferredContentSize
            filterScrollDismissal.watch(relativeTo: sender)
            filterPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        } else if type == .account || type == .sort {
            guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            filterPopover.performClose(nil)
            popover.toggle(anchor: sender) { [weak self] in self?.rows(type) ?? [] }
        } else { perform(type) }
    }

    private func makeFilterPanel() -> WallpaperFilterPanelController? {
        let capturedPage = workspace.presentation.page
        guard let session = images.session(for: capturedPage) else { return nil }
        return OnlineImageFilterPanel.make(session: session) { [weak self, weak session] transform in
            guard let self, let session else { return }
            applyQueryEdit(session: session, page: capturedPage, transform: transform)
        }
    }

    private func applyQueryEdit(session: OnlineImageBrowserSession, page: WallpaperLibraryPage,
                                transform: (OnlineImageBrowserSession.Query) -> OnlineImageBrowserSession.Query) {
        guard workspace.presentation.page == page, WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        var query = session.state.query
        if debounce != nil {
            debounce?.cancel(); debounce = nil
            switch query {
            case .wallhaven(var value): value.search = search.stringValue; value.authorUsername = nil; query = .wallhaven(value)
            case .pixiv(var value): value.search = search.stringValue; value.authorID = nil; query = .pixiv(value)
            }
        }
        session.setQuery(transform(query))
    }

    private func perform(_ type: Item) {
        guard images.session(for: workspace.presentation.page) != nil, WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        debounce?.cancel(); debounce = nil
        switch type { case .back: images.goBack(); case .search: focusSearch(); default: break }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let session = images.session(for: workspace.presentation.page) else { return }
        let text = search.stringValue, page = workspace.presentation.page
        let query = session.state.query, token = session.state.refreshToken
        debounce?.cancel()
        debounce = Task { [weak self, weak session] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            debounce = nil
            guard let session, workspace.presentation.page == page,
                  session.state.query == query, session.state.refreshToken == token,
                  window?.isVisible == true, window?.isMiniaturized == false else { return }
            session.setSearch(text)
        }
    }

    private func rows(_ item: Item) -> [ToolbarMenuPopoverPresenter.Row] {
        guard let session = images.session(for: workspace.presentation.page) else { return [] }
        if item == .account {
            var rows = images.accountStatus(for: session.source).map { ToolbarMenuPopoverPresenter.Row(title: $0, kind: .info) }
            rows.append(.separator())
            if session.source == .wallhaven {
                rows.append(.init(title: "管理 API Key…", kind: .action, handler: { [weak images] in images?.presentAccount() }))
            } else {
                if images.hasPixivIdentity {
                    rows.append(.init(title: "我的作品", kind: .action, handler: { [weak images] in images?.openMyPixivWorks() }))
                    rows.append(.init(title: "个人主页（网页）", kind: .action, handler: { [weak images] in images?.openPixivProfile() }))
                }
                rows.append(.init(title: images.hasPixivIdentity ? "切换账号…" : "登录 Pixiv…", kind: .action,
                    handler: { [weak images] in images?.presentAccount() }))
                rows.append(.init(title: "账号内容设置…", kind: .action, handler: { [weak images] in images?.presentAccount(settings: true) }))
            }
            rows.append(.init(title: "刷新账号信息", kind: .action, isEnabled: images.canRefreshAccount(session.source),
                handler: { [weak images] in images?.refreshAccountInformation(session.source) }))
            if session.source == .pixiv {
                rows.append(.separator())
                rows.append(.init(title: "退出当前会话", kind: .action, isEnabled: images.canLogoutPixiv,
                    handler: { [weak images] in images?.logout() }))
            }
            return rows
        }
        switch session.state.query {
        case .wallhaven(let query): return wallhavenRows(query: query, session: session)
        case .pixiv(let query): return pixivRows(query: query, session: session)
        }
    }

    private func choice(_ title: String, selected: Bool, session: OnlineImageBrowserSession,
                        edit: @escaping (OnlineImageBrowserSession.Query) -> OnlineImageBrowserSession.Query) -> ToolbarMenuPopoverPresenter.Row {
        let page = workspace.presentation.page
        return .init(title: title, kind: .check, isChecked: selected, handler: { [weak self, weak session] in
            guard let self, let session else { return }
            applyQueryEdit(session: session, page: page, transform: edit)
        })
    }

    private func wallhavenRows(query: WallhavenQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout WallhavenQuery) -> Void) -> ToolbarMenuPopoverPresenter.Row {
            choice(title, selected: selected, session: session) { query in
                guard case .wallhaven(var value) = query else { return query }
                edit(&value)
                return .wallhaven(value)
            }
        }
        var rows: [ToolbarMenuPopoverPresenter.Row] = [.header("排序方式")]
        rows += WallhavenQuery.Sorting.allCases.map { value in
            row(value.displayName, selected: query.sorting == value) { $0.sorting = value }
        }
        if query.sorting != .random {
            rows += [.separator(), .header("排序方向")]
            rows += WallhavenQuery.Order.allCases.map { value in
                row(value.displayName, selected: query.order == value) {
                    if $0.sorting != .random { $0.order = value }
                }
            }
        }
        if query.sorting == .popular {
            rows += [.separator(), .header("热门范围")]
            rows += WallhavenQuery.TopRange.allCases.map { value in
                row(value.displayName, selected: query.topRange == value) {
                    if $0.sorting == .popular { $0.topRange = value }
                }
            }
        }
        return rows
    }

    private func pixivRows(query: PixivQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout PixivQuery) -> Void) -> ToolbarMenuPopoverPresenter.Row {
            choice(title, selected: selected, session: session) { query in
                guard case .pixiv(var value) = query else { return query }
                edit(&value)
                return .pixiv(value)
            }
        }
        let author = query.authorID?.isEmpty == false
        let chronological = author || !query.searchWord.isEmpty
        if chronological {
            return [.header("作品顺序")] + [(PixivOrder.newest, "最新优先"), (.oldest, "最早优先")].map { order, title in
                row(title, selected: query.order == order) {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.order = order }
                }
            }
        }
        return [.header("排行")] + [(PixivRankingMode.daily, "每日排行"), (.weekly, "每周排行"), (.monthly, "每月排行")].map { mode, title in
            row(title, selected: query.ranking == mode) {
                if $0.authorID?.isEmpty != false && $0.searchWord.isEmpty { $0.ranking = mode }
            }
        } + [.init(title: "按站点排名显示", kind: .info)]
    }

    private func label(_ item: Item) -> String {
        switch item { case .back: "返回"; case .account: "账号"; case .sort: "排序"; case .filter: "筛选"; case .search: "搜索" }
    }
    private func symbol(_ item: Item) -> String {
        switch item { case .back: "chevron.backward"; case .account: "person.crop.circle"; case .sort: WallpaperLibraryControlStyle.sortSymbol; case .filter: WallpaperLibraryControlStyle.filterSymbol; case .search: "magnifyingglass" }
    }
}
