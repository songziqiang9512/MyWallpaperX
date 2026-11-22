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
    private let filterPopover: NSPopover = { let value = NSPopover(); value.behavior = .transient; return value }()
    private lazy var filterScrollDismissal = ToolbarPopoverScrollDismissal(popover: filterPopover)

    init(images: WallpaperLibraryOnlineImages, workspace: WallpaperLibraryWorkspace, window: NSWindow) {
        self.images = images; self.workspace = workspace; self.window = window
        super.init()
        search.delegate = self; search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.placeholderString = String(localized: "Search Items")
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
        if page != next { debounce?.cancel(); debounce = nil; page = next; filterPopover.performClose(nil) }
        guard let session = images.session(for: next) else { return }
        let queryChanged = observedQuery != session.state.query
        if case .pixiv(let previous)? = observedQuery, case .pixiv(let current) = session.state.query,
           (previous.authorID?.isEmpty == false || !previous.searchWord.isEmpty)
            != (current.authorID?.isEmpty == false || !current.searchWord.isEmpty) { filterPopover.performClose(nil) }
        let accountStatus = images.accountStatus(for: session.source)
        let accountChanged = observedAccountStatus != accountStatus
        observedAccountStatus = accountStatus
        if queryChanged || window?.isVisible != true || window?.isMiniaturized == true {
            debounce?.cancel(); debounce = nil; observedQuery = session.state.query
        }
        if search.currentEditor() == nil { search.stringValue = session.state.query.search }
        search.placeholderString = next == .wallhaven ? String(localized: "Search Wallhaven") : String(localized: "Search Pixiv")
        for type in [Item.account, .sort] {
            guard items[type]?.menuFormRepresentation == nil || queryChanged || (type == .account && accountChanged) else { continue }
            items[type]?.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: label(type), rows: rows(type))
        }
        if queryChanged || items[.filter]?.menuFormRepresentation == nil {
            items[.filter]?.menuFormRepresentation = filterMenuRepresentation()
        }
        if queryChanged, filterPopover.isShown { (filterPopover.contentViewController as? WallpaperFilterPanelController)?.synchronize() }
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
            let button = NSButton(title: type == .filter ? String(localized: "Filter") : type == .back ? String(localized: "Back") : "", target: self, action: #selector(invoke(_:)))
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
            item.menuFormRepresentation = filterMenuRepresentation()
        } else if [.account, .sort].contains(type) {
            item.menuFormRepresentation = ToolbarMenu.menuRepresentation(title: label(type), rows: rows(type))
        }
        return item
    }

    func focusSearch() { (items[.search] as? NSSearchToolbarItem)?.beginSearchInteraction() }

    @objc private func invoke(_ sender: NSButton) {
        guard let type = sender.identifier.flatMap({ Item(rawValue: $0.rawValue) }),
              images.session(for: workspace.presentation.page) != nil else { return }
        if type == .filter {
            showFilter()
        } else if type == .account || type == .sort {
            guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            filterPopover.performClose(nil)
            ToolbarMenu.popUp(anchor: sender, rows: rows(type))
        } else { perform(type) }
    }

    private func filterMenuRepresentation() -> NSMenuItem {
        let page = workspace.presentation.page
        return ActionMenuItem(title: String(localized: "Filter"), symbol: WallpaperLibraryControlStyle.filterSymbol) { [weak self] in
            guard let self, self.workspace.presentation.page == page else { return }
            self.showFilter()
        }
    }

    private func showFilter() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window),
              let item = items[.filter], let contentView = window?.contentView else { return }
        if filterPopover.isShown { filterPopover.performClose(nil); return }
        guard let panel = makeFilterPanel() else { return }
        filterPopover.contentViewController = panel; panel.loadViewIfNeeded()
        filterPopover.contentSize = panel.preferredContentSize
        filterScrollDismissal.watch(relativeTo: contentView)
        filterPopover.show(relativeTo: item)
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

    private func rows(_ item: Item) -> [ToolbarMenu.Row] {
        guard let session = images.session(for: workspace.presentation.page) else { return [] }
        if item == .account {
            var rows = images.accountStatus(for: session.source).map { ToolbarMenu.Row(title: $0, kind: .info) }
            rows.append(.separator())
            if session.source == .wallhaven {
                rows.append(.init(title: String(localized: "Manage API Key…"), kind: .action, handler: { [weak images] in images?.presentAccount() }))
            } else {
                if images.hasPixivIdentity {
                    rows.append(.init(title: String(localized: "My Works"), kind: .action, handler: { [weak images] in images?.openMyPixivWorks() }))
                    rows.append(.init(title: String(localized: "Profile (Web Page)"), kind: .action, handler: { [weak images] in images?.openPixivProfile() }))
                }
                rows.append(.init(title: images.hasPixivIdentity ? String(localized: "Switch Account…") : String(localized: "Sign In to Pixiv…"), kind: .action,
                    handler: { [weak images] in images?.presentAccount() }))
                rows.append(.init(title: String(localized: "Account Content Settings…"), kind: .action, handler: { [weak images] in images?.presentAccount(settings: true) }))
            }
            rows.append(.init(title: String(localized: "Refresh Account Info"), kind: .action, isEnabled: images.canRefreshAccount(session.source),
                handler: { [weak images] in images?.refreshAccountInformation(session.source) }))
            if session.source == .pixiv {
                rows.append(.separator())
                rows.append(.init(title: String(localized: "Sign Out of Current Session"), kind: .action, isEnabled: images.canLogoutPixiv,
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
                        edit: @escaping (OnlineImageBrowserSession.Query) -> OnlineImageBrowserSession.Query) -> ToolbarMenu.Row {
        let page = workspace.presentation.page
        return .init(title: title, kind: .action, isChecked: selected, handler: { [weak self, weak session] in
            guard let self, let session else { return }
            applyQueryEdit(session: session, page: page, transform: edit)
        })
    }

    private func wallhavenRows(query: WallhavenQuery, session: OnlineImageBrowserSession) -> [ToolbarMenu.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout WallhavenQuery) -> Void) -> ToolbarMenu.Row {
            choice(title, selected: selected, session: session) { query in
                guard case .wallhaven(var value) = query else { return query }
                edit(&value)
                return .wallhaven(value)
            }
        }
        var rows: [ToolbarMenu.Row] = [.header(String(localized: "Sort By"))]
        rows += WallhavenQuery.Sorting.allCases.map { value in
            row(value.displayName, selected: query.sorting == value) { $0.sorting = value }
        }
        if query.sorting != .random {
            rows += [.separator(), .header(String(localized: "Sort Direction"))]
            rows += WallhavenQuery.Order.allCases.map { value in
                row(value.displayName, selected: query.order == value) {
                    if $0.sorting != .random { $0.order = value }
                }
            }
        }
        if query.sorting == .popular {
            rows += [.separator(), .header(String(localized: "Popularity Range"))]
            rows += WallhavenQuery.TopRange.allCases.map { value in
                row(value.displayName, selected: query.topRange == value) {
                    if $0.sorting == .popular { $0.topRange = value }
                }
            }
        }
        return rows
    }

    private func pixivRows(query: PixivQuery, session: OnlineImageBrowserSession) -> [ToolbarMenu.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout PixivQuery) -> Void) -> ToolbarMenu.Row {
            choice(title, selected: selected, session: session) { query in
                guard case .pixiv(var value) = query else { return query }
                edit(&value)
                return .pixiv(value)
            }
        }
        let author = query.authorID?.isEmpty == false
        let chronological = author || !query.searchWord.isEmpty
        if chronological {
            return [.header(String(localized: "Artwork Order"))] + [(PixivOrder.newest, String(localized: "Newest First")), (.oldest, String(localized: "Oldest First"))].map { order, title in
                row(title, selected: query.order == order) {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.order = order }
                }
            }
        }
        return [.header(String(localized: "Ranking"))] + [(PixivRankingMode.daily, String(localized: "Daily Ranking")), (.weekly, String(localized: "Weekly Ranking")), (.monthly, String(localized: "Monthly Ranking"))].map { mode, title in
            row(title, selected: query.ranking == mode) {
                if $0.authorID?.isEmpty != false && $0.searchWord.isEmpty { $0.ranking = mode }
            }
        } + [.init(title: String(localized: "Show by Site Ranking"), kind: .info)]
    }

    private func label(_ item: Item) -> String {
        switch item { case .back: String(localized: "Back"); case .account: String(localized: "Account"); case .sort: String(localized: "Sort"); case .filter: String(localized: "Filter"); case .search: String(localized: "Search") }
    }
    private func symbol(_ item: Item) -> String {
        switch item { case .back: "chevron.backward"; case .account: "person.crop.circle"; case .sort: WallpaperLibraryControlStyle.sortSymbol; case .filter: WallpaperLibraryControlStyle.filterSymbol; case .search: "magnifyingglass" }
    }
}
