// Real Commands/Presentation/PlaylistOrganizationActions/SQLite completion.
// Draft UI and native alerts are controlled leaves; no App window is shown.
import SQLite3
@MainActor private enum WallpaperLibrarySheetPresentation {
    static func permitsInput(in window: NSWindow?) -> Bool { true }
}

@MainActor private final class WallpaperPlaylistEditorController {
    static weak var current: WallpaperPlaylistEditorController?
    var onClose: (() -> Void)?
    var onSaved: ((UUID) -> Void)?
    private let collections: UserCollectionsController
    private let members: [WallpaperOrganizationItem]
    private let epoch: UUID
    init(collections: UserCollectionsController, playlist: WallpaperPlaylist?, members: [WallpaperOrganizationItem],
         automaticImage: NSImage?, permitsEditing: @escaping () -> Bool,
         availabilityChanges: AnyPublisher<Void, Never>?, hostWindow: @escaping () -> NSWindow?) {
        self.collections = collections; self.members = members; epoch = collections.snapshot.resetEpoch
    }
    func show() { Self.current = self }
    func close() { onClose?() }
    func save(name: String) async throws -> UUID {
        let id = try await collections.createPlaylist(metadata: .init(name: name), members: members, expectedEpoch: epoch)
        onSaved?(id); close()
        return id
    }
}

@MainActor private func runOrganizationCompletionChecks(root: URL) async throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let databaseURL = root.appendingPathComponent("organization-completion.sqlite3")
    let store = UserCollectionsStore(url: databaseURL)
    let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
    let suite = "mwx.organization.completion." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let refs = ["complete-a", "complete-b", "complete-c"].map { WallpaperReference(provider: .videoLibrary, sourceID: $0) }
    let items = refs.map {
        WallpaperContentItem(reference: $0, providerReference: $0, locator: .init(mediaKind: .video), title: $0.sourceID,
            kind: .video, publishedAvailability: .available, capabilities: [.organize], metadata: .init(),
            acquisition: .idle, update: .idle, aliases: [])
    }
    let catalog = WallpaperLibraryCatalog(videos: items, revision: 1)
    let view = RemovalWorkspace(controller, catalog, defaults: defaults)
    let commands = RemovalCommands(view)
    func select(_ references: Set<WallpaperReference>? = nil) {
        let selected = references ?? Set(refs.prefix(2))
        view.presentation.setSelection(selected, focused: refs.first(where: { selected.contains($0) }), isSelecting: true)
    }
    func publish() { view.presentation.update(catalog: view.catalog.catalog, relationships: controller.snapshot) }
    func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        return condition()
    }
    func invoke(_ item: NSMenuItem) { _ = NSApp.sendAction(item.action!, to: item.target, from: item) }
    let undo = WallpaperLibraryRelationshipUndo(collections: controller,
        report: { view.presentation.report($0) }, didRestore: { publish() })

    select()
    let beforeFavorite = view.presentation.selectionState
    commands.toggleFavorite()
    checks["multi-favorite-keeps-fixed-targets-until-transaction-completes"] = view.presentation.selectionState == beforeFavorite
    checks["successful-favorite-exits-multi-and-keeps-current-focus"] = await wait {
        controller.snapshot.favorites.count == 2 && !view.presentation.selectionState.isSelecting
    } && view.presentation.selectionState.references == [refs[0]] && view.presentation.selectionState.focusedReference == refs[0]
    while undo.undoManager.groupingLevel > 0 { undo.undoManager.endUndoGrouping() }
    undo.undoManager.undo()
    checks["organization-undo-restores-relationships-without-reopening-completed-multi"] = await wait {
        controller.snapshot.favorites.isEmpty && !undo.undoManager.isApplyingTransaction
    } && !view.presentation.selectionState.isSelecting && view.presentation.selectionState.references == [refs[0]]
    undo.undoManager.redo()
    checks["organization-redo-keeps-completed-selection-mode-off"] = await wait {
        controller.snapshot.favorites.count == 2 && !undo.undoManager.isApplyingTransaction
    } && !view.presentation.selectionState.isSelecting

    view.presentation.switchPage(.favorites); publish(); select()
    commands.toggleFavorite()
    checks["successful-unfavorite-exits-after-internal-selection-reconciliation"] = await wait {
        controller.snapshot.favorites.isEmpty && !view.presentation.selectionState.isSelecting
    }
    publish()
    checks["unfavorite-projection-keeps-completed-mode-off"] = view.presentation.selectionState.references.isEmpty
        && !view.presentation.selectionState.isSelecting

    view.presentation.switchPage(.videos); select()
    let beforeNewIntentEdit = view.edited.count
    commands.toggleFavorite()
    view.presentation.setSelection([refs[2]], focused: refs[2], isSelecting: true)
    let newIntent = view.presentation.selectionState
    checks["favorite-completion-does-not-exit-newer-multi-selection"] = await wait {
        controller.snapshot.favorites.count == 2 && view.edited.count == beforeNewIntentEdit + 1
    }
        && view.presentation.selectionState == newIntent

    select()
    let beforeReturnEdit = view.edited.count
    commands.toggleFavorite()
    view.presentation.switchPage(.images); view.presentation.switchPage(.videos); select([refs[2]])
    let returned = view.presentation.selectionState
    checks["favorite-completion-cannot-clear-returned-page-session"] = await wait {
        controller.snapshot.favorites.isEmpty && view.edited.count == beforeReturnEdit + 1
    }
        && view.presentation.selectionState == returned

    // A real failed SQLite transaction must preserve both durable state and
    // the admitted targets, rather than merely reject at a controlled leaf.
    var database: OpaquePointer?
    precondition(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    precondition(sqlite3_exec(database, "CREATE TRIGGER reject_favorite BEFORE INSERT ON favorites BEGIN SELECT RAISE(ABORT,'fixture write failed'); END", nil, nil, nil) == SQLITE_OK)
    select()
    let failedFavorite = view.presentation.selectionState, failedRevision = controller.snapshot.revision
    commands.toggleFavorite()
    checks["failed-favorite-sql-write-preserves-multi-selection-and-reports-error"] = await wait {
        view.presentation.lastError != nil
    } && view.presentation.selectionState == failedFavorite && controller.snapshot.revision == failedRevision
        && controller.snapshot.favorites.isEmpty
    precondition(sqlite3_exec(database, "DROP TRIGGER reject_favorite", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let destination = try await controller.createPlaylist(name: "Destination")
    publish(); select()
    let menu = commands.makePlaylistMenu()!
    let add = menu.items.first { $0.title == "Destination" }!
    let beforeAdd = view.presentation.selectionState
    invoke(add)
    checks["add-menu-preserves-selection-before-real-store-completion"] = view.presentation.selectionState == beforeAdd
    checks["add-to-existing-list-completes-multi-through-real-action-owner"] = await wait {
        controller.snapshot.members.filter { $0.playlistID == destination }.count == 2
            && !view.presentation.selectionState.isSelecting
    } && view.presentation.selectionState.references == [refs[0]]

    select()
    invoke(commands.makePlaylistMenu()!.items.first { $0.title == "Destination" }!)
    checks["already-present-add-is-a-successful-operation-and-exits-multi"] = await wait {
        !view.presentation.selectionState.isSelecting
    } && controller.snapshot.members.filter { $0.playlistID == destination }.count == 2

    select()
    let vanished = commands.makePlaylistMenu()!.items.first { $0.title == "Destination" }!
    try await controller.perform(.deletePlaylist(destination))
    let failedSelection = view.presentation.selectionState
    RecentAlertProbe.alert = nil
    invoke(vanished)
    checks["failed-add-reports-error-without-exiting-or-losing-targets"] = await wait {
        RecentAlertProbe.alert?.title == "播放列表操作未完成"
    } && view.presentation.selectionState == failedSelection
        && !controller.snapshot.playlists.contains { $0.id == destination }

    select()
    invoke(commands.makePlaylistMenu()!.items.last!)
    let draftSelection = view.presentation.selectionState
    checks["new-list-draft-does-not-finish-multi-on-opening"] = WallpaperPlaylistEditorController.current != nil
        && view.presentation.selectionState == draftSelection
    WallpaperPlaylistEditorController.current!.close()
    checks["cancel-new-list-leaves-current-multi-untouched"] = view.presentation.selectionState == draftSelection
    invoke(commands.makePlaylistMenu()!.items.last!)
    let created = try await WallpaperPlaylistEditorController.current!.save(name: "Created from members")
    checks["new-list-save-finishes-multi-only-after-durable-member-creation"] = !view.presentation.selectionState.isSelecting
        && controller.snapshot.members.filter { $0.playlistID == created }.map(\.reference) == Array(refs.prefix(2))

    publish(); view.presentation.switchPage(.playlist(created)); select()
    let beforeRemoval = view.presentation.selectionState
    commands.remove(); RecentAlertProbe.finish(.alertSecondButtonReturn)
    checks["cancel-real-batch-removal-keeps-full-multi-selection"] = view.presentation.selectionState == beforeRemoval
        && controller.snapshot.members.filter { $0.playlistID == created }.count == 2
    commands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["real-batch-list-removal-finishes-multi-after-durable-projection"] = await wait {
        controller.snapshot.members.filter { $0.playlistID == created }.isEmpty
            && view.presentation.queryResult.items.isEmpty && !view.presentation.selectionState.isSelecting
    } && view.presentation.selectionState.references.isEmpty
    view.presentation.switchPage(.videos)

    // The same receipt tracks legitimate projection reconciliation, while
    // explicit selection/page/reset changes revoke it through the old owner.
    select()
    let receipt = view.presentation.beginOrganizationOperation(Set(refs.prefix(2)))
    let reconciliationSession = view.presentation.selectionState.sessionID
    let unavailable = WallpaperLibraryCatalog(videos: [items[1], items[2]], revision: 2)
    view.publish(unavailable)
    checks["internal-projection-actually-changes-selection-session"] = view.presentation.selectionState.sessionID != reconciliationSession
        && view.presentation.selectionState.references == [refs[1]] && view.presentation.selectionState.isSelecting
    view.presentation.completeOrganizationOperation(receipt, succeeded: true)
    checks["completion-follows-own-projection-session-and-keeps-surviving-focus"] = !view.presentation.selectionState.isSelecting
        && view.presentation.selectionState.references == [refs[1]] && view.presentation.selectionState.focusedReference == refs[1]

    view.publish(.init(videos: items, revision: 3)); select()
    let failed = view.presentation.beginOrganizationOperation(Set(refs.prefix(2)))
    let original = view.presentation.selectionState
    view.presentation.completeOrganizationOperation(failed, succeeded: false)
    checks["failed-organization-completion-preserves-full-original-selection"] = view.presentation.selectionState == original
    let unrelated = view.presentation.beginOrganizationOperation([refs[2]])
    view.presentation.completeOrganizationOperation(unrelated, succeeded: true)
    checks["unrelated-single-card-action-cannot-end-another-multi-selection"] = view.presentation.selectionState == original

    let removal = view.presentation.beginRemoval(Set(refs.prefix(2)), from: .videos)
    view.presentation.completeRemoval(removal, succeeded: Set(refs.prefix(2)))
    checks["successful-removal-waits-for-real-projection-before-finishing-multi"] = view.presentation.selectionState == original
    view.publish(.init(videos: [items[2]], revision: 4))
    checks["fully-successful-removal-exits-multi-after-actual-source-absence"] = !view.presentation.selectionState.isSelecting
        && view.presentation.selectionState.references.isEmpty

    view.publish(.init(videos: items, revision: 5)); select()
    controller.recordSuccessfulUse(refs[0], locator: nil, sequence: 1)
    controller.recordSuccessfulUse(refs[1], locator: nil, sequence: 2)
    let recordedHistory = await wait { controller.snapshot.recent.count == 2 }
    precondition(recordedHistory)
    publish(); view.presentation.switchPage(.recent); select()
    let beforeRecent = view.presentation.selectionState
    invoke(commands.makeRecentMenu()!.items[0]); RecentAlertProbe.finish(.alertSecondButtonReturn)
    checks["cancel-clear-recent-keeps-multi-selection-and-history"] = view.presentation.selectionState == beforeRecent
        && controller.snapshot.recent.count == 2
    invoke(commands.makeRecentMenu()!.items[0])
    view.presentation.switchPage(.videos); select()
    let behindConfirmation = view.presentation.selectionState
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["recent-confirmation-never-borrows-another-pages-same-reference-selection"] = controller.snapshot.recent.count == 2
        && view.presentation.selectionState == behindConfirmation
    view.presentation.switchPage(.recent); select()
    let heldRecent = commands.makeRecentMenu()!.items[0]
    view.presentation.switchPage(.videos); select()
    RecentAlertProbe.alert = nil
    invoke(heldRecent)
    checks["held-recent-menu-cannot-start-a-new-command-on-another-page"] = RecentAlertProbe.alert == nil
        && controller.snapshot.recent.count == 2 && view.presentation.selectionState.isSelecting
    view.presentation.switchPage(.recent); select()
    invoke(commands.makeRecentMenu()!.items[0]); RecentAlertProbe.finish(.alertFirstButtonReturn)
    checks["successful-clear-recent-finishes-multi-after-real-store-write"] = await wait {
        controller.snapshot.recent.isEmpty && !view.presentation.selectionState.isSelecting
    }

    view.presentation.switchPage(.videos); select()
    let preReset = view.presentation.beginOrganizationOperation(Set(refs.prefix(2)))
    try await controller.reset()
    publish()
    select([refs[2]])
    let resetSelection = view.presentation.selectionState
    view.presentation.completeOrganizationOperation(preReset, succeeded: true)
    checks["organization-completion-from-old-reset-never-clears-new-selection"] = view.presentation.selectionState == resetSelection

    let lateActions = PlaylistOrganizationActions(collections: controller, hostWindow: { nil })
    RecentAlertProbe.alert = nil
    lateActions.add([items[0].organizationItem], to: created)
    try await controller.reset()
    await Task.yield()
    checks["old-epoch-playlist-failure-does-not-present-error-in-new-library"] = RecentAlertProbe.alert == nil
    return checks
}
