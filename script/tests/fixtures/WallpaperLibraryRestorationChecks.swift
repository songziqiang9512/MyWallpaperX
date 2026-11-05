@MainActor private final class RemovalCatalog {
    var catalog: WallpaperLibraryCatalog { didSet { didChange?() } }
    var didChange: (() -> Void)?
    var refreshes = 0
    init(_ catalog: WallpaperLibraryCatalog) { self.catalog = catalog }
    func refreshAvailability() { refreshes += 1 }
    // ACTUAL_DOWNLOAD_HIDES
}
@MainActor private final class RemovalWorkspace {
    let collections: UserCollectionsController?
    let presentation: WallpaperLibraryPresentation
    let catalog: RemovalCatalog
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    var edited: [WallpaperLibraryPage] = []
    init(_ collections: UserCollectionsController, _ catalog: WallpaperLibraryCatalog, defaults: UserDefaults) {
        self.collections = collections; self.catalog = RemovalCatalog(catalog)
        presentation = WallpaperLibraryPresentation(collections: collections, defaults: defaults)
        presentation.update(catalog: catalog, relationships: collections.snapshot)
        self.catalog.didChange = { [weak self] in
            guard let self else { return }
            self.presentation.update(catalog: self.catalog.catalog, relationships: self.relationships)
        }
    }
    // ACTUAL_HIDE_REVISIONS
    func publish(_ next: WallpaperLibraryCatalog) {
        var merged = next
        merged.sessionHiddenDownloadReferences = catalog.catalog.sessionHiddenDownloadReferences
        catalog.catalog = merged
        presentation.update(catalog: merged, relationships: relationships)
    }
    func didEditMembers(of page: WallpaperLibraryPage) {
        edited.append(page)
        presentation.update(catalog: catalog.catalog, relationships: relationships)
    }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        try WallpaperLibraryQuery.resolve([reference], catalog: catalog.catalog, relationships: relationships)[0]
    }
}
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
    func hidden() -> Bool { workspace.catalog.catalog.sessionHiddenDownloadReferences.contains(ref) }
    func settle() async { try? await Task.sleep(nanoseconds: 30_000_000); _ = await collections.flush() }
    workspace.catalog.hideDownloads([ref])
    workspace.didEditMembers(of: .downloads)
    let restore = commands!.makeRestoreLibraryAction(for: item)
    restore?(); await settle()
    let bytes = try Data(contentsOf: url)
    checks["restore-existing-download-has-a-real-command-with-no-transfer-or-playback"] = restore != nil && !hidden()
        && bytes == Data([9, 8, 7]) && commands!.steam.requested.isEmpty && commands!.pixabay.requested.isEmpty
        && workspace.presentation.queryResult.items.map(\.reference) == [ref]
    workspace.catalog.hideDownloads([ref])
    let held = commands!.makeRestoreLibraryAction(for: item)
    workspace.catalog.hideDownloads([ref])
    let newer = try workspace.libraryHideRevisions(for: [ref], downloads: true)
    held?(); await settle()
    let current = try workspace.libraryHideRevisions(for: [ref], downloads: true)
    checks["held-restore-cannot-clear-a-newer-hide-of-the-same-reference"] = hidden()
        && current == newer
    let oldPage = commands!.makeRestoreLibraryAction(for: item)
    workspace.presentation.switchPage(.favorites); oldPage?(); await settle()
    checks["restore-menu-cannot-borrow-another-page-or-selection-session"] = hidden()
    workspace.presentation.switchPage(.downloads)
    let receipt = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    weak var released: RemovalCommands? = nil
    released = commands
    commands = nil; receipt?(); await settle()
    checks["accepted-download-success-restores-after-the-originating-window-commands-are-released"] = released == nil && !hidden()
    workspace.catalog.hideDownloads([ref])
    let withoutWindowCommands = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    withoutWindowCommands?(); await settle()
    checks["runtime-factory-admits-restoration-with-no-window-commands-instance"] = commands == nil
        && released == nil && withoutWindowCommands != nil && !hidden()
    commands = RemovalCommands(workspace)
    let notHiddenAtAdmission = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    workspace.catalog.hideDownloads([ref])
    let lateHide = workspace.catalog.catalog.sessionHiddenDownloadReferences
    notHiddenAtAdmission?(); await settle()
    checks["download-admitted-before-a-hide-does-not-resurrect-its-later-completion"] = workspace.catalog.catalog.sessionHiddenDownloadReferences == lateHide
    let beforeReset = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)
    try await collections.reset()
    workspace.catalog.hideDownloads([ref])
    let resetHide = workspace.catalog.catalog.sessionHiddenDownloadReferences
    beforeReset?(); await settle()
    checks["download-success-from-the-previous-reset-epoch-cannot-restore-new-library-state"] = workspace.catalog.catalog.sessionHiddenDownloadReferences == resetHide
    RemovalCommands.makeExplicitLibraryRestorationReceipt(for: ref, in: workspace)?()
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
    let alias = WallpaperReference(provider: .videoLibrary, sourceID: "download-alias")
    workspace.catalog.hideDownloads([alias])
    let aliasReceipt = RemovalCommands.makeExplicitLibraryRestorationReceipt(for: alias, in: workspace, downloads: true)
    _ = try await collections.perform(.linkAlias(.init(alias: alias, canonical: ref, proof: .publishedDownload), Date()))
    aliasReceipt?()
    checks["admitted-session-restore-follows-the-original-query-alias-authority"] = workspace.catalog.catalog.sessionHiddenDownloadReferences.isEmpty
    for provider in [WallpaperProvider.steamWorkshop, .pixabay, .wallhaven, .pixiv] {
        let reference = WallpaperReference(provider: provider, sourceID: provider == .pixiv ? "kept:p0" : "kept")
        let row = WallpaperContentItem(reference: reference, providerReference: reference, locator: item.locator,
            title: item.title, kind: item.kind, publishedAvailability: item.publishedAvailability,
            capabilities: item.capabilities, metadata: item.metadata, acquisition: item.acquisition, update: item.update, aliases: [])
        let database = root.appendingPathComponent("session-hide-" + provider.rawValue + ".sqlite3")
        let sourceStore = UserCollectionsStore(url: database)
        let sourceCollections = UserCollectionsController(store: sourceStore, snapshot: try await sourceStore.snapshot())
        let source = WallpaperLibraryCatalog(downloads: [row], revision: 1)
        let view = RemovalWorkspace(sourceCollections, source, defaults: defaults)
        view.presentation.switchPage(.downloads)
        view.presentation.setSelection([reference], focused: reference)
        let command = RemovalCommands(view)
        command.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
        let deadline = Date().addingTimeInterval(3)
        while view.edited.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
        checks["download-hide-is-ephemeral-and-does-not-call-source-delete-" + provider.rawValue] = !view.edited.isEmpty
            && view.catalog.catalog.sessionHiddenDownloadReferences == [reference]
            && sourceCollections.snapshot.excludedLibraryReferences.isEmpty && view.presentation.queryResult.items.isEmpty
            && command.steam.requested.isEmpty && command.pixabay.requested.isEmpty
        view.publish(source)
        checks["same-owner-source-rescan-does-not-undo-hide-" + provider.rawValue] = view.presentation.queryResult.items.isEmpty
        _ = try await sourceCollections.perform(.setLibraryExcluded([reference], true))
        let freshStore = UserCollectionsStore(url: database)
        let fresh = UserCollectionsController(store: freshStore, snapshot: try await freshStore.snapshot())
        let reopened = RemovalWorkspace(fresh, source, defaults: defaults)
        reopened.presentation.switchPage(.downloads)
        checks["fresh-app-owner-restores-retained-file-even-with-old-sql-hide-" + provider.rawValue] = reopened.presentation.queryResult.items.map(\.reference) == [reference]
            && reopened.catalog.catalog.sessionHiddenDownloadReferences.isEmpty && FileManager.default.fileExists(atPath: url.path)
    }
    return checks
}
