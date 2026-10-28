// Compiled with the existing real Commands methods, Presentation and SQLite
// owner. Only the native confirmation response remains the existing alert leaf.
@MainActor private func runRecentSidebarCommandChecks(root: URL) async throws -> [String: Bool] {
    func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
    let store = UserCollectionsStore(url: root.appendingPathComponent("recent-sidebar.sqlite3"))
    let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
    let reference = WallpaperReference(provider: .videoLibrary, sourceID: "selected-video")
    let history = WallpaperReference(provider: .staticImageLibrary, sourceID: "recent-image")
    let value = WallpaperContentItem(reference: reference, providerReference: reference,
        locator: .init(titleHint: "Selected video", mediaKind: .video), title: "Selected video", kind: .video,
        publishedAvailability: .available, capabilities: [.play, .inspect, .organize], metadata: .init(),
        acquisition: .idle, update: .idle, aliases: [])
    _ = try await controller.createPlaylist(name: "Preserve sidebar context", members: [value.organizationItem])
    try await controller.perform(.setFavorite(value.organizationItem, true, Date()))
    controller.recordSuccessfulUse(history, locator: nil, sequence: 1)
    let initialHistory = await wait { controller.snapshot.recent.map(\.reference) == [history] }
    precondition(initialHistory)
    let suite = "mwx.recent-sidebar." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let catalog = WallpaperLibraryCatalog(videos: [value], revision: 1)
    let workspace = RemovalWorkspace(controller, catalog, defaults: defaults), commands = RemovalCommands(workspace)
    _ = workspace.presentation.setSelection([reference], focused: reference, isSelecting: true)
    let selection = workspace.presentation.selectionState, organization = controller.snapshot.organizationState
    let app = NSApplication.shared
    func open() {
        let item = commands.makeRecentMenu(for: .recent)!.items[0]
        _ = app.sendAction(item.action!, to: item.target, from: item)
    }
    var checks = ["toolbar-recent-menu-still-requires-the-current-recent-page": commands.makeRecentMenu() == nil]
    open()
    checks["sidebar-target-recent-opens-original-confirmation-without-navigation-or-selection-change"] = RecentAlertProbe.alert?.buttons == ["清空最近使用", "取消"]
        && workspace.presentation.page == .videos && workspace.presentation.selectionState == selection
    RecentAlertProbe.finish(.alertSecondButtonReturn)
    checks["sidebar-recent-cancel-preserves-history-and-unrelated-selection"] = controller.snapshot.recent.map(\.reference) == [history]
        && workspace.presentation.selectionState == selection && commands.admittedWrites == 0
    open(); RecentAlertProbe.finish(.alertFirstButtonReturn)
    let cleared = await wait { controller.snapshot.recent.isEmpty && !workspace.edited.isEmpty }
    checks["sidebar-recent-success-clears-only-history-through-real-store-and-keeps-other-page-multiselect"] = cleared
        && controller.snapshot.organizationState == organization && workspace.presentation.page == .videos
        && workspace.presentation.selectionState == selection && workspace.edited == [.recent] && commands.admittedWrites == 1
    checks["sidebar-recent-empty-history-command-remains-present-and-disabled"] = commands.makeRecentMenu(for: .recent)?.items[0].isEnabled == false
    controller.recordSuccessfulUse(history, locator: nil, sequence: 2)
    let resumedHistory = await wait { controller.snapshot.recent.map(\.reference) == [history] }
    precondition(resumedHistory)
    open(); _ = workspace.presentation.switchPage(.images)
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["sidebar-recent-confirmation-is-revoked-by-navigation"] = commands.admittedWrites == 1
        && controller.snapshot.recent.map(\.reference) == [history] && workspace.presentation.page == .images
    _ = workspace.presentation.switchPage(.videos)
    _ = workspace.presentation.setSelection([reference], focused: reference, isSelecting: true)
    open(); _ = workspace.presentation.setSelection([], isSelecting: false)
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["sidebar-recent-confirmation-is-revoked-by-a-new-selection-session"] = commands.admittedWrites == 1
        && controller.snapshot.recent.map(\.reference) == [history] && workspace.presentation.selectionState.references.isEmpty
    open()
    try await controller.reset()
    controller.recordSuccessfulUse(reference, locator: nil, sequence: 1)
    let resetHistory = await wait { controller.snapshot.recent.map(\.reference) == [reference] }
    precondition(resetHistory)
    workspace.publish(catalog)
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["sidebar-recent-confirmation-cannot-clear-history-from-a-new-reset-epoch"] = commands.admittedWrites == 1
        && controller.snapshot.recent.map(\.reference) == [reference] && workspace.presentation.lastError == nil
    return checks
}
