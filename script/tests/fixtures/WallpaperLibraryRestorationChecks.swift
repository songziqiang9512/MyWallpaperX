// Appended to the existing real-Commands/SQLite harness by its driver. The
// source leaves only record calls; exclusion/query/receipt methods are product.
@MainActor private func runLibraryRestorationChecks(root: URL) async throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let store = UserCollectionsStore(url: root.appendingPathComponent("explicit-restoration.sqlite3"))
    let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
    let ref = WallpaperReference(provider: .pixabay, sourceID: "90")
    let url = root.appendingPathComponent("kept-download.mp4"); try Data([9, 8, 7]).write(to: url)
    let item = WallpaperContentItem(reference: ref, providerReference: ref, locator: .init(path: url.path, mediaKind: .video),
        title: "Retained download", kind: .video, publishedAvailability: .available, capabilities: [.play, .organize],
        metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    let suite = "mwx.restore." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let workspace = RemovalWorkspace(collections, .init(downloads: [item], revision: 1), defaults: defaults)
    workspace.presentation.switchPage(.downloads)
    var commands: RemovalCommands? = RemovalCommands(workspace)
    func hidden() -> Bool { collections.snapshot.excludedLibraryReferences.contains { $0.reference == ref } }
    func settle() async { try? await Task.sleep(nanoseconds: 30_000_000); _ = await collections.flush() }
    try await collections.perform(.setLibraryExcluded([ref], true))
    workspace.didEditMembers(of: .downloads)
    let restore = commands!.makeRestoreLibraryAction(for: item)
    restore?(); await settle()
    let bytes = try Data(contentsOf: url)
    checks["restore-existing-download-has-a-real-command-with-no-transfer-or-playback"] = restore != nil && !hidden()
        && bytes == Data([9, 8, 7]) && commands!.steam.requested.isEmpty && commands!.pixabay.requested.isEmpty
        && workspace.presentation.queryResult.items.map(\.reference) == [ref]
    try await collections.perform(.setLibraryExcluded([ref], true))
    let held = commands!.makeRestoreLibraryAction(for: item)
    try await collections.perform(.setLibraryExcluded([ref], true))
    let newer = collections.snapshot.excludedLibraryReferences
    held?(); await settle()
    checks["held-restore-cannot-clear-a-newer-hide-of-the-same-reference"] = hidden() && collections.snapshot.excludedLibraryReferences == newer
    let oldPage = commands!.makeRestoreLibraryAction(for: item)
    workspace.presentation.switchPage(.favorites); oldPage?(); await settle()
    checks["restore-menu-cannot-borrow-another-page-or-selection-session"] = hidden()
    workspace.presentation.switchPage(.downloads)
    let receipt = commands!.makeExplicitLibraryRestorationReceipt(for: ref)
    weak var released: RemovalCommands? = nil
    released = commands
    commands = nil; receipt?(); await settle()
    checks["accepted-download-success-persists-after-the-originating-window-commands-are-released"] = released == nil && !hidden()
    try await collections.perform(.setLibraryExcluded([ref], true))
    let withoutWindowCommands = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    withoutWindowCommands?(); await settle()
    checks["runtime-factory-admits-restoration-with-no-window-commands-instance"] = commands == nil
        && released == nil && withoutWindowCommands != nil && !hidden()
    commands = RemovalCommands(workspace)
    let notHiddenAtAdmission = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    try await collections.perform(.setLibraryExcluded([ref], true))
    let lateHide = collections.snapshot.excludedLibraryReferences
    notHiddenAtAdmission?(); await settle()
    checks["download-admitted-before-a-hide-does-not-resurrect-its-later-completion"] = collections.snapshot.excludedLibraryReferences == lateHide
    let beforeReset = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    try await collections.reset()
    try await collections.perform(.setLibraryExcluded([ref], true))
    let resetHide = collections.snapshot.excludedLibraryReferences
    beforeReset?(); await settle()
    checks["download-success-from-the-previous-reset-epoch-cannot-restore-new-library-state"] = collections.snapshot.excludedLibraryReferences == resetHide
    try await collections.perform(.setLibraryExcluded([ref], false))
    workspace.didEditMembers(of: .downloads)
    var sourceBindingIsCurrent = true
    let menu = commands!.makePlaylistMenu([ref], permitsAction: { sourceBindingIsCurrent })
    let leaf = menu?.items.last
    let organizationBefore = collections.snapshot.organizationState
    let hadNoDraft = WallpaperPlaylistEditorController.current == nil
    sourceBindingIsCurrent = false
    if let leaf, let action = leaf.action { _ = NSApplication.shared.sendAction(action, to: leaf.target, from: leaf) }
    checks["native-playlist-submenu-leaf-rechecks-the-provider-binding-before-executing"] = leaf != nil && hadNoDraft
        && WallpaperPlaylistEditorController.current == nil && collections.snapshot.organizationState == organizationBefore
    sourceBindingIsCurrent = true
    if let leaf, let action = leaf.action { _ = NSApplication.shared.sendAction(action, to: leaf.target, from: leaf) }
    let created = try await WallpaperPlaylistEditorController.current?.save(name: "Fixed provider binding")
    checks["native-playlist-submenu-leaf-keeps-its-original-fixed-reference"] = created.map { id in
        collections.snapshot.members.filter { $0.playlistID == id }.map(\.reference) == [ref]
    } == true
    return checks
}
