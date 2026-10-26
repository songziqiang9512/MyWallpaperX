import AppKit

/// Native controls over the same typed browser queries; no second search/filter state.
@MainActor final class OnlineImageToolbarController: NSObject, NSSearchFieldDelegate {
    enum Item: String, CaseIterable {
        case back = "OnlineImageBack", account = "OnlineImageAccount", refresh = "OnlineImageRefresh"
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
    private lazy var popover = ToolbarMenuPopoverPresenter(fallbackAnchorProvider: { [weak self] in self?.window?.contentView })

    init(images: WallpaperLibraryOnlineImages, workspace: WallpaperLibraryWorkspace, window: NSWindow) {
        self.images = images; self.workspace = workspace; self.window = window
        super.init()
        search.delegate = self; search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.placeholderString = "搜索作品"
        search.widthAnchor.constraint(equalToConstant: 220).isActive = true
    }
    var identifiers: [NSToolbarItem.Identifier] {
        guard images.session(for: workspace.presentation.page) != nil else { return [] }
        return (images.hasReturnContext(for: workspace.presentation.page) ? [Item.back.id] : [])
            + [Item.account.id, Item.refresh.id, .space, Item.sort.id, Item.filter.id, .space,
               .init("zoom"), .space, Item.search.id]
    }

    func refresh() {
        let next = workspace.presentation.page
        if page != next { debounce?.cancel(); page = next; popover.close() }
        guard let session = images.session(for: next) else { return }
        if observedQuery != session.state.query || window?.isVisible != true || window?.isMiniaturized == true {
            debounce?.cancel(); observedQuery = session.state.query
        }
        if search.currentEditor() == nil { search.stringValue = session.state.query.search }
        search.placeholderString = next == .wallhaven ? "搜索 Wallhaven" : "搜索 Pixiv"
        items[.refresh]?.isEnabled = !session.state.isLoading
        for type in [Item.account, .sort, .filter] {
            items[type]?.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: label(type), rows: rows(type))
        }
        for type in [Item.back, .refresh] {
            items[type]?.menuFormRepresentation = ActionMenuItem(title: label(type), symbol: symbol(type)) { [weak self] in self?.perform(type) }
        }
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
            let button = NSButton(title: type == .filter ? "筛选" : "", target: self, action: #selector(invoke(_:)))
            button.identifier = .init(type.rawValue)
            button.image = NSImage(systemSymbolName: symbol(type), accessibilityDescription: label(type))
            button.imagePosition = type == .filter ? .imageLeading : .imageOnly
            button.toolTip = label(type)
            WallpaperLibraryControlStyle.capsule(button)
            item.view = button
        }
        items[type] = item; return item
    }

    func focusSearch() { (items[.search] as? NSSearchToolbarItem)?.beginSearchInteraction() }

    @objc private func invoke(_ sender: NSButton) {
        guard let type = sender.identifier.flatMap({ Item(rawValue: $0.rawValue) }),
              images.session(for: workspace.presentation.page) != nil else { return }
        if type == .account || type == .sort || type == .filter {
            guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            popover.toggle(anchor: sender) { [weak self] in self?.rows(type) ?? [] }
        } else { perform(type) }
    }

    private func perform(_ type: Item) {
        guard let session = images.session(for: workspace.presentation.page), WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        debounce?.cancel()
        switch type { case .back: images.goBack(); case .refresh: session.refresh(); case .search: focusSearch(); default: break }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let session = images.session(for: workspace.presentation.page) else { return }
        let text = search.stringValue, page = workspace.presentation.page
        let query = session.state.query, token = session.state.refreshToken
        debounce?.cancel()
        debounce = Task { [weak self, weak session] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, let session, workspace.presentation.page == page,
                  session.state.query == query, session.state.refreshToken == token,
                  window?.isVisible == true, window?.isMiniaturized == false else { return }
            session.setSearch(text)
        }
    }

    private func rows(_ item: Item) -> [ToolbarMenuPopoverPresenter.Row] {
        guard let session = images.session(for: workspace.presentation.page) else { return [] }
        if item == .account {
            if session.source == .wallhaven {
                return [.init(title: "设置 API Key…", kind: .action, handler: { [weak images] in images?.presentAccount() })]
            }
            return [
                .init(title: "登录 Pixiv…", kind: .action, handler: { [weak images] in images?.presentAccount() }),
                .init(title: "账号内容设置…", kind: .action, handler: { [weak images] in images?.presentAccount(settings: true) }),
                .separator(),
                .init(title: "退出当前会话", kind: .action, handler: { [weak images] in images?.logout() })
            ]
        }
        switch session.state.query {
        case .wallhaven(let query): return wallhavenRows(item, query: query, session: session)
        case .pixiv(let query): return pixivRows(item, query: query, session: session)
        }
    }

    private func choice(_ title: String, selected: Bool, session: OnlineImageBrowserSession,
                        query: OnlineImageBrowserSession.Query) -> ToolbarMenuPopoverPresenter.Row {
        let page = workspace.presentation.page
        return .init(title: title, kind: .check, isChecked: selected, handler: { [weak self, weak session] in
            guard let self, let session, workspace.presentation.page == page else { return }
            session.setQuery(query)
        })
    }

    private func wallhavenRows(_ item: Item, query: WallhavenQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        func row(_ title: String, selected: Bool, edit: (inout WallhavenQuery) -> Void) -> ToolbarMenuPopoverPresenter.Row {
            var value = query; edit(&value)
            return choice(title, selected: selected, session: session, query: .wallhaven(value))
        }
        if item == .sort {
            var rows = WallhavenQuery.Sorting.allCases.map { value in row(value.displayName, selected: query.sorting == value) { $0.sorting = value } }
            if query.sorting == .popular {
                rows += [.separator(), .header("热门范围")]
                for (value, title) in [(WallhavenQuery.TopRange.day, "今天"), (.week, "本周"), (.month, "本月"), (.year, "一年内")] {
                    rows.append(row(title, selected: query.topRange == value) { $0.topRange = value })
                }
            }
            return rows
        }
        var rows: [ToolbarMenuPopoverPresenter.Row] = [.header("分类")]
        for (index, title) in ["综合", "动漫", "人物"].enumerated() {
            let chars = Array(query.categories), checked = chars[index] == "1"
            rows.append(row(title, selected: checked) { value in
                var mask = Array(value.categories); mask[index] = checked ? "0" : "1"
                value.categories = mask.allSatisfy { $0 == "0" } ? "111" : String(mask)
            })
        }
        rows += [.separator(), .header("最低分辨率")]
        for (size, title) in [(String?.none, "不限"), ("1920x1080", "1920 × 1080"), ("2560x1440", "2560 × 1440"), ("3840x2160", "3840 × 2160")] {
            rows.append(row(title, selected: query.minimumResolution == size) { $0.minimumResolution = size; $0.resolutions = [] })
        }
        rows += [.separator(), .header("比例")]
        for (ratio, title) in [(String?.none, "不限"), ("16x9", "16:9"), ("16x10", "16:10"), ("21x9", "21:9")] {
            rows.append(row(title, selected: query.ratios.first == ratio) { $0.ratios = ratio.map { [$0] } ?? [] })
        }
        rows += [.separator(), .header("内容")]
        for (mask, title) in [("100", "仅安全内容"), ("110", "含敏感内容"), ("111", "全部内容（成人需 API Key）")] {
            rows.append(row(title, selected: query.purity == mask) { $0.purity = mask })
        }
        return rows
    }

    private func pixivRows(_ item: Item, query: PixivQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        if item == .sort {
            if !query.searchWord.isEmpty || query.authorID != nil { return [.init(title: "按最新作品显示", kind: .info)] }
            return [(PixivRankingMode.daily, "每日排行"), (.weekly, "每周排行"), (.monthly, "每月排行")].map { mode, title in
                var value = query; value.ranking = mode
                return choice(title, selected: query.ranking == mode, session: session, query: .pixiv(value))
            }
        }
        return [(PixivWorkType.illustrations, "插画"), (.manga, "漫画")].map { type, title in
            var value = query; value.workType = type
            return choice(title, selected: query.workType == type, session: session, query: .pixiv(value))
        } + [.separator(), .init(title: "按站点允许的安全内容浏览", kind: .info)]
    }

    private func label(_ item: Item) -> String {
        switch item { case .back: "返回"; case .account: "账号"; case .refresh: "刷新"; case .sort: "排序"; case .filter: "筛选"; case .search: "搜索" }
    }
    private func symbol(_ item: Item) -> String {
        switch item { case .back: "chevron.backward"; case .account: "person.crop.circle"; case .refresh: "arrow.clockwise"; case .sort: "line.3.horizontal"; case .filter: "line.3.horizontal.decrease.circle"; case .search: "magnifyingglass" }
    }
}
