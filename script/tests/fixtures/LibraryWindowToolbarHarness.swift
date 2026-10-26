import AppKit
import Combine
import Foundation

// Recording commands/source controls exercise the full production toolbar.
// Page identity, query, selection reconciliation and relationship state use
// the actual Presentation, Query, Controller and SQLite store.
enum ManualNavigationDirection { case previous, next }
enum WallpaperPlaybackSequence { enum NavigationPolicy { case adjacent, randomHistory } }
enum PlaylistOrganizationAction { case create, rename(UUID), duplicate(UUID), delete(UUID) }
extension Notification.Name { static let steamWorkshopBrowseContextDidChange = Notification.Name("toolbar-fixture-browse-context") }
extension NSToolbarItem.Identifier {
    static let steamAccount = Self("fixture-steam-account")
    static let steamDownloadTasks = Self("fixture-steam-tasks")
}
@MainActor final class WallpaperLibraryWorkspace {
    let collections: UserCollectionsController
    let presentation: WallpaperLibraryPresentation
    var catalog: WallpaperLibraryCatalog
    var relationships: UserCollectionsSnapshot { collections.snapshot }
    var sourceRefreshes = 0
    func refreshSources() { sourceRefreshes += 1 }
    init(collections: UserCollectionsController, defaults: UserDefaults, catalog: WallpaperLibraryCatalog) {
        self.collections = collections; self.catalog = catalog
        presentation = WallpaperLibraryPresentation(collections: collections, defaults: defaults)
        refresh()
    }
    func refresh() { _ = presentation.update(catalog: catalog, relationships: relationships) }
}
@MainActor final class ToolbarManager {
    var manual: [ManualNavigationDirection] = []
    var adjacent: [ManualNavigationDirection] = []
    func navigateWallpaperManually(_ direction: ManualNavigationDirection) { manual.append(direction) }
    func navigateLibraryPlayback(_ direction: ManualNavigationDirection, policy: WallpaperPlaybackSequence.NavigationPolicy) {
        if policy == .adjacent { adjacent.append(direction) }
    }
}
@MainActor final class ToolbarPlaylists {
    var actions: [PlaylistOrganizationAction] = []
    func handle(_ action: PlaylistOrganizationAction) { actions.append(action) }
}
@MainActor final class WallpaperLibraryCommands {
    let workspace: WallpaperLibraryWorkspace
    let manager = ToolbarManager()
    let playlists: ToolbarPlaylists? = ToolbarPlaylists()
    var onFocusSearch: (() -> Void)?
    var onAddWallpapers: ((UUID) -> Void)?
    var imports = 0, removals = 0, favorites = 0, plays = 0, randoms = 0, playlistChoices = 0, recentClears = 0
    let availabilityInvalidations = PassthroughSubject<Void, Never>()
    var availabilityChanges: AnyPublisher<Void, Never> { availabilityInvalidations.eraseToAnyPublisher() }
    var isApplyingUndo = false
    var canOrganize: Bool { workspace.presentation.canEditCollections && !isApplyingUndo }
    var canImport: Bool { canOrganize && [.videos, .images, .favorites].contains(workspace.presentation.page) }
    var canToggleSelection: Bool { !workspace.presentation.page.isRemoteBrowse && workspace.presentation.page != .playlists }
    var selectionReads = 0, favoriteStateReads = 0
    var selection: [WallpaperContentItem] {
        selectionReads += 1
        return workspace.presentation.queryResult.items.filter { workspace.presentation.selectionState.references.contains($0.reference) }
    }
    var canFavorite: Bool { canOrganize && !selection.isEmpty }
    var favoriteIsRemoving = false
    var favoriteActionState: (canExecute: Bool, isRemoving: Bool, title: String) {
        favoriteActionState(for: selection)
    }
    func favoriteActionState(for items: [WallpaperContentItem]) -> (canExecute: Bool, isRemoving: Bool, title: String) {
        favoriteStateReads += 1
        return (canOrganize && !items.isEmpty, favoriteIsRemoving, favoriteIsRemoving ? "取消特别喜爱" : "添加到特别喜爱")
    }
    var manualOrderRequests = 0
    var canBeginManualOrdering: Bool {
        guard canOrganize else { return false }
        return workspace.presentation.page == .playlists
            && !workspace.presentation.queryState.permitsManualReordering
    }
    func beginManualOrdering() { manualOrderRequests += 1 }
    var removalTitle: String { workspace.presentation.page == .favorites ? "取消特别喜爱" : "移除所选" }
    init(_ workspace: WallpaperLibraryWorkspace) { self.workspace = workspace }
    func importFiles() { imports += 1 }
    func toggleSelectionMode() {
        _ = workspace.presentation.setSelection([], isSelecting: !workspace.presentation.selectionState.isSelecting)
    }
    var removalReceipts: [[WallpaperReference]] = []
    func remove(_ items: [WallpaperContentItem]? = nil, from page: WallpaperLibraryPage? = nil) {
        removals += 1; removalReceipts.append((items ?? selection).map(\.reference))
    }
    func toggleFavorite() { favorites += 1 }
    var favoriteReceipts: [(references: [WallpaperReference], isRemoving: Bool)] = []
    func makeFavoriteAction(_ references: [WallpaperReference]? = nil) -> (() -> Void)? {
        let items = references.map { references in
            workspace.presentation.queryResult.items.filter { references.contains($0.reference) }
        } ?? selection
        let action = favoriteActionState(for: items)
        guard action.canExecute else { return nil }
        let fixed = items.map(\.reference), removing = action.isRemoving
        return { [weak self] in self?.favoriteReceipts.append((fixed, removing)) }
    }
    func playDisplayed(random: Bool = false) { if random { randoms += 1 } else { plays += 1 } }
    func contextMenu(for items: [WallpaperContentItem]) -> NSMenu? {
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "固定内容操作", symbol: "info.circle") {})
        return menu
    }
    func makePlaylistMenu() -> NSMenu? {
        guard canOrganize, !selection.isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "固定播放列表", symbol: "music.note.list") { [weak self] in self?.playlistChoices += 1 })
        return menu
    }
    func makeRecentMenu() -> NSMenu? {
        guard workspace.presentation.page == .recent else { return nil }
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "清空最近使用…", symbol: "trash") { [weak self] in self?.recentClears += 1 })
        return menu
    }
}
// Acquisition/session behavior stays in its Core gate; this leaf records
// the production window toolbar's source dispatch and native item ownership.
@MainActor final class WallpaperLibraryOnlineImages { var onChange: (() -> Void)? }
@MainActor final class OnlineImageToolbarController {
    static var latest: OnlineImageToolbarController!
    let identifiers: [NSToolbarItem.Identifier] = [.init("fixture-image-filter"), .init("fixture-image-search")]
    var focused = 0
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    init(images: WallpaperLibraryOnlineImages, workspace: WallpaperLibraryWorkspace, window: NSWindow?) { Self.latest = self }
    func refresh() {}
    func focusSearch() { focused += 1 }
    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard identifiers.contains(id) else { return nil }
        if let old = items[id] { return old }
        let item = NSToolbarItem(itemIdentifier: id); item.label = id.rawValue
        items[id] = item; return item
    }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var downloadsShowsAdultContent = false
    var browserSectionTitle = "创意工坊"
}
@MainActor final class SteamWorkshopToolbarController {
    static var latest: SteamWorkshopToolbarController!
    var titleUpdateHandler: ((String) -> Void)?
    let browserIdentifiers: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator, .init("ToolbarTitle"), .flexibleSpace,
        .steamAccount, .steamDownloadTasks, .init("fixture-steam-filter"), .init("fixture-steam-search")]
    var queries = "kept steam server query", focused = 0
    var makeZoomAction: ((Int) -> (() -> Void)?)?
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    init(toolbar: NSToolbar, window: NSWindow?) { Self.latest = self }
    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard browserIdentifiers.contains(id), id != .sidebarTrackingSeparator, id != .flexibleSpace, id.rawValue != "ToolbarTitle" else { return nil }
        if let existing = items[id] { return existing }
        let item = NSToolbarItem(itemIdentifier: id); item.label = "Steam \(id.rawValue)"
        item.image = NSImage(systemSymbolName: "square", accessibilityDescription: nil); items[id] = item
        return item
    }
    var layoutUpdates = 0
    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) { layoutUpdates += 1 }
    func focusSearch() { focused += 1 }
}
@MainActor final class OnlineLibraryToolbarController {
    static var latest: OnlineLibraryToolbarController!
    var titleUpdateHandler: ((String) -> Void)?
    let onlineIdentifiers: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator, .init("ToolbarTitle"), .flexibleSpace,
        .init("fixture-online-settings"), .init("fixture-online-category"), .init("fixture-online-search")]
    var queries = "kept Pixabay server query", focused = 0
    var makeZoomAction: ((Int) -> (() -> Void)?)?
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    init(window: NSWindow?) { Self.latest = self }
    func makeItem(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard onlineIdentifiers.contains(id), id != .sidebarTrackingSeparator, id != .flexibleSpace, id.rawValue != "ToolbarTitle" else { return nil }
        if let existing = items[id] { return existing }
        let item = NSToolbarItem(itemIdentifier: id); item.label = "Pixabay \(id.rawValue)"
        item.image = NSImage(systemSymbolName: "square", accessibilityDescription: nil); items[id] = item
        return item
    }
    var layoutUpdates = 0, categoryWidthUpdates = 0
    func configureZoom(preferredColumns: Int, clipWidth: CGFloat) { layoutUpdates += 1 }
    func updateCategoryScrollWidth() { categoryWidthUpdates += 1 }
    func focusSearch() { focused += 1 }
}

@main private enum LibraryWindowToolbarChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fatalError("Toolbar fixture: \(error)") }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let app = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let suite = "mwx.toolbar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserCollectionsStore(url: root.appendingPathComponent("relations.sqlite3"))
        let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        func content(_ provider: WallpaperProvider, _ id: String, _ kind: WallpaperMediaKind) -> WallpaperContentItem {
            let ref = WallpaperReference(provider: provider, sourceID: id)
            return .init(reference: ref, providerReference: ref, locator: .init(mediaKind: kind), title: id, kind: kind,
                publishedAvailability: .available, capabilities: [.play, .organize, .inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        let video = content(.videoLibrary, "video", .video), image = content(.staticImageLibrary, "image", .image)
        let steam = content(.steamWorkshop, "steam", .scene), online = content(.pixabay, "1", .video)
        let list = try await collections.createPlaylist(name: "稳定 UUID 名称", members: [video.organizationItem, image.organizationItem, steam.organizationItem, online.organizationItem])
        let catalog = WallpaperLibraryCatalog(videos: [video], images: [image], downloads: [steam, online], revision: 1,
            loadedProviders: Set(WallpaperProvider.allCases))
        let workspace = WallpaperLibraryWorkspace(collections: collections, defaults: defaults, catalog: catalog)
        let commands = WallpaperLibraryCommands(workspace)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var clipWidth: CGFloat = 900
        var returnAction: (() -> Void)?
        let controller = WallpaperLibraryWindowToolbar(window: window, workspace: workspace, commands: commands, gridWidth: { clipWidth },
            makeDirectoryReturnAction: { returnAction }, onlineImages: WallpaperLibraryOnlineImages())
        app.activate()
        window.makeKeyAndOrderFront(nil)
        let initialKeyDeadline = Date().addingTimeInterval(5)
        while !app.isActive || !window.isKeyWindow {
            if Date() >= initialKeyDeadline {
                func describe(_ value: NSWindow?) -> String {
                    guard let value else { return "nil" }
                    return "\(String(describing: type(of: value)))#\(value.windowNumber)(visible=\(value.isVisible),key=\(value.isKeyWindow),main=\(value.isMainWindow),sheet=\(value.isSheet))"
                }
                let frontmost = NSWorkspace.shared.frontmostApplication
                let content = window.contentView.map {
                    "\(String(describing: type(of: $0)))(window=\($0.window?.windowNumber ?? -1),frame=\($0.frame))"
                } ?? "nil"
                let values = [
                    "Toolbar initial-key timeout",
                    "app.active=\(app.isActive)", "app.running=\(app.isRunning)", "app.policy=\(app.activationPolicy().rawValue)",
                    "frontmost.pid=\(frontmost?.processIdentifier ?? -1)", "frontmost.bundle=\(frontmost?.bundleIdentifier ?? "nil")",
                    "window=\(describe(window))", "window.canKey=\(window.canBecomeKey)", "window.canMain=\(window.canBecomeMain)",
                    "window.style=\(window.styleMask.rawValue)", "window.content=\(content)",
                    "window.attached=\(describe(window.attachedSheet))", "window.parent=\(describe(window.sheetParent))",
                    "app.key=\(describe(app.keyWindow))", "app.main=\(describe(app.mainWindow))", "app.modal=\(describe(app.modalWindow))",
                    "app.windows=\(app.windows.map { describe($0) })",
                    "toolbar.ids=\(controller.toolbar.items.map { $0.itemIdentifier.rawValue })"
                ]
                FileHandle.standardError.write(Data((values.joined(separator: " ") + "\n").utf8))
            }
            precondition(Date() < initialKeyDeadline, "Toolbar native fixture did not receive its initial key-window admission")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        defer { window.orderOut(nil) }
        var checks: [String: Bool] = [:]
        func settle() { window.contentView?.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.015)) }
        func page(_ value: WallpaperLibraryPage) {
            if value == .workshop { SteamWorkshopService.shared.browserSectionTitle = value.title() }
            _ = workspace.presentation.switchPage(value); controller.refresh(); settle()
        }
        func item(_ raw: String) -> NSToolbarItem { controller.toolbar.items.first { $0.itemIdentifier.rawValue == raw }! }
        func title() -> String { (item("ToolbarTitle").view as! NSTextField).stringValue }
        func actionGroups() -> [[String]] {
            guard let start = controller.toolbar.items.firstIndex(where: { $0.itemIdentifier == .flexibleSpace }) else { return [] }
            var groups: [[String]] = [[]]
            for native in controller.toolbar.items.dropFirst(start + 1) {
                if native.itemIdentifier == .space { groups.append([]) }
                else { groups[groups.count - 1].append(native.itemIdentifier.rawValue) }
            }
            return groups
        }
        func titleMetadataMatches(_ expected: String, summary: String? = nil) -> Bool {
            let native = item("ToolbarTitle"), label = native.view as! NSTextField
            return label.stringValue == expected && label.accessibilityLabel() == expected
                && native.label == expected && native.paletteLabel == expected
                && native.toolTip == (summary.map { "\(expected)\n\($0)" } ?? expected)
                && label.accessibilityHelp() == summary
        }
        func trigger(_ raw: String) -> Bool {
            let control = item(raw)
            guard let action = control.action else { return false }
            return app.sendAction(action, to: control.target, from: control)
        }
        func menu(_ raw: String) -> NSMenu {
            let native = item(raw) as! NSMenuToolbarItem
            // NSMenu.update validates an existing menu; AppKit asks the
            // delegate for its dynamic contents when native tracking opens.
            let cancellation = Timer(timeInterval: 0.025, repeats: false) { _ in
                MainActor.assumeIsolated { native.menu.cancelTracking() }
            }
            RunLoop.main.add(cancellation, forMode: .eventTracking)
            native.menu.popUp(positioning: nil, at: NSPoint(x: 24, y: 24), in: window.contentView)
            cancellation.invalidate()
            return native.menu
        }
        func invoke(_ menu: NSMenu, _ title: String) { menu.performActionForItem(at: menu.items.firstIndex { $0.title == title }!) }
        page(.videos)
        checks["window-owns-one-native-toolbar-with-one-title-and-search"] = window.toolbar === controller.toolbar
            && controller.toolbar.items.filter { $0.itemIdentifier.rawValue == "ToolbarTitle" }.count == 1
            && controller.toolbar.items.filter { $0 is NSSearchToolbarItem }.count == 1 && title() == "我的视频"
        checks["initial-native-title-value-accessibility-and-item-metadata-share-one-value"] = titleMetadataMatches("我的视频", summary: "显示 1 / 共 1 张壁纸")
        checks["video-toolbar-has-six-native-groups-without-empty-spaces"] = actionGroups() == [["importFiles", "select", "addToPlaylist"], ["previous", "next"],
            ["remove", "favorite", "more"], ["sort"], ["zoom"], ["search"]]
        checks["fixed-sidebar-has-no-toolbar-toggle"] = !controller.toolbar.items.contains { $0.itemIdentifier == .toggleSidebar }
        checks["ordinary-library-does-not-duplicate-play-header-actions"] = !controller.toolbar.items.contains { ["play", "random", "back"].contains($0.itemIdentifier.rawValue) }
        checks["native-menu-items-own-menu-without-custom-view-anchor"] = ["sort", "more", "addToPlaylist"].allSatisfy {
            let native = item($0) as? NSMenuToolbarItem
            return native != nil && native?.menu.delegate === controller
        }
        checks["empty-selection-disables-organization-actions-with-stable-identifiers"] = !item("remove").isEnabled && !item("favorite").isEnabled && !item("addToPlaylist").isEnabled && !item("more").isEnabled
        _ = workspace.presentation.setSelection([video.reference], focused: video.reference, isSelecting: true); controller.refresh()
        checks["selection-enables-current-organization-and-displays-count"] = item("remove").isEnabled && item("favorite").isEnabled
            && item("addToPlaylist").isEnabled && item("more").isEnabled && title().contains("已选 1 项")
        checks["native-title-metadata-and-accessibility-follow-selection-count"] = titleMetadataMatches("我的视频 · 已选 1 项", summary: "显示 1 / 共 1 张壁纸")
        commands.selectionReads = 0; commands.favoriteStateReads = 0
        controller.refresh()
        checks["one-refresh-reuses-selection-and-favorite-display-state-with-one-fixed-action-factory"] = commands.selectionReads == 1
            && commands.favoriteStateReads == 2 && item("favorite").isEnabled && item("addToPlaylist").isEnabled
        commands.isApplyingUndo = true; commands.availabilityInvalidations.send()
        checks["undo-busy-invalidation-synchronously-revokes-toolbar-favorite"] = !item("favorite").isEnabled && !item("addToPlaylist").isEnabled
        commands.isApplyingUndo = false; commands.availabilityInvalidations.send()
        checks["undo-completion-invalidation-restores-current-toolbar-qualification"] = item("favorite").isEnabled && item("addToPlaylist").isEnabled
        commands.favoriteIsRemoving = true; controller.refresh()
        checks["favorite-toolbar-shares-command-title-filled-heart-and-accessibility"] = item("favorite").label == "取消特别喜爱"
            && item("favorite").toolTip == "取消特别喜爱" && item("favorite").image?.accessibilityDescription == "取消特别喜爱"
        commands.favoriteIsRemoving = false; controller.refresh()
        let heldRemoval = item("remove").menuFormRepresentation!, removalSession = workspace.presentation.selectionState.sessionID
        _ = workspace.presentation.setSelection([], isSelecting: true)
        _ = workspace.presentation.setSelection([video.reference], focused: video.reference, isSelecting: true); controller.refresh()
        _ = app.sendAction(heldRemoval.action!, to: heldRemoval.target, from: heldRemoval)
        checks["held-removal-overflow-cannot-borrow-a-later-selection-session"] = workspace.presentation.selectionState.sessionID != removalSession
            && commands.removals == 0 && commands.removalReceipts.isEmpty
        let currentRemoval = item("remove").menuFormRepresentation!
        _ = app.sendAction(currentRemoval.action!, to: currentRemoval.target, from: currentRemoval)
        checks["current-removal-overflow-passes-the-captured-items-to-the-original-command"] = commands.removals == 1
            && commands.removalReceipts == [[video.reference]]
        let heldFavorite = item("favorite").menuFormRepresentation!
        commands.favoriteIsRemoving = true; controller.refresh()
        _ = app.sendAction(heldFavorite.action!, to: heldFavorite.target, from: heldFavorite)
        checks["favorite-overflow-invokes-the-fixed-reference-and-intent-factory-receipt"] = commands.favoriteReceipts.count == 1
            && commands.favoriteReceipts[0].references == [video.reference] && !commands.favoriteReceipts[0].isRemoving && commands.favorites == 0
        commands.favoriteIsRemoving = false; controller.refresh()
        let previous = commands.manager.manual.count
        _ = trigger("next")
        checks["video-toolbar-retains-original-throttled-manual-entry"] = commands.manager.manual.count == previous + 1 && commands.manager.adjacent.isEmpty
        let playlistMenu = menu("addToPlaylist")
        invoke(playlistMenu, "固定播放列表")
        checks["native-add-menu-delegates-to-shared-command-factory"] = commands.playlistChoices == 1
        let nativeSort = item("sort") as! NSMenuToolbarItem, sorts = menu("sort")
        checks["native-default-video-sort-checkmark-and-direction"] = sorts.items.first { $0.title == "默认顺序" }?.state == .on
            && sorts.items.first { $0.title == "改为降序" }?.isEnabled == false
        let staleSort = sorts.items.first { $0.title == "名称" }!
        page(.images)
        checks["image-toolbar-keeps-the-same-six-role-groups"] = actionGroups() == [["importFiles", "select", "addToPlaylist"], ["previous", "next"],
            ["remove", "favorite", "more"], ["sort"], ["zoom"], ["search"]]
        checks["native-title-metadata-and-accessibility-follow-image-page"] = titleMetadataMatches("我的图片", summary: "显示 1 / 共 1 张壁纸")
        _ = app.sendAction(staleSort.action!, to: staleSort.target, from: staleSort)
        checks["old-sort-menu-cannot-change-another-page"] = workspace.presentation.queryState.sort == nil
        _ = trigger("previous")
        checks["image-toolbar-navigation-delegates-unified-adjacent-policy"] = commands.manager.adjacent.count == 1
        page(.downloads)
        checks["downloads-retains-one-account-task-group-and-four-page-groups"] = actionGroups() == [["fixture-steam-account", "fixture-steam-tasks"],
            ["select", "remove", "more"], ["filter", "sort"], ["zoom"], ["search"]]
        checks["native-title-metadata-and-accessibility-follow-downloads-page"] = titleMetadataMatches("我的下载", summary: "显示 2 / 共 2 张壁纸")
        let downloadSort = menu("sort")
        checks["default-download-order-is-newest-first-with-native-checkmark"] = downloadSort.items.first { $0.title == "本地记录时间" }?.state == .on
            && downloadSort.items.contains { $0.title == "改为升序" }
        invoke(downloadSort, "名称")
        checks["choosing-sort-preserves-default-download-descending-direction"] = workspace.presentation.queryState.sort == .name && !workspace.presentation.queryState.ascending
        let adultMenu = menu("filter"), oldAdult = menu("filter").items.first { $0.title == "成人内容" }!
        checks["downloads-adult-filter-uses-the-existing-source-preference"] = adultMenu.items.first { $0.title == "成人内容" }?.state == .off
        invoke(adultMenu, "成人内容")
        checks["downloads-adult-filter-native-action-updates-the-original-owner"] = SteamWorkshopService.shared.downloadsShowsAdultContent
            && menu("filter").items.first { $0.title == "成人内容" }?.state == .on
        _ = workspace.presentation.setSelection([online.reference], focused: online.reference, isSelecting: false); controller.refresh()
        checks["downloads-more-is-enabled-only-with-an-actual-current-selection"] = item("more").isEnabled && item("remove").isEnabled
        let localMore = menu("more"), staleRefresh = localMore.items.first { $0.title == "刷新文件状态" }!
        invoke(localMore, "刷新文件状态")
        checks["downloads-refresh-is-reachable-through-the-sole-workspace-source-entry"] = workspace.sourceRefreshes == 1
        let filters = menu("filter")
        checks["downloads-offers-all-four-local-download-provider-filters"] = ["Steam 创意工坊", "Pixabay", "Wallhaven", "Pixiv"].allSatisfy { title in
            filters.items.contains { $0.title == title }
        }
        checks["type-counts-use-current-page-and-preserve-other-filters"] = filters.items.contains { $0.title == "全部类型（2）" }
            && filters.items.contains { $0.title == "视频（1）" } && filters.items.contains { $0.title == "Scene（1）" }
        invoke(filters, "Pixabay")
        invoke(menu("filter"), "视频（1）")
        invoke(menu("filter"), "可播放")
        checks["filter-dimensions-compose-without-resetting-other-dimensions"] = workspace.presentation.queryState.provider == .pixabay
            && workspace.presentation.queryState.kind == .video && workspace.presentation.queryState.status == .playable
            && workspace.presentation.queryResult.items.map(\.reference) == [online.reference]
        let filtered = menu("filter")
        checks["native-filter-checkmarks-reflect-all-independent-values"] = ["Pixabay", "视频（1）", "可播放"].allSatisfy { name in filtered.items.first { $0.title == name }?.state == .on }
        controller.refresh()
        checks["active-filter-and-current-sort-remain-readable-without-opening-menus"] = item("filter").toolTip?.contains("Pixabay") == true
            && item("filter").toolTip?.contains("可播放") == true && item("sort").toolTip?.contains("名称") == true
        checks["local-title-help-distinguishes-current-results-from-the-unfiltered-page"] = titleMetadataMatches("我的下载", summary: "显示 1 / 共 2 张壁纸")
        invoke(filtered, "全部来源")
        checks["all-sources-restores-provider-union-without-clearing-kind-or-status"] = workspace.presentation.queryState.provider == nil
            && workspace.presentation.queryState.kind == .video && workspace.presentation.queryState.status == .playable
        let oldProviderItem = filtered.items.first { $0.title == "Steam 创意工坊" }!
        try await collections.reset(); workspace.refresh(); controller.refresh()
        let resetQuery = workspace.presentation.queryState
        _ = app.sendAction(oldProviderItem.action!, to: oldProviderItem.target, from: oldProviderItem)
        checks["old-filter-menu-cannot-write-across-store-reset"] = workspace.presentation.queryState == resetQuery
        page(.favorites)
        checks["favorites-has-one-cancel-action-without-a-duplicate-heart"] = controller.toolbar.items.filter { $0.itemIdentifier.rawValue == "remove" }.count == 1
            && !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "favorite" }
        checks["favorites-keeps-play-add-selection-removal-view-and-search-in-six-groups"] = actionGroups() == [["play", "random"],
            ["select", "addToPlaylist"], ["remove", "more"], ["filter", "sort"], ["zoom"], ["search"]]
        _ = app.sendAction(oldAdult.action!, to: oldAdult.target, from: oldAdult)
        _ = app.sendAction(staleRefresh.action!, to: staleRefresh.target, from: staleRefresh)
        checks["stale-downloads-menu-cannot-change-preference-or-refresh-another-page"] = SteamWorkshopService.shared.downloadsShowsAdultContent
            && workspace.sourceRefreshes == 1 && !menu("filter").items.contains { $0.title == "成人内容" }
        let favoritesSort = menu("sort")
        checks["favorite-default-sort-and-direction-match-query-authority"] = favoritesSort.items.first { $0.title == "标记喜爱时间" }?.state == .on
            && favoritesSort.items.contains { $0.title == "改为升序" }
        page(.recent)
        checks["recent-toolbar-groups-playback-organization-filter-zoom-search"] = actionGroups() == [["play", "random"],
            ["select", "addToPlaylist"], ["remove", "favorite", "more"], ["filter"], ["zoom"], ["search"]]
        let disabledRecentMore = item("more") as! NSMenuToolbarItem
        controller.menuNeedsUpdate(disabledRecentMore.menu)
        checks["recent-fixed-time-order-retains-clear-menu-content-while-empty-selection-disables-entry"] = !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "sort" }
            && !disabledRecentMore.isEnabled && disabledRecentMore.menu.items.contains { $0.title == "清空最近使用…" }
        page(.playlists)
        checks["native-title-metadata-and-accessibility-follow-playlist-directory"] = titleMetadataMatches("所有播放列表", summary: "显示 0 / 共 0 个播放列表")
        checks["directory-toolbar-has-create-without-wallpaper-organization-actions"] = item("create").isEnabled
            && !controller.toolbar.items.contains { ["select", "remove", "play", "random"].contains($0.itemIdentifier.rawValue) }
        checks["directory-is-four-small-native-groups"] = actionGroups() == [["create"], ["sort"], ["zoom"], ["search"]]
        checks["already-manual-directory-does-not-advertise-a-noop-arrange-command"] = !menu("sort").items.contains { $0.title == "切回手动并清除筛选以整理" }
        let freshList = try await collections.createPlaylist(name: "固定标题"); workspace.refresh(); controller.refresh()
        checks["directory-title-count-excludes-the-fixed-create-card"] = titleMetadataMatches("所有播放列表", summary: "显示 1 / 共 1 个播放列表")
        var directorySearch = workspace.presentation.queryState; directorySearch.search = "no matching playlist"
        _ = workspace.presentation.setQueryState(directorySearch); controller.refresh()
        checks["directory-title-count-keeps-total-while-search-hides-all-lists"] = titleMetadataMatches("所有播放列表", summary: "显示 0 / 共 1 个播放列表")
        _ = workspace.presentation.setQueryState(.init()); page(.playlist(freshList))
        checks["direct-sidebar-playlist-has-fixed-name-without-directory-return-or-duplicate-play"] = title() == "固定标题"
            && !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "back" }
            && !controller.toolbar.items.contains { ["play", "random"].contains($0.itemIdentifier.rawValue) }
        checks["native-title-metadata-and-accessibility-follow-custom-playlist-name"] = titleMetadataMatches("固定标题", summary: "显示 0 / 共 0 张壁纸")
        checks["custom-playlist-keeps-header-actions-out-of-its-five-toolbar-groups"] = actionGroups() == [["select", "addToPlaylist"], ["remove", "favorite", "more"],
            ["filter", "sort"], ["zoom"], ["search"]]
        var returns = 0
        returnAction = { returns += 1 }; controller.refresh()
        checks["directory-entry-return-is-the-first-independent-right-control-group"] = actionGroups().first == ["back"]
            && (item("back").view as? NSButton)?.title == "返回"
            && (item("back").view as? NSButton)?.imagePosition == .imageLeading
        let nativeReturn = item("back").view as! NSButton
        FileHandle.standardError.write(Data("Q03 before native return action=\(String(describing: nativeReturn.action)) target=\(String(describing: nativeReturn.target))\n".utf8))
        nativeReturn.performClick(nil)
        FileHandle.standardError.write(Data("Q03 after native return count=\(returns)\n".utf8))
        checks["directory-return-native-button-invokes-once-through-its-own-target"] = returns == 1
        let returnOverflow = item("back").menuFormRepresentation!
        _ = app.sendAction(returnOverflow.action!, to: returnOverflow.target, from: returnOverflow)
        checks["directory-return-overflow-runs-the-captured-action"] = returns == 2
        let heldSort = menu("sort").items.first { $0.title == "名称" }!
        let heldFilter = menu("filter").items.first { $0.title == "Pixabay" }!
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.beginSheet(sheet, completionHandler: { _ in }); controller.refresh(); settle()
        let originalQuery = workspace.presentation.queryState
        _ = app.sendAction(heldSort.action!, to: heldSort.target, from: heldSort)
        _ = app.sendAction(heldFilter.action!, to: heldFilter.target, from: heldFilter)
        checks["one-outer-modal-gate-revokes-held-sort-and-filter-without-changing-the-query"] = workspace.presentation.queryState == originalQuery
        _ = app.sendAction(returnOverflow.action!, to: returnOverflow.target, from: returnOverflow)
        nativeReturn.performClick(nil)
        controller.performZoom(delta: 1)
        let choicesBeforeHeldMenu = commands.playlistChoices
        invoke(playlistMenu, "固定播放列表")
        checks["modal-sheet-blocks-held-native-playlist-submenu-actions"] = commands.playlistChoices == choicesBeforeHeldMenu
        FileHandle.standardError.write(Data("toolbar-modal-return returns=\(returns) itemEnabled=\(item("back").isEnabled) buttonEnabled=\(nativeReturn.isEnabled) queryUnchanged=\(workspace.presentation.queryState == originalQuery) sheetAttached=\(window.attachedSheet === sheet) keyWindow=\(String(describing: NSApp.keyWindow?.title))\n".utf8))
        checks["modal-sheet-blocks-held-return-and-background-toolbar-zoom"] = returns == 2
            && !item("back").isEnabled && workspace.presentation.queryState == originalQuery
        window.endSheet(sheet); sheet.orderOut(nil); window.makeKeyAndOrderFront(nil); settle()
        returnAction = nil; controller.refresh()
        checks["clearing-directory-entry-context-removes-only-the-return-group"] = !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "back" }
        var filteredManual = workspace.presentation.queryState
        filteredManual.search = "fixed search"; filteredManual.provider = .videoLibrary; filteredManual.kind = .video
        filteredManual.status = .unavailable; filteredManual.sort = .name; filteredManual.preferredColumns = 4
        filteredManual.scrollAnchor = video.reference; filteredManual.scrollOffset = -13; filteredManual.scrollAtTop = false
        _ = workspace.presentation.setQueryState(filteredManual); controller.refresh()
        invoke(menu("sort"), "手动顺序")
        var expectedManual = filteredManual; expectedManual.sort = .sourceOrder
        checks["ordinary-manual-sort-retains-filter-search-density-and-scroll"] = workspace.presentation.queryState == expectedManual
            && commands.manualOrderRequests == 0
        checks["member-grid-never-advertises-internal-drag-ordering"] = !menu("sort").items.contains { $0.title == "切回手动并清除筛选以整理" }
            && !commands.canBeginManualOrdering
        page(.playlists)
        var directoryManual = workspace.presentation.queryState
        directoryManual.search = "directory search"; directoryManual.sort = .name; directoryManual.preferredColumns = 4
        _ = workspace.presentation.setQueryState(directoryManual); controller.refresh()
        let oldArrange = menu("sort").items.first { $0.title == "切回手动并清除筛选以整理" }!
        let explicitArrange = menu("sort")
        invoke(explicitArrange, "切回手动并清除筛选以整理")
        checks["explicit-arrange-routes-once-through-the-shared-command"] = commands.manualOrderRequests == 1
            && workspace.presentation.queryState == directoryManual
        workspace.presentation.setEditingAllowed(false); controller.refresh()
        _ = workspace.presentation.setQueryState(directoryManual); controller.refresh()
        invoke(menu("sort"), "手动顺序")
        var expectedDirectoryManual = directoryManual; expectedDirectoryManual.sort = .sourceOrder
        checks["readonly-manual-sort-keeps-the-same-query-without-a-drag-promise"] = workspace.presentation.queryState == expectedDirectoryManual
            && !menu("sort").items.contains { $0.title == "切回手动并清除筛选以整理" }
        workspace.presentation.setEditingAllowed(true)
        _ = workspace.presentation.setQueryState(.init()); controller.refresh()
        page(.playlist(freshList))
        _ = app.sendAction(oldArrange.action!, to: oldArrange.target, from: oldArrange)
        checks["held-arrange-menu-cannot-clear-a-different-page-query"] = commands.manualOrderRequests == 1
        page(.workshop)
        SteamWorkshopService.shared.browserSectionTitle = "作者的创意工坊"
        SteamWorkshopToolbarController.latest.titleUpdateHandler?("作者的创意工坊")
        checks["original-source-title-callback-updates-native-accessibility-and-item-metadata"] = titleMetadataMatches("作者的创意工坊")
        workspace.refresh(); controller.refresh()
        NotificationCenter.default.post(name: .steamWorkshopBrowseContextDidChange, object: nil)
        checks["source-context-title-survives-relationship-echo-and-context-notification"] = titleMetadataMatches("作者的创意工坊")
        SteamWorkshopService.shared.browserSectionTitle = "创意工坊"
        SteamWorkshopToolbarController.latest.titleUpdateHandler?("迟到的作者标题")
        checks["returning-to-discovery-reads-current-source-facts-instead-of-a-held-title-string"] = titleMetadataMatches("创意工坊")
        let sourceItem = item("fixture-steam-search")
        let staleSteamZoom = SteamWorkshopToolbarController.latest.makeZoomAction?(1)
        controller.focusSearch(); controller.performZoom(delta: 1)
        checks["workshop-retains-original-items-and-search-with-one-page-column-owner"] = SteamWorkshopToolbarController.latest.focused == 1
            && workspace.presentation.queryState.preferredColumns == 4 && !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "search" }
        let steamBeforeResize = SteamWorkshopToolbarController.latest.layoutUpdates
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        checks["active-steam-controls-recompute-layout-from-the-window-owner"] = SteamWorkshopToolbarController.latest.layoutUpdates == steamBeforeResize + 1
        page(.videos)
        let localDensity = workspace.presentation.queryState
        staleSteamZoom?()
        checks["old-steam-zoom-action-cannot-mutate-another-page"] = workspace.presentation.queryState == localDensity
        page(.workshop)
        checks["workshop-reentry-reuses-original-source-control-identity"] = item("fixture-steam-search") === sourceItem
        page(.pixabay)
        controller.focusSearch(); controller.performZoom(delta: -1)
        checks["pixabay-retains-settings-category-search-with-one-page-column-owner"] = OnlineLibraryToolbarController.latest.focused == 1
            && workspace.presentation.queryState.preferredColumns == 6 && controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "fixture-online-settings" }
        let onlineBeforeResize = OnlineLibraryToolbarController.latest.layoutUpdates
        let categoryBeforeResize = OnlineLibraryToolbarController.latest.categoryWidthUpdates
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        checks["active-pixabay-controls-recompute-category-width-and-zoom"] = OnlineLibraryToolbarController.latest.layoutUpdates == onlineBeforeResize + 1
            && OnlineLibraryToolbarController.latest.categoryWidthUpdates == categoryBeforeResize + 1
        for imagePage in [WallpaperLibraryPage.wallhaven, .pixiv] {
            page(imagePage)
            let focused = OnlineImageToolbarController.latest.focused
            controller.focusSearch()
            checks["online-image-browser-uses-source-items-and-search-\(imagePage.persistenceKey)"] = titleMetadataMatches(imagePage.title())
                && OnlineImageToolbarController.latest.focused == focused + 1
                && controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "fixture-image-search" }
                && !controller.toolbar.items.contains { $0.itemIdentifier.rawValue == "search" || $0.itemIdentifier.rawValue == "importFiles" }
        }
        page(.videos)
        let localOnlineLayouts = OnlineLibraryToolbarController.latest.layoutUpdates
        let localSteamLayouts = SteamWorkshopToolbarController.latest.layoutUpdates
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        checks["local-window-resize-does-not-update-inactive-remote-controls"] = OnlineLibraryToolbarController.latest.layoutUpdates == localOnlineLayouts
            && SteamWorkshopToolbarController.latest.layoutUpdates == localSteamLayouts
        let zoom = item("zoom").view as! NSSegmentedControl
        checks["local-zoom-pair-retains-native-steam-shape-and-icon-order"] = zoom.segmentStyle == .capsule && zoom.segmentCount == 2
            && zoom.trackingMode == .momentary
            && zoom.image(forSegment: 0)?.accessibilityDescription == "缩小卡片"
            && zoom.image(forSegment: 1)?.accessibilityDescription == "放大卡片"
        checks["local-zoom-is-a-low-priority-view-control"] = item("zoom").visibilityPriority == .low
        window.setContentSize(NSSize(width: 1800, height: 560)); settle()
        var clickDensity = workspace.presentation.queryState; clickDensity.preferredColumns = 5
        _ = workspace.presentation.setQueryState(clickDensity); controller.refresh(); settle()
        // Native momentary tracking needs an actual active/key App window.
        // The prohibited, non-key CLI diagnostic left the first segment
        // pressed without dispatching its command. Do not retry either click.
        window.makeKeyAndOrderFront(nil)
        app.activate()
        let activationDeadline = Date().addingTimeInterval(2)
        while (!app.isActive || app.keyWindow !== window || app.mainWindow !== window), Date() < activationDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        settle()
        checks["native-mouse-tracking-runs-in-a-regular-active-main-key-window"] = app.activationPolicy() == .regular
            && app.isActive && app.mainWindow === window && app.keyWindow === window
            && window.isMainWindow && window.isKeyWindow
        let sharedZoom = zoom as! WallpaperLibraryZoomControl
        let originalMakeAction = sharedZoom.makeAction
        var clickPhase = "observe-initial-state", traceSequence = 0, factorySequence = 0
        func traceZoom(_ detail: String) {
            traceSequence += 1
            FileHandle.standardError.write(Data("Native zoom trace \(traceSequence) [\(clickPhase)]: \(detail)\n".utf8))
        }
        // Observe the original willSet payload. Reading the presentation getter
        // inside this sink would report the previous columns instead.
        let columnChanges = workspace.presentation.$state.sink { state in
            traceZoom("publisher page=\(state.page.persistenceKey), columns=\(state.query.preferredColumns), session=\(state.selectionState.sessionID)")
        }
        sharedZoom.makeAction = { [weak sharedZoom] delta in
            factorySequence += 1
            let receipt = factorySequence
            traceZoom("factory \(receipt) enter delta=\(delta), selected=\(sharedZoom?.selectedSegment ?? -99), originalBound=\(originalMakeAction != nil)")
            let command = originalMakeAction?(delta)
            traceZoom("factory \(receipt) returnedCommand=\(command != nil)")
            guard let command else { return nil }
            return {
                traceZoom("command \(receipt) before page=\(workspace.presentation.page.persistenceKey), columns=\(workspace.presentation.queryState.preferredColumns), session=\(workspace.presentation.selectionState.sessionID)")
                command()
                traceZoom("command \(receipt) after page=\(workspace.presentation.page.persistenceKey), columns=\(workspace.presentation.queryState.preferredColumns), session=\(workspace.presentation.selectionState.sessionID)")
            }
        }
        defer { sharedZoom.makeAction = originalMakeAction; columnChanges.cancel() }
        func clickZoom(_ segment: Int) async throws -> Bool {
            clickPhase = segment == 0 ? "minus-once" : "plus-once"
            let native = item("zoom")
            let localPoint = NSPoint(x: zoom.bounds.width * (segment == 0 ? 0.25 : 0.75), y: zoom.bounds.midY)
            let point = zoom.convert(localPoint, to: nil)
            let screenPoint = window.convertPoint(toScreen: point)
            let osScreenPoint = NSEvent.mouseLocation
            let windowStreamPoint = window.mouseLocationOutsideOfEventStream
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(screenPoint) }
            let isVisibleItem = controller.toolbar.visibleItems?.contains { $0 === native } == true
            let hitRoot = window.contentView?.superview
            let hit = hitRoot.flatMap { root in
                root.hitTest(root.convert(root.convert(point, from: nil), to: root.superview))
            }
            let hitsZoom = hit === zoom || hit?.isDescendant(of: zoom) == true
            let beforeColumns = workspace.presentation.queryState.preferredColumns
            let geometry = "segment=\(segment), policy=\(app.activationPolicy()), active=\(app.isActive), "
                + "window=\(window.frame), visible=\(window.isVisible), key=\(window.isKeyWindow), main=\(window.isMainWindow), "
                + "zoomFrame=\(zoom.frame), bounds=\(zoom.bounds), windowPoint=\(point), screenPoint=\(screenPoint), "
                + "osScreenPoint=\(osScreenPoint), windowStreamPoint=\(windowStreamPoint), "
                + "onScreen=\(onScreen), inVisibleItems=\(isVisibleItem), hidden=\(zoom.isHiddenOrHasHiddenAncestor), "
                + "hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil"), hitsZoom=\(hitsZoom), "
                + "enabled=\(zoom.isEnabled)/\(zoom.isEnabled(forSegment: segment)), beforeColumns=\(beforeColumns), beforeSelected=\(zoom.selectedSegment)"
            guard app.isActive, app.keyWindow === window, window.isKeyWindow,
                  window.isVisible, zoom.window === window, !zoom.isHiddenOrHasHiddenAncestor,
                  isVisibleItem, onScreen, hitsZoom else {
                FileHandle.standardError.write(Data("Native zoom click not dispatched: \(geometry)\n".utf8))
                return false
            }
            let time = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.01,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { return false }
            var dispatchedUps = 0
            let upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                MainActor.assumeIsolated {
                    if event.windowNumber == window.windowNumber, event.eventNumber == up.eventNumber { dispatchedUps += 1 }
                }
                return event
            }
            defer { if let upMonitor { NSEvent.removeMonitor(upMonitor) } }
            traceZoom("before down: \(geometry)")
            app.postEvent(up, atStart: true)
            window.sendEvent(down)
            // A nested RunLoop pump does not dispatch NSApp's queued mouseUp.
            // Yield this task for one fixed event turn; NSApp owns dispatch.
            try await Task.sleep(nanoseconds: 15_000_000)
            window.contentView?.layoutSubtreeIfNeeded()
            FileHandle.standardError.write(Data(("Native zoom mouseDown/mouseUp: \(geometry), "
                + "afterColumns=\(workspace.presentation.queryState.preferredColumns), afterSelected=\(zoom.selectedSegment), "
                + "highlighted=\(zoom.cell?.isHighlighted == true), nativeDispatchedUps=\(dispatchedUps)\n").utf8))
            return true
        }
        // Drain already-enqueued page/query delivery before starting either
        // native tracking operation. This is one fixed turn, not a retry.
        clickPhase = "pre-input-settlement"
        try await Task.sleep(nanoseconds: 15_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
        let minusBefore = workspace.presentation.queryState.preferredColumns
        let minusTracked = try await clickZoom(0)
        checks["real-native-momentary-minus-click-shrinks-cards-and-clears-pressed-state"] = minusTracked
            && minusBefore == 5 && workspace.presentation.queryState.preferredColumns == 6
            && zoom.selectedSegment == -1 && zoom.cell?.isHighlighted != true
        let plusBefore = workspace.presentation.queryState.preferredColumns
        let plusTracked = try await clickZoom(1)
        checks["real-native-momentary-plus-click-enlarges-cards-and-clears-pressed-state"] = plusTracked
            && plusBefore == 6 && workspace.presentation.queryState.preferredColumns == 5
            && zoom.selectedSegment == -1 && zoom.cell?.isHighlighted != true
        sharedZoom.makeAction = originalMakeAction
        columnChanges.cancel()
        let beforeZeroDelta = workspace.presentation.queryState
        controller.performZoom(delta: 0)
        checks["global-zero-delta-does-not-dispatch-or-rewrite-query"] = workspace.presentation.queryState == beforeZeroDelta
        clipWidth = 0; controller.refreshSourceLayout()
        checks["unmounted-grid-disables-both-zoom-segments-and-overflow"] = !zoom.isEnabled(forSegment: 0) && !zoom.isEnabled(forSegment: 1)
            && item("zoom").menuFormRepresentation?.submenu?.items.allSatisfy { !$0.isEnabled } == true
        clipWidth = 550
        var density = workspace.presentation.queryState; density.preferredColumns = 6
        _ = workspace.presentation.setQueryState(density); controller.refreshSourceLayout()
        checks["narrow-grid-preserves-request-and-disables-impossible-smaller-cards"] = workspace.presentation.queryState.preferredColumns == 6
            && !zoom.isEnabled(forSegment: 0) && zoom.isEnabled(forSegment: 1)
        checks["narrow-zoom-help-explains-effective-density-without-changing-preference"] = zoom.toolTip?.contains("保留每行 6 张") == true
            && zoom.accessibilityHelp()?.contains("当前窗口") == true
            && item("zoom").menuFormRepresentation?.toolTip == zoom.toolTip
        let zoomMenu = item("zoom").menuFormRepresentation!.submenu!
        zoomMenu.performActionForItem(at: 1)
        checks["native-zoom-overflow-enlarges-effective-five-to-four-on-first-command"] = workspace.presentation.queryState.preferredColumns == 4
        clipWidth = 900; controller.refreshSourceLayout()
        checks["resize-retains-per-page-density-and-restores-available-zoom"] = workspace.presentation.queryState.preferredColumns == 4
            && zoom.isEnabled(forSegment: 0) && zoom.isEnabled(forSegment: 1) && item("zoom").isEnabled
        let staleZoom = item("zoom").menuFormRepresentation!.submenu!.items[1]
        try await collections.reset(); workspace.refresh(); controller.refresh()
        let afterZoomReset = workspace.presentation.queryState
        _ = app.sendAction(staleZoom.action!, to: staleZoom.target, from: staleZoom)
        checks["old-native-zoom-overflow-cannot-write-across-reset"] = workspace.presentation.queryState == afterZoomReset
        let search = item("search") as! NSSearchToolbarItem
        checks["native-search-and-menu-overflow-are-not-replaced-by-ordinary-button-actions"] = !(search.menuFormRepresentation is ActionMenuItem)
            && (item("sort") as! NSMenuToolbarItem).menuFormRepresentation?.submenu === (item("sort") as! NSMenuToolbarItem).menu
        search.searchField.stringValue = "local only"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search.searchField))
        page(.pixabay); page(.videos)
        checks["page-search-restores-local-state-without-erasing-remote-query"] = search.searchField.stringValue == "local only"
            && workspace.presentation.queryState.search == "local only"
            && SteamWorkshopToolbarController.latest.queries == "kept steam server query"
            && OnlineLibraryToolbarController.latest.queries == "kept Pixabay server query"
        var query = workspace.presentation.queryState; query.search = ""; _ = workspace.presentation.setQueryState(query)
        workspace.presentation.setEditingAllowed(false); controller.refresh()
        checks["recovery-readonly-disables-mutations-without-disabling-view-controls"] = !item("importFiles").isEnabled
            && !item("favorite").isEnabled && !item("addToPlaylist").isEnabled && item("sort").isEnabled && item("search").isEnabled
        workspace.presentation.setEditingAllowed(true); controller.refresh()
        let requestedLongName = String(repeating: "很长的家庭媒体播放列表 🎨🌇 ", count: 8)
        let longList = try await collections.createPlaylist(name: requestedLongName); workspace.refresh(); page(.playlist(longList))
        let longName = workspace.relationships.playlists.first { $0.id == longList }!.name
        checks["long-playlist-title-retains-the-source-name-trimming-contract"] = longName == requestedLongName.trimmingCharacters(in: .whitespacesAndNewlines)
            && longName != requestedLongName
        window.setContentSize(NSSize(width: 900, height: 560)); settle()
        let longTitle = item("ToolbarTitle").view as! NSTextField
        // Auto Layout sizes native text fields by their alignment rect, not
        // their drawing frame. An independent stock label keeps that distinction
        // honest without increasing the product's 280 pt layout budget.
        let stockHost = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        let stockTitle = NSTextField(labelWithString: longName)
        stockTitle.font = .systemFont(ofSize: 16, weight: .bold)
        stockTitle.lineBreakMode = .byTruncatingTail
        stockTitle.translatesAutoresizingMaskIntoConstraints = false
        stockHost.addSubview(stockTitle)
        NSLayoutConstraint.activate([
            stockTitle.leadingAnchor.constraint(equalTo: stockHost.leadingAnchor, constant: 20),
            stockTitle.topAnchor.constraint(equalTo: stockHost.topAnchor, constant: 20),
            stockTitle.widthAnchor.constraint(equalToConstant: 280)
        ])
        stockHost.layoutSubtreeIfNeeded()
        let titleAlignment = longTitle.alignmentRect(forFrame: longTitle.frame)
        let stockAlignment = stockTitle.alignmentRect(forFrame: stockTitle.frame)
        let titleInsets = longTitle.alignmentRectInsets, stockInsets = stockTitle.alignmentRectInsets
        checks["native-title-frame-extension-matches-independent-stock-alignment-layout"] = abs(stockAlignment.width - 280) <= 0.5
            && abs((longTitle.frame.width - titleAlignment.width) - (stockTitle.frame.width - stockAlignment.width)) <= 0.5
            && abs(titleInsets.left - stockInsets.left) <= 0.5 && abs(titleInsets.right - stockInsets.right) <= 0.5
        checks["narrow-long-playlist-title-uses-native-truncation-and-complete-accessibility"] = titleMetadataMatches(longName, summary: "显示 0 / 共 0 张壁纸")
            && longTitle.lineBreakMode == .byTruncatingTail && titleAlignment.width <= 280.5
            && controller.toolbar.items.contains { $0 is NSSearchToolbarItem }
        if checks["narrow-long-playlist-title-uses-native-truncation-and-complete-accessibility"] != true
            || checks["native-title-frame-extension-matches-independent-stock-alignment-layout"] != true {
            let detail = "Long title metadata=\(titleMetadataMatches(longName, summary: "显示 0 / 共 0 张壁纸")), "
                + "truncating=\(longTitle.lineBreakMode == .byTruncatingTail), frame=\(longTitle.frame), alignment=\(titleAlignment), insets=\(titleInsets), "
                + "stockFrame=\(stockTitle.frame), stockAlignment=\(stockAlignment), stockInsets=\(stockInsets), "
                + "search=\(controller.toolbar.items.contains { $0 is NSSearchToolbarItem })\n"
            FileHandle.standardError.write(Data(detail.utf8))
        }
        page(.videos)
        window.setContentSize(NSSize(width: 360, height: 560)); settle()
        _ = menu("sort")
        checks["native-overflow-preserves-menu-representation-and-enabled-sort-actions"] = (controller.toolbar.visibleItems?.count ?? 0) < controller.toolbar.items.count
            && nativeSort.menuFormRepresentation?.submenu === nativeSort.menu && nativeSort.menu.items.contains { $0.title == "名称" && $0.isEnabled }
        checks["old-playlist-id-is-not-reused-after-reset"] = workspace.relationships.playlists.allSatisfy { $0.id != list }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
