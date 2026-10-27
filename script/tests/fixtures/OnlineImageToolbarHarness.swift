import AppKit
import CoreGraphics

// Browser requests and product composition are recording leaves. Query values,
// toolbar callbacks, native overflow, presentation permission and popover are real.
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
    var pixivAccountStatus = "未登录（匿名浏览）"
    func session(for page: WallpaperLibraryPage) -> OnlineImageBrowserSession? {
        switch page { case .wallhaven: wallhaven; case .pixiv: pixiv; default: nil }
    }
    func hasReturnContext(for page: WallpaperLibraryPage) -> Bool { false }
    func goBack() { returns += 1 }
    func presentAccount(settings: Bool = false) { accounts += 1 }
    func logout() { logouts += 1 }
}

@MainActor enum WallpaperLibraryControlStyle {
    static func capsule(_ button: NSButton) { button.bezelStyle = .rounded }
}

private enum ToolbarFixtureError: Error { case missing(String) }

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
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            let facts: [String: Any]
            do { facts = try await run() }
            catch { facts = ["checks": ["fixture_completed": false], "error": String(describing: error)] }
            let data = try! JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.center()
        let root = NSView(frame: .init(x: 0, y: 0, width: 1000, height: 620))
        window.contentView = root
        let images = WallpaperLibraryOnlineImages(), workspace = WallpaperLibraryWorkspace()
        let controller = OnlineImageToolbarController(images: images, workspace: workspace, window: window)
        var items: [OnlineImageToolbarController.Item: NSToolbarItem] = [:]
        for (index, kind) in OnlineImageToolbarController.Item.allCases.enumerated() {
            guard let item = controller.makeItem(for: kind.id) else { throw ToolbarFixtureError.missing(kind.rawValue) }
            items[kind] = item
            if let view = item.view {
                view.frame = .init(x: 24 + CGFloat(index) * 74, y: 566, width: 68, height: 30)
                root.addSubview(view)
            }
        }
        guard let search = (items[.search] as? NSSearchToolbarItem)?.searchField,
              let filterButton = items[.filter]?.view as? NSButton,
              let sortButton = items[.sort]?.view as? NSButton else { throw ToolbarFixtureError.missing("toolbar controls") }
        if search.superview == nil { search.frame = .init(x: 650, y: 566, width: 220, height: 30); root.addSubview(search) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        defer { window.close() }
        var checks: [String: Bool] = [:]
        var details: [String: String] = [:]
        func menu(_ kind: OnlineImageToolbarController.Item) throws -> NSMenu {
            controller.refresh()
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

        // Keep the actual native command opened before the real debounce fires.
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
        try invoke(immediateFilter)
        let immediatelyFiltered = try wallhaven()
        let editsAfterImmediateFilter = images.wallhaven.edits.count
        checks["typing_then_immediate_filter_keeps_pending_search_and_applies_filter"] = immediatelyFiltered.search == "typed immediately before filter"
            && immediatelyFiltered.ratios == ["16x10"] && immediatelyFiltered.sorting == .views
        try await Task.sleep(for: .milliseconds(650))
        let afterCancelledDebounce = try wallhaven()
        checks["immediate_filter_cancels_the_old_debounce_without_late_query_changes"] = afterCancelledDebounce == immediatelyFiltered
            && images.wallhaven.edits.count == editsAfterImmediateFilter

        var author = WallhavenQuery(); author.authorUsername = "CaseSensitive_User"; author.categories = "101"
        images.wallhaven.setQuery(.wallhaven(author))
        try invoke(menuItem("3840 × 2160", in: menu(.filter), after: "最低分辨率"))
        let minimum = try wallhaven()
        try invoke(menuItem("2560 × 1440", in: menu(.filter), after: "精确分辨率"))
        let exact = try wallhaven()
        try invoke(menuItem("1920 × 1080", in: menu(.filter), after: "最低分辨率"))
        let minimumAgain = try wallhaven()
        checks["minimum_and_exact_resolution_clear_only_the_other_resolution_mode"] = minimum.minimumResolution == "3840x2160"
            && minimum.resolutions.isEmpty && exact.minimumResolution == nil && exact.resolutions == ["2560x1440"]
            && minimumAgain.minimumResolution == "1920x1080" && minimumAgain.resolutions.isEmpty
        try invoke(menuItem("9:16", in: menu(.filter)))
        try invoke(menuItem("#424153", in: menu(.filter)))
        try invoke(menuItem("仅敏感内容", in: menu(.filter)))
        try invoke(menuItem("收藏量", in: menu(.sort)))
        try invoke(menuItem("升序", in: menu(.sort)))
        let filteredAuthor = try wallhaven()
        checks["wallhaven_author_and_existing_filters_survive_independent_edits"] = filteredAuthor.authorUsername == "CaseSensitive_User"
            && filteredAuthor.search.isEmpty && filteredAuthor.categories == "101" && filteredAuthor.ratios == ["9x16"]
            && filteredAuthor.color == "424153" && filteredAuthor.purity == "010" && filteredAuthor.sorting == .favorites
            && filteredAuthor.order == .asc && filteredAuthor.minimumResolution == "1920x1080"
        let colorMenu = try menu(.filter)
        checks["official_color_palette_is_reachable_through_actual_overflow_rows"] = WallhavenQuery.colorPalette.allSatisfy { color in
            colorMenu.items.contains { item in item.title == "#" + color.uppercased() && item.isEnabled }
        }
        // A held category checkbox toggles the current mask rather than its old snapshot.
        let category = try menuItem("动漫", in: menu(.filter))
        var changedMask = try wallhaven(); changedMask.categories = "110"; images.wallhaven.setQuery(.wallhaven(changedMask))
        try invoke(category)
        let afterCategory = try wallhaven()
        checks["held_category_checkbox_reads_the_current_mask"] = afterCategory.categories == "100"

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

        // Native permission is real: a held command cannot mutate under a modal child.
        var normal = try wallhaven(); normal.sorting = .views; images.wallhaven.setQuery(.wallhaven(normal))
        let held = try menuItem("降序", in: menu(.sort))
        let panel = WallpaperLibraryModalPanel(contentRect: .init(x: 0, y: 0, width: 250, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let admitted = WallpaperLibrarySheetPresentation.present(panel, in: window)
        let beforeModal = try wallhaven(); try invoke(held)
        let afterModal = try wallhaven()
        checks["held_native_command_obeys_actual_modal_permission"] = admitted && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && afterModal == beforeModal
        panel.close(); window.makeKeyAndOrderFront(nil)

        workspace.presentation.page = .pixiv
        let beforeAccountEdits = images.pixiv.edits.count, beforeAccountRefreshes = images.pixiv.refreshes
        let anonymousAccount = try menu(.account)
        images.pixivAccountStatus = "当前账号：fixture（12345）"
        let verifiedAccount = try menu(.account)
        images.pixivAccountStatus = "会话状态待确认"
        let unknownAccount = try menu(.account)
        checks["account_menu_projects_current_status_without_a_browse_query_or_refresh"] = anonymousAccount.items.contains { $0.title == "未登录（匿名浏览）" && !$0.isEnabled }
            && verifiedAccount.items.contains { $0.title == "当前账号：fixture（12345）" && !$0.isEnabled }
            && unknownAccount.items.contains { $0.title == "会话状态待确认" && !$0.isEnabled }
            && images.pixiv.edits.count == beforeAccountEdits && images.pixiv.refreshes == beforeAccountRefreshes
        let beforePage = images.wallhaven.state.query
        try invoke(held)
        checks["held_source_command_cannot_change_a_different_page"] = images.wallhaven.state.query == beforePage
        let ranking = try menu(.sort), rankFilters = try menu(.filter)
        let oldRank = try menuItem("每周排行", in: ranking)
        checks["ranking_shows_rank_type_ai_and_no_inactive_order_or_content_switch"] = ranking.items.contains { $0.title == "每月排行" && $0.isEnabled }
            && !ranking.items.contains { $0.title == "最早优先" }
            && rankFilters.items.contains { $0.title == "隐藏 AI 及未标注作品" && $0.isEnabled }
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
        try invoke(menuItem("隐藏 AI 及未标注作品", in: menu(.filter)))
        try invoke(menuItem("账号允许的内容", in: menu(.filter)))
        let authorFilters = try pixiv(), authorMenu = try menu(.filter)
        checks["pixiv_author_filters_edit_real_fields_and_keep_author_scope"] = authorFilters.authorID == "123456"
            && authorFilters.workType == .manga && authorFilters.ai == .hide && authorFilters.content == .accountAllowed
            && authorFilters.order == .oldest && authorFilters.search.isEmpty
            && authorMenu.items.contains { !$0.isEnabled && $0.title == "筛选当前批次，其他作品可继续加载" }

        // Native shared popover: long real filter menu is bounded and scrollable.
        workspace.presentation.page = .wallhaven
        images.wallhaven.setQuery(.wallhaven(.init())); controller.refresh()
        let shown = await PopoverReceipt().receive(NSPopover.didShowNotification) { filterButton.performClick(nil) }
        guard let longPopover = shown, let content = longPopover.contentViewController?.view,
              let scroll = descendants(content, NSScrollView.self).first, let document = scroll.documentView else {
            throw ToolbarFixtureError.missing("native long filter popover didShow / scroll")
        }
        await settle(); content.layoutSubtreeIfNeeded()
        let limit = max(180, min(560, (window.screen?.visibleFrame.height ?? 720) - 160))
        checks["native_long_menu_is_height_bounded_with_a_real_scroll_view"] = longPopover.isShown
            && longPopover.contentSize.height <= limit + 1 && document.frame.height > scroll.contentView.bounds.height
            && scroll.hasVerticalScroller && document.isFlipped
        details["native_long_menu_is_height_bounded_with_a_real_scroll_view"] = "content=\(longPopover.contentSize), document=\(document.frame), clip=\(scroll.contentView.bounds)"
        let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: .init(x: 0, y: bottom)); scroll.reflectScrolledClipView(scroll.contentView)
        content.layoutSubtreeIfNeeded()
        guard let lastColor = descendants(content, NSButton.self).first(where: { $0.title == "#424153" }) else {
            throw ToolbarFixtureError.missing("last native color")
        }
        checks["long_menu_lower_rows_are_reachable_inside_the_native_viewport"] = lastColor.convert(lastColor.bounds, to: document)
            .intersects(document.visibleRect) && scroll.contentView.bounds.minY > 0
        let beforeCheckOffset = scroll.contentView.bounds.minY
        lastColor.performClick(nil)
        await settle()
        guard let updatedScroll = descendants(content, NSScrollView.self).first else { throw ToolbarFixtureError.missing("reloaded scroll") }
        let checkedItem = try menuItem("#424153", in: menu(.filter))
        let selectedNativeColor = try wallhaven()
        checks["checking_a_native_long_menu_row_preserves_scroll_and_updates_checkmark"] = longPopover.isShown
            && abs(updatedScroll.contentView.bounds.minY - beforeCheckOffset) <= 1
            && selectedNativeColor.color == "424153" && checkedItem.state == .on
        details["checking_a_native_long_menu_row_preserves_scroll_and_updates_checkmark"] = "before=\(beforeCheckOffset), after=\(updatedScroll.contentView.bounds.minY)"

        let dismissal = ToolbarPopoverScrollDismissal(popover: longPopover)
        dismissal.watch(relativeTo: filterButton)
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 24, wheel2: 0, wheel3: 0)!
        let beforeWheel = updatedScroll.contentView.bounds.minY
        updatedScroll.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        await settle()
        dismissal.dismissIfGridScroll(in: updatedScroll.window, target: updatedScroll)
        checks["native_menu_scroll_keeps_the_popover_open"] = longPopover.isShown
            && abs(updatedScroll.contentView.bounds.minY - beforeWheel) > 0
        details["native_menu_scroll_keeps_the_popover_open"] = "before=\(beforeWheel), after=\(updatedScroll.contentView.bounds.minY)"
        let gridScroll = NSScrollView(frame: .init(x: 0, y: 0, width: 400, height: 400))
        let grid = NSCollectionView(frame: .init(x: 0, y: 0, width: 400, height: 800))
        gridScroll.documentView = grid; root.addSubview(gridScroll)
        let closed = await PopoverReceipt().receive(NSPopover.didCloseNotification) {
            dismissal.dismissIfGridScroll(in: window, target: grid)
        }
        checks["grid_scroll_target_closes_the_same_shared_popover"] = closed === longPopover && !longPopover.isShown

        workspace.presentation.page = .pixiv; images.pixiv.setQuery(.pixiv(.init())); controller.refresh()
        let shortShown = await PopoverReceipt().receive(NSPopover.didShowNotification) { sortButton.performClick(nil) }
        guard let shortPopover = shortShown, let shortContent = shortPopover.contentViewController?.view,
              let shortScroll = descendants(shortContent, NSScrollView.self).first,
              let shortDocument = shortScroll.documentView else { throw ToolbarFixtureError.missing("native short menu") }
        await settle(); shortContent.layoutSubtreeIfNeeded()
        checks["short_native_menu_keeps_compact_geometry_and_zero_scroll_range"] = shortPopover.contentSize.height < limit
            && abs(shortDocument.frame.height - shortScroll.contentView.bounds.height) <= 1
            && abs(shortScroll.contentView.bounds.minY) <= 1
        details["short_native_menu_keeps_compact_geometry_and_zero_scroll_range"] = "content=\(shortPopover.contentSize), document=\(shortDocument.frame), clip=\(shortScroll.contentView.bounds)"
        let shortClosed = await PopoverReceipt().receive(NSPopover.didCloseNotification) { shortPopover.performClose(nil) }
        checks["native_popover_lifecycle_finishes_without_a_retained_panel"] = shortClosed === shortPopover && !shortPopover.isShown
        return ["checks": checks, "details": details,
                "scope": "Actual toolbar/query/overflow/modal/popup with recording browser leaves; native scrolling and public post-hit-test dismissal entry; no physical wheel, network or full-App claim."]
    }
}
