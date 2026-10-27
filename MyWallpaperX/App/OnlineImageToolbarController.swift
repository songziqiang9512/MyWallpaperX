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
    private var observedAccountStatus: String?
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
        if page != next { debounce?.cancel(); debounce = nil; page = next; popover.close() }
        guard let session = images.session(for: next) else { return }
        let queryChanged = observedQuery != session.state.query
        let accountStatus = images.pixivAccountStatus
        let accountChanged = observedAccountStatus != accountStatus
        observedAccountStatus = accountStatus
        if queryChanged || window?.isVisible != true || window?.isMiniaturized == true {
            debounce?.cancel(); debounce = nil; observedQuery = session.state.query
        }
        if search.currentEditor() == nil { search.stringValue = session.state.query.search }
        search.placeholderString = next == .wallhaven ? "搜索 Wallhaven" : "搜索 Pixiv"
        items[.refresh]?.isEnabled = !session.state.isLoading
        for type in [Item.account, .sort, .filter] {
            guard items[type]?.menuFormRepresentation == nil || queryChanged || (type == .account && accountChanged) else { continue }
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
        items[type] = item
        if [.account, .sort, .filter].contains(type) {
            item.menuFormRepresentation = ToolbarMenuPopoverPresenter.menuRepresentation(title: label(type), rows: rows(type))
        }
        return item
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
        debounce?.cancel(); debounce = nil
        switch type { case .back: images.goBack(); case .refresh: session.refresh(); case .search: focusSearch(); default: break }
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
            if session.source == .wallhaven {
                return [.init(title: "设置 API Key…", kind: .action, handler: { [weak images] in images?.presentAccount() })]
            }
            return [
                .init(title: images.pixivAccountStatus, kind: .info), .separator(),
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
                        edit: @escaping (OnlineImageBrowserSession) -> Void) -> ToolbarMenuPopoverPresenter.Row {
        let page = workspace.presentation.page
        return .init(title: title, kind: .check, isChecked: selected, handler: { [weak self, weak session] in
            guard let self, let session, workspace.presentation.page == page,
                  WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
            if debounce != nil {
                debounce?.cancel(); debounce = nil
                session.setSearch(search.stringValue)
            }
            edit(session)
        })
    }

    private func wallhavenRows(_ item: Item, query: WallhavenQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout WallhavenQuery) -> Void) -> ToolbarMenuPopoverPresenter.Row {
            choice(title, selected: selected, session: session) { current in
                guard case .wallhaven(var value) = current.state.query else { return }
                edit(&value)
                current.setQuery(.wallhaven(value))
            }
        }
        if item == .sort {
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
        var rows: [ToolbarMenuPopoverPresenter.Row] = [.header("分类")]
        let categories = Array(query.categories)
        for (index, title) in ["综合", "动漫", "人物"].enumerated() {
            let checked = categories[index] == "1"
            rows.append(row(title, selected: checked) { value in
                var mask = Array(value.categories); mask[index] = mask[index] == "1" ? "0" : "1"
                value.categories = mask.allSatisfy { $0 == "0" } ? "111" : String(mask)
            })
        }
        rows += [.separator(), .header("分辨率")]
        rows.append(row("不限", selected: query.minimumResolution == nil && query.resolutions.isEmpty) {
            $0.minimumResolution = nil; $0.resolutions = []
        })
        rows.append(.header("最低分辨率"))
        for size in ["1920x1080", "2560x1440", "3440x1440", "3840x2160", "5120x2880", "7680x4320"] {
            rows.append(row(size.replacingOccurrences(of: "x", with: " × "), selected: query.minimumResolution == size) {
                $0.minimumResolution = size; $0.resolutions = []
            })
        }
        rows.append(.header("精确分辨率"))
        for size in ["1920x1080", "1920x1200", "2560x1440", "2560x1600", "3440x1440", "3840x1600", "3840x2160", "5120x2880", "7680x4320"] {
            rows.append(row(size.replacingOccurrences(of: "x", with: " × "), selected: query.resolutions == [size]) {
                $0.resolutions = [size]; $0.minimumResolution = nil
            })
        }
        rows += [.separator(), .header("比例")]
        rows.append(row("不限", selected: query.ratios.isEmpty) { $0.ratios = [] })
        for ratio in ["16x9", "16x10", "21x9", "32x9", "4x3", "3x2", "5x4", "1x1", "9x16", "10x16", "9x18"] {
            rows.append(row(ratio.replacingOccurrences(of: "x", with: ":"), selected: query.ratios == [ratio]) {
                $0.ratios = [ratio]
            })
        }
        rows += [.separator(), .header("颜色")]
        rows.append(row("不限", selected: query.color == nil) { $0.color = nil })
        let selectedColor = query.color?.replacingOccurrences(of: "#", with: "").lowercased()
        rows += WallhavenQuery.colorPalette.map { color in
            row("#" + color.uppercased(), selected: selectedColor == color) { $0.color = color }
        }
        rows += [.separator(), .header("内容")]
        for (mask, title) in [("100", "仅安全内容"), ("110", "安全与敏感内容"), ("010", "仅敏感内容"),
                              ("001", "仅成人内容（需 API Key）"), ("111", "全部内容（成人需 API Key）")] {
            rows.append(row(title, selected: query.purity == mask) { $0.purity = mask })
        }
        return rows
    }

    private func pixivRows(_ item: Item, query: PixivQuery, session: OnlineImageBrowserSession) -> [ToolbarMenuPopoverPresenter.Row] {
        func row(_ title: String, selected: Bool, edit: @escaping (inout PixivQuery) -> Void) -> ToolbarMenuPopoverPresenter.Row {
            choice(title, selected: selected, session: session) { current in
                guard case .pixiv(var value) = current.state.query else { return }
                edit(&value)
                current.setQuery(.pixiv(value))
            }
        }
        let author = query.authorID?.isEmpty == false
        let chronological = author || !query.searchWord.isEmpty
        if item == .sort {
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
        var rows: [ToolbarMenuPopoverPresenter.Row] = [.header("作品类型")]
        rows += [(PixivWorkType.illustrations, "插画"), (.manga, "漫画")].map { type, title in
            row(title, selected: query.workType == type) { $0.workType = type }
        }
        rows += [.separator(), .header("AI 作品")]
        rows += [(PixivAIFilter.include, "包含 AI 作品"), (.hide, "隐藏 AI 及未标注作品")].map { ai, title in
            row(title, selected: query.ai == ai) { $0.ai = ai }
        }
        rows += [.separator(), .header("内容范围")]
        if chronological {
            rows += [(PixivContentFilter.safe, "仅安全内容"), (.accountAllowed, "账号允许的内容")].map { content, title in
                row(title, selected: query.content == content) {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.content = content }
                }
            }
        } else {
            rows.append(.init(title: "排行内容由站点权限决定", kind: .info))
        }
        if author {
            rows += [.separator(), .init(title: "筛选当前批次，其他作品可继续加载", kind: .info)]
        } else if !chronological {
            rows += [.separator(), .init(title: "隐藏作品后仍可继续加载下一页", kind: .info)]
        }
        return rows
    }

    private func label(_ item: Item) -> String {
        switch item { case .back: "返回"; case .account: "账号"; case .refresh: "刷新"; case .sort: "排序"; case .filter: "筛选"; case .search: "搜索" }
    }
    private func symbol(_ item: Item) -> String {
        switch item { case .back: "chevron.backward"; case .account: "person.crop.circle"; case .refresh: "arrow.clockwise"; case .sort: "line.3.horizontal"; case .filter: "line.3.horizontal.decrease.circle"; case .search: "magnifyingglass" }
    }
}
