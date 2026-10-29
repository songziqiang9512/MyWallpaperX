import AppKit

// Browser requests and product composition are recording leaves. Query values,
// toolbar callbacks, native menus, filter popover and presentation permission are real.
@MainActor final class OnlineImageBrowserSession {
    enum Query: Hashable {
        case wallhaven(WallhavenQuery), pixiv(PixivQuery)
        var search: String {
            switch self { case .wallhaven(let value): value.search; case .pixiv(let value): value.search }
        }
    }
    struct State {
        var query: Query
        var refreshToken = UUID()
        var isLoading = false
    }
    let source: OnlineImageSource
    var state: State
    var edits: [Query] = []
    var refreshes = 0
    init(source: OnlineImageSource) {
        self.source = source
        state = .init(query: source == .wallhaven ? .wallhaven(.init()) : .pixiv(.init()))
    }
    func setQuery(_ value: Query) {
        guard value != state.query else { return }
        state.query = value; state.refreshToken = UUID(); edits.append(value)
    }
    func setSearch(_ text: String) {
        switch state.query {
        case .wallhaven(var value): value.search = text; value.authorUsername = nil; setQuery(.wallhaven(value))
        case .pixiv(var value): value.search = text; value.authorID = nil; setQuery(.pixiv(value))
        }
    }
    func refresh() { refreshes += 1; state.refreshToken = UUID() }
}

@MainActor final class WallpaperLibraryWorkspace {
    struct Presentation { var page: WallpaperLibraryPage = .wallhaven }
    var presentation = Presentation()
}

@MainActor final class WallpaperLibraryOnlineImages {
    let wallhaven = OnlineImageBrowserSession(source: .wallhaven)
    let pixiv = OnlineImageBrowserSession(source: .pixiv)
    var returns = 0, accounts = 0, logouts = 0
    var returnContext = false
    var pixivAccountStatus = "未登录（匿名浏览）"
    var wallhavenAccountStatus = ["未配置 API Key · 可匿名浏览"]
    var hasPixivIdentity = false, canLogoutPixiv = false, accountRefreshAllowed = true
    var accountRefreshes = 0, myWorks = 0, profiles = 0
    func accountStatus(for source: OnlineImageSource) -> [String] { source == .wallhaven ? wallhavenAccountStatus : [pixivAccountStatus] }
    func canRefreshAccount(_ source: OnlineImageSource) -> Bool { accountRefreshAllowed }
    func refreshAccountInformation(_ source: OnlineImageSource) { accountRefreshes += 1 }
    func openMyPixivWorks() { myWorks += 1 }
    func openPixivProfile() { profiles += 1 }
    func session(for page: WallpaperLibraryPage) -> OnlineImageBrowserSession? {
        switch page { case .wallhaven: wallhaven; case .pixiv: pixiv; default: nil }
    }
    func hasReturnContext(for page: WallpaperLibraryPage) -> Bool { returnContext }
    func goBack() { returns += 1 }
    func presentAccount(settings: Bool = false) { accounts += 1 }
    func logout() { logouts += 1 }
}



private enum ToolbarFixtureError: Error { case missing(String) }

@MainActor private func diagnostic(_ text: String) {
    FileHandle.standardError.write(Data(("Online toolbar: " + text + "\n").utf8))
}

@MainActor private final class ImageToolbarFixtureDelegate: NSObject, NSToolbarDelegate {
    let items: [NSToolbarItem.Identifier: NSToolbarItem]
    init(items: [NSToolbarItem.Identifier: NSToolbarItem]) { self.items = items; super.init() }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        OnlineImageToolbarController.Item.allCases.map(\.id)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // This fixture inserts its existing item instances explicitly below.
        []
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { items[id] }
}

/// One AppKit lifecycle event, observed before the single native action.
@MainActor private final class PopoverReceipt {
    private var observer: NSObjectProtocol?
    private var deadline: Task<Void, Never>?
    private var completion: CheckedContinuation<NSPopover?, Never>?
    func receive(_ name: Notification.Name, perform action: () -> Void) async -> NSPopover? {
        await withCheckedContinuation { continuation in
            completion = continuation
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if let popover = note.object as? NSPopover { self?.finish(popover) }
                }
            }
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                FileHandle.standardError.write(Data("Online toolbar popover deadline: \(name.rawValue)\n".utf8))
                self?.finish(nil)
            }
            action()
        }
    }
    private func finish(_ value: NSPopover?) {
        guard let completion else { return }
        self.completion = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; deadline?.cancel(); deadline = nil
        completion.resume(returning: value)
    }
}

@main enum OnlineImageToolbarHarness {
    @MainActor static func main() {
        diagnostic("main entered")
        initializeNativeAppHarness()
        diagnostic("native App initialized")
        let app = NSApplication.shared
        Task { @MainActor in
            diagnostic("run task entered")
            let facts: [String: Any]
            do { facts = try await run() }
            catch { facts = ["checks": ["fixture_completed": false], "error": String(describing: error)] }
            diagnostic("run task completed; emitting facts")
            let data = try! JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        diagnostic("application run loop entered")
        app.run()
    }

    @MainActor static func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants($0, type) }
    }

    @MainActor static func menuItem(_ title: String, in menu: NSMenu, after header: String? = nil) throws -> NSMenuItem {
        var eligible = header == nil
        for item in menu.items {
            if let header, item.title == header { eligible = true; continue }
            if eligible, item.title == title { return item }
        }
        throw ToolbarFixtureError.missing("menu item \(header ?? "") / \(title)")
    }

    @MainActor static func invoke(_ item: NSMenuItem) throws {
        guard let action = item.action else { throw ToolbarFixtureError.missing("action for \(item.title)") }
        guard NSApp.sendAction(action, to: item.target, from: item) else {
            throw ToolbarFixtureError.missing("target for \(item.title)")
        }
    }

    @MainActor static func run() async throws -> [String: Any] {
        diagnostic("window setup begin")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.center()
        let root = NSView(frame: .init(x: 0, y: 0, width: 1000, height: 620))
        window.contentView = root
        let images = WallpaperLibraryOnlineImages(), workspace = WallpaperLibraryWorkspace()
        diagnostic("controller initialization begin")
        let controller = OnlineImageToolbarController(images: images, workspace: workspace, window: window)
        diagnostic("controller initialized; creating native items")
        var items: [OnlineImageToolbarController.Item: NSToolbarItem] = [:]
        var accountGeometry = false
        for (index, kind) in OnlineImageToolbarController.Item.allCases.enumerated() {
            diagnostic("creating item \(kind.rawValue)")
            guard let item = controller.makeItem(for: kind.id) else { throw ToolbarFixtureError.missing(kind.rawValue) }
            items[kind] = item
            if let view = item.view {
                if kind == .account, let button = view as? NSButton {
                    accountGeometry = button.frame.size == NSSize(width: 32, height: 32)
                        && button.controlSize == .regular && button.imagePosition == .imageOnly && button.alignment == .center
                        && button.imageScaling == .scaleProportionallyDown && button.symbolConfiguration == nil
                        && button.bezelStyle == .push && button.borderShape == .capsule && button.isBordered
                }
                view.frame = .init(x: 24 + CGFloat(index) * 74, y: 566,
                    width: kind == .account ? 32 : 68, height: kind == .account ? 32 : 30)
                root.addSubview(view)
            }
        }
        guard let search = (items[.search] as? NSSearchToolbarItem)?.searchField,
              let filterButton = items[.filter]?.view as? NSButton,
              let sortButton = items[.sort]?.view as? NSButton else { throw ToolbarFixtureError.missing("toolbar controls") }
        if search.superview == nil { search.frame = .init(x: 650, y: 566, width: 220, height: 30); root.addSubview(search) }
        let standaloneAccountBounds = items[.account]?.view?.bounds.size
        let toolbar = NSToolbar(identifier: .init("online-image-filter-fixture"))
        let toolbarDelegate = ImageToolbarFixtureDelegate(items: Dictionary(uniqueKeysWithValues: items.values.map { ($0.itemIdentifier, $0) }))
        toolbar.delegate = toolbarDelegate; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = false
        diagnostic("toolbar assignment begin")
        window.toolbar = toolbar
        diagnostic("toolbar assigned: initial item count=\(toolbar.items.count)")
        for (index, kind) in OnlineImageToolbarController.Item.allCases.enumerated() {
            diagnostic("inserting item \(kind.rawValue) at \(index)")
            toolbar.insertItem(withItemIdentifier: kind.id, at: index)
        }
        diagnostic("toolbar mounted: \(toolbar.items.map(\.itemIdentifier.rawValue))")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        diagnostic("window shown and activation requested")
        defer { window.close(); withExtendedLifetime(toolbarDelegate) {} }
        var checks: [String: Bool] = [:]
        checks["all-image-sources-have-generic-download-entry-without-refresh"] = [WallpaperLibraryPage.wallhaven, .pixiv].allSatisfy { page in
            workspace.presentation.page = page
            return controller.identifiers.contains(.init("downloadTasks")) && !controller.identifiers.contains(.init("OnlineImageRefresh"))
        }
        checks["image-source-accounts-share-regular-native-symbol-hitbox-without-changing-their-capsule"] = accountGeometry
            && standaloneAccountBounds == NSSize(width: 32, height: 32)
        workspace.presentation.page = .wallhaven
        images.returnContext = true; controller.refresh()
        checks["author-return-is-first-independent-capsule-with-icon-and-title"] = controller.identifiers.first == OnlineImageToolbarController.Item.back.id
            && (items[.back]?.view as? NSButton)?.title == "返回" && (items[.back]?.view as? NSButton)?.imagePosition == .imageLeading
        images.returnContext = false; controller.refresh()

        var details: [String: String] = [:]
        func menu(_ kind: OnlineImageToolbarController.Item) throws -> NSMenu {
            controller.refresh()
            if kind == .filter {
                guard let panel = controller.makeFilterPanel() else { throw ToolbarFixtureError.missing("source filter panel") }
                return nativeFilterMenuSnapshot(panel)
            }
            guard let menu = items[kind]?.menuFormRepresentation?.submenu else {
                throw ToolbarFixtureError.missing("overflow menu \(kind.rawValue)")
            }
            return menu
        }
        func wallhaven() throws -> WallhavenQuery {
            guard case .wallhaven(let value) = images.wallhaven.state.query else { throw ToolbarFixtureError.missing("Wallhaven query") }
            return value
        }
        func pixiv() throws -> PixivQuery {
            guard case .pixiv(let value) = images.pixiv.state.query else { throw ToolbarFixtureError.missing("Pixiv query") }
            return value
        }
        func settle() async { root.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(60)); root.layoutSubtreeIfNeeded() }
        func systemMenu(_ button: NSButton) throws -> (menu: NSMenu, ended: Bool, popovers: Int) {
            var opened: NSMenu?, ended = false, popovers = 0
            var cancellation: Timer?
            let center = NotificationCenter.default
            let observers = [
                center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
                    MainActor.assumeIsolated {
                        guard opened == nil, let native = note.object as? NSMenu else { return }
                        opened = native
                        diagnostic("system menu began: \(native.items.map(\.title))")
                        // The toolbar button can itself enter event tracking;
                        // arm cancellation only after its menu has begun.
                        let timer = Timer(timeInterval: 0.03, repeats: false) { _ in
                            MainActor.assumeIsolated {
                                diagnostic("system menu cancellation")
                                native.cancelTracking()
                            }
                        }
                        cancellation = timer
                        RunLoop.main.add(timer, forMode: .eventTracking)
                    }
                },
                center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { note in
                    MainActor.assumeIsolated {
                        if let menu = note.object as? NSMenu, menu === opened { ended = true; diagnostic("system menu ended") }
                    }
                },
                center.addObserver(forName: NSPopover.didShowNotification, object: nil, queue: nil) { _ in
                    MainActor.assumeIsolated { popovers += 1 }
                }
            ]
            defer { cancellation?.invalidate(); observers.forEach { center.removeObserver($0) } }
            diagnostic("system menu click: \(button.toolTip ?? button.title)")
            button.performClick(nil)
            diagnostic("system menu click returned: ended=\(ended), captured=\(opened != nil)")
            guard let opened else { throw ToolbarFixtureError.missing("system menu tracking for \(button.toolTip ?? button.title)") }
            return (opened, ended, popovers)
        }

        // Keep the actual native command opened before the real debounce fires.
        diagnostic("query debounce cases begin")
        let staleSort = try menuItem("浏览量", in: menu(.sort))
        search.stringValue = "new debounced search"
        controller.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: search))
        try await Task.sleep(for: .milliseconds(650))
        let debounced = try wallhaven()
        checks["real_search_debounce_updates_the_current_query"] = debounced.search == "new debounced search"
        try invoke(staleSort)
        let afterSearch = try wallhaven()
        checks["old_overflow_command_preserves_search_completed_after_menu_opened"] = afterSearch.search == "new debounced search"
            && afterSearch.sorting == .views

        // Invoke the retained filter in the same turn as typing, before the
        // 400ms debounce can publish. The real command must consume that text.
        let immediateFilter = try menuItem("16:10", in: menu(.filter))
        search.stringValue = "typed immediately before filter"
        controller.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: search))
        let beforeImmediateFilter = images.wallhaven.edits.count
        try invoke(immediateFilter)
        let immediatelyFiltered = try wallhaven()
        let editsAfterImmediateFilter = images.wallhaven.edits.count
        checks["typing_then_immediate_filter_keeps_pending_search_and_applies_filter"] = immediatelyFiltered.search == "typed immediately before filter"
            && immediatelyFiltered.ratios == ["16x10"] && immediatelyFiltered.sorting == .views
            && editsAfterImmediateFilter == beforeImmediateFilter + 1
        try await Task.sleep(for: .milliseconds(650))
        let afterCancelledDebounce = try wallhaven()
        checks["immediate_filter_cancels_the_old_debounce_without_late_query_changes"] = afterCancelledDebounce == immediatelyFiltered
            && images.wallhaven.edits.count == editsAfterImmediateFilter

        diagnostic("query filter and ordering cases begin")
        var author = WallhavenQuery(); author.authorUsername = "CaseSensitive_User"; author.categories = "101"
        images.wallhaven.setQuery(.wallhaven(author))
        try invoke(menuItem("4K 及以上", in: menu(.filter), after: "最低分辨率"))
        let minimum = try wallhaven()
        try invoke(menuItem("1080p 及以上", in: menu(.filter), after: "最低分辨率"))
        let minimumAgain = try wallhaven()
        let reducedFilters = try menu(.filter)
        checks["minimum_resolution_is_one_native_choice_without_duplicate_exact_or_color_controls"] = minimum.minimumResolution == "3840x2160"
            && minimumAgain.minimumResolution == "1920x1080"
            && !reducedFilters.items.contains { $0.title == "精确分辨率" || $0.title == "颜色" || $0.title.hasPrefix("#") }
        try invoke(menuItem("9:16", in: menu(.filter)))
        try invoke(menuItem("16:9", in: menu(.filter)))
        try invoke(menuItem("敏感", in: menu(.filter)))
        try invoke(menuItem("安全", in: menu(.filter)))
        try invoke(menuItem("收藏量", in: menu(.sort)))
        try invoke(menuItem("升序", in: menu(.sort)))
        let filteredAuthor = try wallhaven()
        checks["wallhaven_author_and_existing_filters_survive_independent_edits"] = filteredAuthor.authorUsername == "CaseSensitive_User"
            && filteredAuthor.search.isEmpty && filteredAuthor.categories == "101" && Set(filteredAuthor.ratios) == ["9x16", "16x9"]
            && filteredAuthor.purity == "010" && filteredAuthor.sorting == .favorites
            && filteredAuthor.order == .asc && filteredAuthor.minimumResolution == "1920x1080"
        // A held category checkbox toggles the current mask rather than its old snapshot.
        let category = try menuItem("动漫", in: menu(.filter))
        var changedMask = try wallhaven(); changedMask.categories = "110"; images.wallhaven.setQuery(.wallhaven(changedMask))
        try invoke(category)
        let afterCategory = try wallhaven()
        checks["held_category_checkbox_reads_the_current_mask"] = afterCategory.categories == "100"
        try invoke(menuItem("清空筛选", in: menu(.filter)))
        let clearedAuthor = try wallhaven()
        checks["clear_native_filters_preserves_author_search_and_sort_context"] = clearedAuthor.authorUsername == "CaseSensitive_User"
            && clearedAuthor.categories == "111" && clearedAuthor.purity == "100" && clearedAuthor.minimumResolution == nil
            && clearedAuthor.ratios.isEmpty && clearedAuthor.sorting == .favorites && clearedAuthor.order == .asc

        var popular = try wallhaven(); popular.sorting = .popular; images.wallhaven.setQuery(.wallhaven(popular))
        let topMenu = try menu(.sort)
        checks["all_toplist_ranges_have_active_native_commands"] = WallhavenQuery.TopRange.allCases.allSatisfy { range in
            topMenu.items.contains { $0.title == range.displayName && $0.isEnabled }
        }
        let staleRange = try menuItem("六个月内", in: topMenu)
        let staleDirection = try menuItem("降序", in: topMenu)
        var random = try wallhaven(); random.sorting = .random; images.wallhaven.setQuery(.wallhaven(random))
        let beforeStale = try wallhaven()
        try invoke(staleRange); try invoke(staleDirection)
        let afterStale = try wallhaven()
        let randomMenu = try menu(.sort)
        checks["random_hides_inactive_order_and_toprange_and_rejects_held_mode_commands"] = afterStale == beforeStale
            && !randomMenu.items.contains { $0.title == "升序" || $0.title == "降序" || $0.title == "热门范围" }

        // Native permission is real: a held command cannot mutate under a sheet.
        diagnostic("modal permission case begin")
        var normal = try wallhaven(); normal.sorting = .views; images.wallhaven.setQuery(.wallhaven(normal))
        let held = try menuItem("降序", in: menu(.sort))
        let panel = WallpaperLibraryModalPanel(contentRect: .init(x: 0, y: 0, width: 250, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let admitted = WallpaperLibrarySheetPresentation.present(panel, in: window)
        let beforeModal = try wallhaven(); try invoke(held)
        let afterModal = try wallhaven()
        checks["held_native_command_obeys_actual_modal_permission"] = admitted && panel.isSheet
            && panel.sheetParent === window && window.attachedSheet === panel && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && afterModal == beforeModal
        panel.close(); window.makeKeyAndOrderFront(nil)

        diagnostic("account projection cases begin")
        workspace.presentation.page = .pixiv
        let beforeAccountEdits = images.pixiv.edits.count, beforeAccountRefreshes = images.pixiv.refreshes
        let anonymousAccount = try menu(.account)
        images.pixivAccountStatus = "已登录：fixture（12345）"; images.hasPixivIdentity = true; images.canLogoutPixiv = true
        let verifiedAccount = try menu(.account)
        images.pixivAccountStatus = "会话状态待确认"
        let unknownAccount = try menu(.account)
        checks["account_menu_projects_current_status_without_a_browse_query_or_refresh"] = anonymousAccount.items.contains { $0.title == "未登录（匿名浏览）" && !$0.isEnabled }
            && verifiedAccount.items.contains { $0.title == "已登录：fixture（12345）" && !$0.isEnabled }
            && unknownAccount.items.contains { $0.title == "会话状态待确认" && !$0.isEnabled }
            && images.pixiv.edits.count == beforeAccountEdits && images.pixiv.refreshes == beforeAccountRefreshes
        checks["account-actions-appear-only-after-trusted-identity"] = !anonymousAccount.items.contains { $0.title == "我的作品" }
            && verifiedAccount.items.contains { $0.title == "我的作品" && $0.isEnabled }
            && verifiedAccount.items.contains { $0.title == "个人主页（网页）" && $0.isEnabled }
            && verifiedAccount.items.contains { $0.title == "切换账号…" && $0.isEnabled }
        try invoke(menuItem("我的作品", in: verifiedAccount)); try invoke(menuItem("个人主页（网页）", in: verifiedAccount))
        try invoke(menuItem("刷新账号信息", in: verifiedAccount))
        checks["account-menu-actions-reuse-native-routing-without-refreshing-the-grid"] = images.myWorks == 1 && images.profiles == 1
            && images.accountRefreshes == 1 && images.pixiv.edits.count == beforeAccountEdits && images.pixiv.refreshes == beforeAccountRefreshes
        images.accountRefreshAllowed = false
        images.pixivAccountStatus = "正在读取账号信息…"
        checks["pending-account-read-disables-duplicate-refresh-command"] = try menuItem("刷新账号信息", in: menu(.account)).isEnabled == false
        images.accountRefreshAllowed = true
        images.pixivAccountStatus = "会话状态待确认"
        checks["completed-account-read-restores-refresh-command"] = try menuItem("刷新账号信息", in: menu(.account)).isEnabled
        workspace.presentation.page = .wallhaven
        images.wallhavenAccountStatus = ["已保存 API Key", "已取得 1 个收藏集", "Landscapes · 12 张"]
        let wallhavenAccount = try menu(.account)
        checks["wallhaven-account-menu-distinguishes-stored-key-and-real-collection-data"] = wallhavenAccount.items.contains { $0.title == "已保存 API Key" && !$0.isEnabled }
            && wallhavenAccount.items.contains { $0.title == "Landscapes · 12 张" && !$0.isEnabled }
            && !wallhavenAccount.items.contains { $0.title == "我的作品" || $0.title.contains("已登录") }
        diagnostic("held source and inactive-query cases begin")
        workspace.presentation.page = .pixiv
        let beforePage = images.wallhaven.state.query
        try invoke(held)
        checks["held_source_command_cannot_change_a_different_page"] = images.wallhaven.state.query == beforePage
        let ranking = try menu(.sort), rankFilters = try menu(.filter)
        let oldRank = try menuItem("每周排行", in: ranking)
        checks["ranking_shows_rank_type_ai_and_no_inactive_order_or_content_switch"] = ranking.items.contains { $0.title == "每月排行" && $0.isEnabled }
            && !ranking.items.contains { $0.title == "最早优先" }
            && rankFilters.items.contains { $0.title == "隐藏 AI 与未标注" && $0.isEnabled }
            && !rankFilters.items.contains { $0.title == "仅安全内容" || $0.title == "账号允许的内容" }
        var searched = PixivQuery(); searched.search = "landscape"; images.pixiv.setQuery(.pixiv(searched))
        let oldOrder = try menuItem("最早优先", in: menu(.sort))
        let oldContent = try menuItem("账号允许的内容", in: menu(.filter))
        try invoke(oldRank)
        let ignoredRank = try pixiv()
        checks["ranking_command_opened_before_search_does_not_write_an_inactive_field"] = ignoredRank.ranking == .daily
            && ignoredRank.search == "landscape"
        images.pixiv.setQuery(.pixiv(.init()))
        try invoke(oldOrder); try invoke(oldContent)
        let ignoredSearch = try pixiv()
        checks["search_commands_do_not_write_inactive_fields_after_return_to_ranking"] = ignoredSearch.order == .newest
            && ignoredSearch.content == .safe && ignoredSearch.search.isEmpty
        var pixivAuthor = PixivQuery(); pixivAuthor.authorID = "123456"; images.pixiv.setQuery(.pixiv(pixivAuthor))
        try invoke(menuItem("最早优先", in: menu(.sort)))
        try invoke(menuItem("漫画", in: menu(.filter)))
        try invoke(menuItem("隐藏 AI 与未标注", in: menu(.filter)))
        try invoke(menuItem("账号允许的内容", in: menu(.filter)))
        let authorFilters = try pixiv(), authorMenu = try menu(.filter)
        checks["pixiv_author_filters_edit_real_fields_and_keep_author_scope"] = authorFilters.authorID == "123456"
            && authorFilters.workType == .manga && authorFilters.ai == .hide && authorFilters.content == .accountAllowed
            && authorFilters.order == .oldest && authorFilters.search.isEmpty
            && authorMenu.items.contains { $0.title == "内容范围" }

        // Native source filter: one shared grid, source-owned state, live edits.
        workspace.presentation.page = .wallhaven
        images.wallhaven.setQuery(.wallhaven(.init())); controller.refresh()
        diagnostic("filter button show: toolbar=\(items[.filter]?.toolbar === toolbar), mounted=\(filterButton.window === window)")
        let nativeShown = await PopoverReceipt().receive(NSPopover.didShowNotification) { filterButton.performClick(nil) }
        diagnostic("filter button show returned: captured=\(nativeShown != nil)")
        guard let nativePopover = nativeShown, let nativeContent = nativePopover.contentViewController?.view,
              let nativeRatio = descendants(nativeContent, NSButton.self).first(where: { $0.title == "16:9" }),
              let nativeClear = descendants(nativeContent, NSButton.self).first(where: { $0.title == "清空筛选" }) else {
            throw ToolbarFixtureError.missing("native grouped source filter")
        }
        await settle()
        let nativeGroups = descendants(nativeContent, NSGridView.self)
        let edges = nativeGroups.map { $0.convert($0.bounds, to: nativeContent).minX }
        checks["native_filter_has_four_equal_edge_checkbox_groups_at_400_points"] = nativePopover.contentSize.width == 400
            && nativeGroups.map(\.numberOfColumns) == [3, 3, 2, 4]
            && (edges.max()! - edges.min()!) <= 1 && descendants(nativeContent, NSScrollView.self).isEmpty
        let originalButtons = descendants(nativeContent, NSButton.self).map(ObjectIdentifier.init)
        nativeRatio.performClick(nil); await settle(); controller.refresh()
        let nativeFiltered = try wallhaven()
        checks["native_filter_checkbox_immediately_updates_query_without_closing_or_rebuilding_controls"] = nativePopover.isShown
            && nativeRatio.state == .on && nativeFiltered.ratios == ["16x9"] && nativeClear.isEnabled
            && descendants(nativeContent, NSButton.self).map(ObjectIdentifier.init) == originalButtons
        nativeClear.performClick(nil); await settle()
        let nativeCleared = try wallhaven()
        checks["native_filter_clear_restores_query_and_checkbox_state_in_the_same_panel"] = nativePopover.isShown
            && !nativeClear.isEnabled && nativeRatio.state == .off && nativeCleared.ratios.isEmpty
        let gridScroll = NSScrollView(frame: .init(x: 0, y: 0, width: 400, height: 400))
        let grid = NSCollectionView(frame: .init(x: 0, y: 0, width: 400, height: 800))
        gridScroll.documentView = grid; root.addSubview(gridScroll)
        let dismissal = ToolbarPopoverScrollDismissal(popover: nativePopover)
        dismissal.watch(relativeTo: filterButton)
        gridScroll.contentView.scroll(to: .init(x: 0, y: 100)); gridScroll.reflectScrolledClipView(gridScroll.contentView)
        dismissal.dismissIfGridScroll(in: nativeContent.window, target: nativeContent)
        checks["native_filter_keeps_open_for_programmatic_grid_position_and_panel_content"] = nativePopover.isShown
        diagnostic("filter grid-target close")
        let filterClosed = await PopoverReceipt().receive(NSPopover.didCloseNotification) {
            dismissal.dismissIfGridScroll(in: window, target: grid)
        }
        checks["grid_scroll_target_closes_the_same_native_filter_popover"] = filterClosed === nativePopover && !nativePopover.isShown

        let filterItem = items[.filter]!, overflowFilter = filterItem.menuFormRepresentation!
        window.setContentSize(.init(width: 160, height: 620)); await settle()
        diagnostic("filter overflow show: detached=\(filterButton.window == nil), visible=\(toolbar.visibleItems?.contains(where: { $0 === filterItem }) == true), toolbar=\(filterItem.toolbar === toolbar), frame=\(window.frame)")
        checks["filter_overflow_is_one_action_for_the_real_detached_toolbar_item"] = overflowFilter.submenu == nil
            && overflowFilter.action != nil && filterItem.toolbar === toolbar && filterButton.window == nil
            && toolbar.visibleItems?.contains(where: { $0 === filterItem }) == false
        let overflowShown = await PopoverReceipt().receive(NSPopover.didShowNotification) {
            NSApp.sendAction(overflowFilter.action!, to: overflowFilter.target, from: overflowFilter)
        }
        diagnostic("filter overflow show returned: captured=\(overflowShown != nil)")
        guard let overflowPopup = overflowShown, let overflowContent = overflowPopup.contentViewController?.view,
              let overflowRatio = descendants(overflowContent, NSButton.self).first(where: { $0.title == "16:9" }) else {
            throw ToolbarFixtureError.missing("native filter from a detached toolbar overflow action")
        }
        overflowRatio.performClick(nil)
        let overflowQuery = try wallhaven()
        checks["detached_filter_overflow_opens_the_same_native_multiselect_panel_and_keeps_it_open"] = overflowPopup === nativePopover
            && overflowPopup.isShown && overflowPopup.behavior == .transient && overflowPopup.contentSize.width == 400
            && overflowRatio.state == .on && overflowQuery.ratios == ["16x9"]
        let beforeLeavingWallhaven = images.wallhaven.state.query, beforeLeavingPixiv = images.pixiv.state.query
        diagnostic("filter source-change close")
        let closedOnSourceChange = await PopoverReceipt().receive(NSPopover.didCloseNotification) {
            workspace.presentation.page = .pixiv; controller.refresh()
        }
        overflowRatio.performClick(nil)
        try invoke(overflowFilter)
        checks["source_change_closes_filter_and_revokes_held_checkbox_and_overflow_actions"] = closedOnSourceChange === overflowPopup
            && !overflowPopup.isShown && images.wallhaven.state.query == beforeLeavingWallhaven && images.pixiv.state.query == beforeLeavingPixiv
        window.setContentSize(.init(width: 1000, height: 620)); await settle()
        diagnostic("filter source-change and width restoration completed")

        var calls = 0
        let semanticMenu = ToolbarMenu.makeMenu(rows: [
            .header("分组"), .init(title: "当前选择", kind: .action, isChecked: true, handler: { calls += 1 }),
            .separator(), .init(title: "禁用动作", kind: .action, isEnabled: false, handler: { calls += 1 }),
            .init(title: "账号状态", kind: .info)
        ])
        let selected = try menuItem("当前选择", in: semanticMenu)
        let disabled = try menuItem("禁用动作", in: semanticMenu)
        let info = try menuItem("账号状态", in: semanticMenu)
        checks["ordinary_menu_rows_use_system_group_checkmark_separator_and_disabled_items"] = !semanticMenu.autoenablesItems
            && semanticMenu.items[0].title == "分组" && semanticMenu.items[0].action == nil
            && selected.state == .on && selected.isEnabled && semanticMenu.items[2].isSeparatorItem
            && !disabled.isEnabled && !info.isEnabled && info.action == nil && info.target == nil
            && semanticMenu.items.allSatisfy { $0.view == nil }
        try invoke(disabled)
        checks["disabled_system_menu_command_cannot_dispatch_even_through_a_held_action"] = calls == 0
        try invoke(selected)
        checks["checked_system_menu_action_dispatches_once_without_a_second_selection_owner"] = calls == 1 && selected.state == .on

        workspace.presentation.page = .wallhaven
        images.wallhaven.setQuery(.wallhaven(.init())); controller.refresh()
        let directSort = try systemMenu(sortButton)
        let overflowSort = try menu(.sort)
        checks["ordinary_sort_button_tracks_a_system_menu_without_an_arrow_popover"] = directSort.ended && directSort.popovers == 0
            && directSort.menu.items.allSatisfy { $0.view == nil }
            && directSort.menu.items.map(\.title) == overflowSort.items.map(\.title)
            && directSort.menu.items.map(\.state) == overflowSort.items.map(\.state)
            && directSort.menu.items.map(\.isEnabled) == overflowSort.items.map(\.isEnabled)
        details["ordinary_sort_button_tracks_a_system_menu_without_an_arrow_popover"] = "ended=\(directSort.ended), popovers=\(directSort.popovers), titles=\(directSort.menu.items.map(\.title))"
        let beforeSingleSort = images.wallhaven.edits.count
        try invoke(menuItem("浏览量", in: directSort.menu))
        let singleSorted = try wallhaven(), sortedMenu = try menu(.sort)
        let sortingTitles = Set(WallhavenQuery.Sorting.allCases.map(\.displayName))
        checks["system_sort_selection_updates_the_original_query_once_and_has_one_checked_choice"] = singleSorted.sorting == .views
            && images.wallhaven.edits.count == beforeSingleSort + 1
            && sortedMenu.items.filter { sortingTitles.contains($0.title) && $0.state == .on }.map(\.title) == ["浏览量"]

        workspace.presentation.page = .pixiv; images.pixiv.setQuery(.pixiv(.init())); controller.refresh()
        guard let accountButton = items[.account]?.view as? NSButton else { throw ToolbarFixtureError.missing("account button") }
        images.pixivAccountStatus = "正在读取账号信息…"; images.hasPixivIdentity = false; controller.refresh()
        let pendingAccount = try systemMenu(accountButton)
        images.pixivAccountStatus = "已登录：完成用户（12345）"; images.hasPixivIdentity = true; controller.refresh()
        let completedAccount = try systemMenu(accountButton)
        checks["reopening_system_account_menu_projects_the_completed_optional_identity_read"] = pendingAccount.ended && completedAccount.ended
            && pendingAccount.popovers == 0 && completedAccount.popovers == 0
            && pendingAccount.menu.items.contains { $0.title == "正在读取账号信息…" && !$0.isEnabled }
            && !pendingAccount.menu.items.contains { $0.title == "我的作品" }
            && completedAccount.menu.items.contains { $0.title == "已登录：完成用户（12345）" && !$0.isEnabled }
            && completedAccount.menu.items.contains { $0.title == "我的作品" && $0.isEnabled }
            && !completedAccount.menu.items.contains { $0.title == "正在读取账号信息…" }
        let nativeInfo = try menuItem("已登录：完成用户（12345）", in: completedAccount.menu)
        let actionsBeforeInfo = (images.accounts, images.accountRefreshes, images.myWorks)
        completedAccount.menu.performActionForItem(at: completedAccount.menu.items.firstIndex { $0 === nativeInfo }!)
        checks["native-account-info-is-disabled-and-cannot-trigger-a-command"] = !nativeInfo.isEnabled && nativeInfo.action == nil && nativeInfo.target == nil
            && images.accounts == actionsBeforeInfo.0 && images.accountRefreshes == actionsBeforeInfo.1 && images.myWorks == actionsBeforeInfo.2
        return ["checks": checks, "details": details,
                "scope": "Actual toolbar/query/overflow/modal/system menu with recording browser leaves; native filter and public post-hit-test grid-scroll dismissal; native menu tracking is cancelled by the fixture, without a physical selection, wheel, network or full-App claim."]
    }
}
