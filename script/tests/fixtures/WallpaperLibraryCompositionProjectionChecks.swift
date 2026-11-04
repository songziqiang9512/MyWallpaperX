// App projection work uses the actual Composition method and signature. The
// source-snapshot leaf records its inputs; the real Workspace constructor has
// its own gate. No native view, source scan or renderer is started here.
@MainActor private final class ProjectionPresentation {
    var errors = 0
    func report(_ error: Error) { errors += 1 }
}

@MainActor private final class ProjectionWorkspace {
    let presentation = ProjectionPresentation()
    var captures = 0
    var shouldFail = false
    var capturedReferences: [WallpaperReference] = []
    func capturePlaybackSnapshot(for reference: WallpaperReference,
        resolvedProjection: (catalogRevision: UInt64, relationshipsRevision: Int64, resetEpoch: UUID, items: [WallpaperContentItem])?
    ) throws -> WallpaperPlaybackSequence.Snapshot {
        captures += 1
        if shouldFail { throw CocoaError(.fileReadUnknown) }
        capturedReferences = resolvedProjection?.items.map(\.reference) ?? []
        return try .init(source: .page(.videos), revision: resolvedProjection?.catalogRevision ?? 0, entries: [])
    }
}

@MainActor private final class ProjectionComposition {
    let workspace = ProjectionWorkspace()
    let manager = WallpaperManager()
    var commands: WallpaperLibraryCommands!
    lazy var inspectorPrimaryFactory: (WallpaperContentItem) -> (() -> Void)? = // ACTUAL_INSPECTOR_PRIMARY_FACTORY
    var downloadedContentWrites = 0
    var downloadedContent: [WallpaperReference: WallpaperContentItem] = [:] { didSet { downloadedContentWrites += 1 } }
    var cardState: WallpaperLibraryCardStateProjection?
    var playlistNamesWrites = 0
    var playlistNames: [WallpaperReference: [String]] = [:] { didSet { playlistNamesWrites += 1 } }
    var sourceSnapshotWrites = 0
    var sourceSnapshot: WallpaperPlaybackSequence.Snapshot? { didSet { sourceSnapshotWrites += 1 } }

    func prepare(_ state: WallpaperLibraryPresentationState, catalog: WallpaperLibraryCatalog,
                 relationships: UserCollectionsSnapshot, signature: RenderSignature, previous: RenderSignature?) {
        prepareCardState(state, catalog: catalog, relationships: relationships, signature: signature, previousSignature: previous)
    }
    // ACTUAL_CARD_STATE_PREPARATION
}

@MainActor private func runCompositionProjectionChecks(_ checks: inout [String: Bool]) throws {
    let selection = WallpaperLibrarySelectionState(), epoch = UUID()
    func oldSignature(_ projection: UInt64, canEdit: Bool = true, notice: String? = nil,
                      error: String? = nil, errorEvent: UInt64 = 0) -> RenderSignature {
        .init(page: .videos, query: .init(), items: [], selection: selection, catalogRevision: 2, projectionRevision: projection,
            relationshipsRevision: 7, resetEpoch: epoch, sequenceReference: nil, sequenceTicket: nil, ticket: nil,
            pendingReference: nil, pendingSequenceTicket: nil, pendingRuntimeTicket: nil, canEdit: canEdit,
            recoveryNotice: notice, operationError: error, operationErrorEvent: errorEvent, visible: true)
    }
    checks["late-accepted-projection-is-distinct-from-early-render-of-same-source-revision"] = oldSignature(1) != oldSignature(2)
    checks["render-signature-still-recognizes-identical-echo-and-editing-errors"] = oldSignature(2) == oldSignature(2)
        && oldSignature(2) != oldSignature(2, canEdit: false) && oldSignature(2) != oldSignature(2, notice: "Read-only recovery")
    checks["operation-error-is-not-masked-by-an-unchanged-recovery-notice-in-render-signature"] =
        oldSignature(2, notice: "Read-only recovery") != oldSignature(2, notice: "Read-only recovery", error: "Rename failed")
        && oldSignature(2, notice: "Read-only recovery", error: "Rename failed") != oldSignature(2, notice: "Read-only recovery", error: "Add failed")
        && oldSignature(2, error: "Rename failed", errorEvent: 1) != oldSignature(2, error: "Rename failed", errorEvent: 2)

    let a = WallpaperReference(provider: .videoLibrary, sourceID: "projection-A")
    let b = WallpaperReference(provider: .videoLibrary, sourceID: "projection-B")
    let download = WallpaperReference(provider: .steamWorkshop, sourceID: "projection-download")
    func content(_ reference: WallpaperReference, title: String? = nil) -> WallpaperContentItem {
        .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
            title: title ?? reference.sourceID, kind: .video, publishedAvailability: .available,
            capabilities: [.play, .organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    var state = WallpaperLibraryPresentationState()
    state.queryResult = .init(items: [content(a), content(b)], unfilteredCount: 2)
    let relationships = UserCollectionsSnapshot(revision: 7, resetEpoch: epoch, migrationManifestID: nil,
        playlists: [], members: [], favorites: [.init(reference: a, favoritedAt: nil)], recent: [], aliases: [], locators: [])
    var catalog = WallpaperLibraryCatalog(videos: state.queryResult.items, downloads: [content(download)], revision: 2)
    func signature(_ state: WallpaperLibraryPresentationState, catalogRevision: UInt64 = 2, projectionRevision: UInt64 = 3,
                   relationshipsRevision: Int64 = 7, resetEpoch: UUID? = nil, sequenceReference: WallpaperReference? = nil,
                   sequenceTicket: PlaybackSwitchTicket? = nil, runtimeTicket: PlaybackSwitchTicket? = nil,
                   pendingReference: WallpaperReference? = nil, pendingSequenceTicket: PlaybackSwitchTicket? = nil,
                   pendingRuntimeTicket: PlaybackSwitchTicket? = nil,
                   canEdit: Bool = true, notice: String? = nil, error: String? = nil, visible: Bool = true) -> RenderSignature {
        .init(page: state.page, query: state.query, items: state.queryResult.items, selection: state.selectionState,
            catalogRevision: catalogRevision, projectionRevision: projectionRevision, relationshipsRevision: relationshipsRevision,
            resetEpoch: resetEpoch ?? epoch, sequenceReference: sequenceReference, sequenceTicket: sequenceTicket,
            ticket: runtimeTicket, pendingReference: pendingReference, pendingSequenceTicket: pendingSequenceTicket,
            pendingRuntimeTicket: pendingRuntimeTicket, canEdit: canEdit, recoveryNotice: notice,
            operationError: error ?? state.lastError, operationErrorEvent: state.lastErrorEvent, visible: visible)
    }
    let errorSuite = "mwx.composition-error-events." + UUID().uuidString
    let errorDefaults = UserDefaults(suiteName: errorSuite)!
    defer { errorDefaults.removePersistentDomain(forName: errorSuite) }
    let errorPresentation = WallpaperLibraryPresentation(collections: nil, defaults: errorDefaults)
    let repeatedError = NSError(domain: "composition-error", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repeated failure"])
    errorPresentation.report(repeatedError)
    let firstError = signature(errorPresentation.state)
    errorPresentation.report(repeatedError)
    let nextError = signature(errorPresentation.state)
    checks["real-repeated-error-report-refreshes-ui-without-invalidating-card-inputs"] = firstError.operationError == nextError.operationError
        && nextError.operationErrorEvent == firstError.operationErrorEvent &+ 1 && firstError != nextError
        && nextError == signature(errorPresentation.state)
    let first = signature(state)
    let composition = ProjectionComposition()
    let before = WallpaperLibraryQuery.resolverInitializationCount
    composition.prepare(state, catalog: catalog, relationships: relationships, signature: first, previous: nil)
    let built = WallpaperLibraryQuery.resolverInitializationCount
    checks["composition-first-batch-really-resolves-and-captures-once"] = built == before + 2
        && composition.workspace.captures == 1 && composition.workspace.capturedReferences == [a, b]
        && composition.downloadedContent[download]?.reference == download && composition.cardState?.isFavorite(a) == true

    state.selectionState.references = [b]; state.selectionState.focusedReference = b; state.selectionState.sessionID = UUID()
    let selected = signature(state)
    composition.prepare(state, catalog: catalog, relationships: relationships, signature: selected, previous: first)
    checks["selection-session-refresh-reuses-only-the-successful-data-projection"] = selected != first
        && WallpaperLibraryQuery.resolverInitializationCount == built && composition.workspace.captures == 1
    state.query.preferredColumns = 6; state.query.scrollAnchor = b; state.query.scrollOffset = -13; state.query.scrollAtTop = false
    let scrolled = signature(state)
    composition.prepare(state, catalog: catalog, relationships: relationships, signature: scrolled, previous: selected)
    checks["view-only-density-and-scroll-do-not-rebuild-playback-or-card-data"] = WallpaperLibraryQuery.resolverInitializationCount == built
        && composition.workspace.captures == 1

    let source = try WallpaperPlaybackSequence.Snapshot(source: .page(.videos), revision: 1, entries: [])
    let remoteWorkspace = RemoteWorkspace(relationships)
    remoteWorkspace.presentation.page = .videos
    let commands = WallpaperLibraryCommands(composition.manager, CommandWorkspace(composition.manager, source))
    let remote = RemoteComposition(remoteWorkspace, commands)
    remote.cardState = composition.cardState
    let oldAction = remote.favorite(content(a))!
    remoteWorkspace.presentation.selectionState.sessionID = UUID()
    let currentAction = remote.favorite(content(a))!
    oldAction()
    let oldWasRejected = commands.favoriteActions.isEmpty
    currentAction()
    checks["reused-data-keeps-current-session-actions-and-revokes-the-old-factory-result"] = oldWasRejected
        && commands.favoriteActions == [[a]] && WallpaperLibraryQuery.resolverInitializationCount == built

    var changed = state
    changed.queryResult = .init(items: [content(b), content(a)], unfilteredCount: 2)
    let reorderedInvalidates = signature(changed) != scrolled
    changed.queryResult = .init(items: [content(a, title: "Changed metadata"), content(b)], unfilteredCount: 2)
    let metadataSignature = signature(changed)
    catalog.videos = changed.queryResult.items
    composition.prepare(changed, catalog: catalog, relationships: relationships, signature: metadataSignature, previous: scrolled)
    checks["actual-order-or-same-id-metadata-invalidates-card-data"] = reorderedInvalidates
        && metadataSignature != scrolled && composition.workspace.captures == 2
        && WallpaperLibraryQuery.resolverInitializationCount == built + 2
    changed = state; changed.page = .favorites
    let ticket = PlaybackSwitchTicket(epoch: 42, id: UUID(), runtime: .video)
    let ownerChanges: [Bool] = [
        signature(changed) != scrolled,
        signature(state, catalogRevision: 4) != scrolled,
        signature(state, projectionRevision: 4) != scrolled,
        signature(state, relationshipsRevision: 8) != scrolled,
        signature(state, resetEpoch: UUID()) != scrolled,
        signature(state, sequenceReference: a) != scrolled,
        signature(state, sequenceTicket: ticket) != scrolled,
        signature(state, runtimeTicket: ticket) != scrolled,
        signature(state, pendingReference: b) != scrolled,
        signature(state, pendingSequenceTicket: ticket) != scrolled,
        signature(state, pendingRuntimeTicket: ticket) != scrolled]
    checks["card-data-key-retains-all-owner-revisions-epoch-and-playback-identities"] = ownerChanges.allSatisfy { $0 }
    var queryVariants = [WallpaperLibraryQueryState]()
    var query = state.query; query.search = "Changed"; queryVariants.append(query)
    query = state.query; query.providers = [.pixabay, .steamWorkshop]; queryVariants.append(query)
    query = state.query; query.kinds = [.image, .video]; queryVariants.append(query)
    query = state.query; query.statuses = [.unavailable, .failed]; queryVariants.append(query)
    query = state.query; query.sort = .name; queryVariants.append(query)
    query = state.query; query.ascending = false; queryVariants.append(query)
    query = state.query; query.legacyTimeOrder = [b, a]; queryVariants.append(query)
    checks["card-data-key-keeps-every-playback-query-field"] = queryVariants.allSatisfy { query in
        var next = state; next.query = query
        return signature(next) != scrolled
    }
    checks["permission-notice-error-and-visibility-still-refresh-ui-without-rebuilding-data"] =
        signature(state, canEdit: false, notice: "Read-only", error: "Failed", visible: false) != scrolled

    catalog.revision = 4
    let failed = signature(state, catalogRevision: 4)
    composition.workspace.shouldFail = true
    composition.prepare(state, catalog: catalog, relationships: relationships, signature: failed, previous: metadataSignature)
    let afterFailure = WallpaperLibraryQuery.resolverInitializationCount
    checks["failed-card-preparation-clears-every-derived-value"] = composition.cardState == nil && composition.sourceSnapshot == nil
        && composition.downloadedContent.isEmpty && composition.playlistNames.isEmpty && composition.workspace.presentation.errors == 1
    composition.workspace.shouldFail = false
    composition.prepare(state, catalog: catalog, relationships: relationships, signature: failed, previous: failed)
    checks["same-inputs-retry-after-failure-instead-of-reusing-a-failed-projection"] = composition.cardState != nil
        && composition.sourceSnapshot != nil && WallpaperLibraryQuery.resolverInitializationCount == afterFailure + 2
        && composition.workspace.captures == 4

    // Full UI identity still changes for playback. Actual preparation below
    // distinguishes source work from the current playing/switching receipt.
    let alias = WallpaperReference(provider: .videoLibrary, sourceID: "projection-alias-A")
    let outside = WallpaperReference(provider: .videoLibrary, sourceID: "projection-outside-page")
    let hiddenAlias = WallpaperReference(provider: .videoLibrary, sourceID: "projection-unseen-alias")
    let listID = UUID()
    func ticketRelationships(revision: Int64 = 7, reset: UUID? = nil, name: String = "Projection playlist") -> UserCollectionsSnapshot {
        .init(revision: revision, resetEpoch: reset ?? epoch, migrationManifestID: nil,
            playlists: [.init(id: listID, name: name, sidebarRank: 0)],
            members: [.init(playlistID: listID, reference: alias, position: 0, addedAt: .distantPast)],
            favorites: [.init(reference: alias, favoritedAt: nil)], recent: [],
            aliases: [.init(alias: alias, canonical: a, proof: .publishedDownload),
                      .init(alias: hiddenAlias, canonical: outside, proof: .publishedDownload)], locators: [])
    }
    let ticketState = state, ticketRelations = ticketRelationships()
    let ticketCatalog = WallpaperLibraryCatalog(videos: [content(a), content(b), content(outside)],
        downloads: [content(download)], revision: 2)
    let playbackSource = try WallpaperPlaybackSequence.Snapshot(source: .global, revision: 2,
        entries: [a, b, alias, outside, hiddenAlias].map { .init(reference: $0, runtime: .video, isPlayable: true) })
    func currentSignature(_ owner: ProjectionComposition, state: WallpaperLibraryPresentationState,
        catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot, projection: UInt64 = 3) -> RenderSignature {
        let committed = owner.manager.libraryPlaybackSequence.committed
        let pending = owner.manager.libraryPlaybackSequence.pending
        return signature(state, catalogRevision: catalog.revision, projectionRevision: projection,
            relationshipsRevision: relationships.revision, resetEpoch: relationships.resetEpoch,
            sequenceReference: committed?.reference, sequenceTicket: committed?.ticket,
            runtimeTicket: owner.manager.playbackSwitch.committed?.ticket,
            pendingReference: pending?.proposal.entry.reference, pendingSequenceTicket: pending?.ticket,
            pendingRuntimeTicket: owner.manager.playbackSwitch.pending?.selection.ticket)
    }
    func derivedWork(_ owner: ProjectionComposition) -> [Int] {
        [WallpaperLibraryQuery.fullResolverInitializations, owner.workspace.captures,
         owner.downloadedContentWrites, owner.playlistNamesWrites, owner.sourceSnapshotWrites]
    }
    let ticketOwner = ProjectionComposition()
    var previous = currentSignature(ticketOwner, state: ticketState, catalog: ticketCatalog, relationships: ticketRelations)
    ticketOwner.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations, signature: previous, previous: nil)
    checks["playback-reuse-starts-with-real-nonempty-download-playlist-favorite-and-source-values"] =
        ticketOwner.downloadedContent[download]?.reference == download && ticketOwner.playlistNames[a] == ["Projection playlist"]
        && ticketOwner.cardState?.isFavorite(a) == true && ticketOwner.cardState?.isFavorite(alias) == true
        && ticketOwner.sourceSnapshot != nil
    func refreshPlayback(_ label: String) {
        let work = derivedWork(ticketOwner), resolver = WallpaperLibraryQuery.resolverInitializationCount
        let downloads = ticketOwner.downloadedContent, names = ticketOwner.playlistNames, snapshot = ticketOwner.sourceSnapshot
        let next = currentSignature(ticketOwner, state: ticketState, catalog: ticketCatalog, relationships: ticketRelations)
        ticketOwner.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations, signature: next, previous: previous)
        checks[label + "-does-not-repeat-source-resolve-capture-or-derived-assignments"] = derivedWork(ticketOwner) == work
        let currentResolvers = WallpaperLibraryQuery.resolverInitializationCount
        checks[label + "-at-most-one-current-reference-resolver"] = currentResolvers >= resolver && currentResolvers <= resolver + 1
        checks[label + "-preserves-current-source-values-and-canonical-organization"] = ticketOwner.downloadedContent == downloads
            && ticketOwner.playlistNames == names && ticketOwner.sourceSnapshot == snapshot
            && ticketOwner.cardState?.isFavorite(a) == true && ticketOwner.cardState?.isFavorite(alias) == true
        previous = next
    }
    let uiOnly = signature(ticketState, canEdit: false, notice: "Read-only", error: "Failed", visible: false)
    let uiWork = derivedWork(ticketOwner), uiResolvers = WallpaperLibraryQuery.resolverInitializationCount
    ticketOwner.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations, signature: uiOnly, previous: previous)
    checks["actual-permission-notice-error-visibility-render-retains-the-successful-data"] = uiOnly != previous
        && derivedWork(ticketOwner) == uiWork && WallpaperLibraryQuery.resolverInitializationCount == uiResolvers
    previous = uiOnly

    func stage(_ reference: WallpaperReference) -> PlaybackSwitchTicket {
        let proposal = ticketOwner.manager.libraryPlaybackSequence.proposeSelection(reference, from: playbackSource)!
        let (ticket, _) = ticketOwner.manager.playbackSwitch.begin(.video)
        precondition(ticketOwner.manager.libraryPlaybackSequence.stage(proposal, ticket: ticket))
        return ticket
    }
    let pendingB = stage(b)
    refreshPlayback("pending-only")
    checks["pending-only-immediately-switches-exact-B-without-inventing-a-commit"] =
        ticketOwner.cardState?.isSwitching(b) == true && ticketOwner.cardState?.isSwitching(a) == false
        && ticketOwner.cardState?.isPlaying(b) == false && ticketOwner.cardState?.committedTicket == nil
    let alignedRuntime = ticketOwner.manager.playbackSwitch
    var differentPendingRuntime = PlaybackSwitchTransaction()
    _ = differentPendingRuntime.begin(.video)
    ticketOwner.manager.playbackSwitch = differentPendingRuntime
    refreshPlayback("runtime-pending-ticket-only-mismatch")
    checks["changing-only-runtime-pending-ticket-revokes-the-existing-switching-badge"] =
        ticketOwner.cardState?.isSwitching(b) == false
    ticketOwner.manager.playbackSwitch = alignedRuntime
    refreshPlayback("runtime-pending-ticket-only-realigned")
    checks["realigning-only-runtime-pending-ticket-restores-the-current-switching-badge"] =
        ticketOwner.cardState?.isSwitching(b) == true
    let execution = UUID()
    _ = ticketOwner.manager.playbackSwitch.prepared(pendingB, executionID: execution)
    _ = ticketOwner.manager.playbackSwitch.visible(pendingB, executionID: execution)
    precondition(ticketOwner.manager.libraryPlaybackSequence.commit(pendingB) != nil)
    refreshPlayback("committed-only")
    checks["committed-only-immediately-plays-B-and-clears-the-switching-target"] =
        ticketOwner.cardState?.isPlaying(b) == true && ticketOwner.cardState?.isPlaying(a) == false
        && ticketOwner.cardState?.isSwitching(b) == false && ticketOwner.cardState?.committedTicket == pendingB
    ticketOwner.manager.stopCurrentPlayback()
    refreshPlayback("stopped-only")
    checks["stop-immediately-clears-playing-switching-and-committed-ticket"] = ticketOwner.cardState?.isPlaying(b) == false
        && ticketOwner.cardState?.isSwitching(b) == false && ticketOwner.cardState?.committedTicket == nil

    _ = stage(alias)
    refreshPlayback("aliased-pending-only")
    checks["aliased-pending-target-uses-the-existing-visible-canonical-reference"] =
        ticketOwner.cardState?.isSwitching(a) == true && ticketOwner.cardState?.isSwitching(alias) == true
        && ticketOwner.cardState?.isSwitching(b) == false
    ticketOwner.manager.stopCurrentPlayback()
    refreshPlayback("aliased-stop-only")
    _ = stage(outside)
    refreshPlayback("outside-page-pending-only")
    checks["outside-page-pending-target-neither-rebuilds-the-page-nor-switches-a-visible-neighbor"] =
        ticketOwner.cardState?.isSwitching(outside) == true && ticketOwner.cardState?.isSwitching(a) == false
        && ticketOwner.cardState?.isSwitching(b) == false
    ticketOwner.manager.stopCurrentPlayback()
    refreshPlayback("outside-page-stop-only")
    let hiddenPending = stage(hiddenAlias)
    refreshPlayback("unseen-outside-alias-pending-only")
    checks["previously-unmapped-page-outside-alias-keeps-raw-and-canonical-switching-queries-equivalent"] =
        ticketOwner.cardState?.canonical(hiddenAlias) == outside && ticketOwner.cardState?.isSwitching(hiddenAlias) == true
        && ticketOwner.cardState?.isSwitching(outside) == true && ticketOwner.cardState?.isSwitching(a) == false
    let hiddenExecution = UUID()
    _ = ticketOwner.manager.playbackSwitch.prepared(hiddenPending, executionID: hiddenExecution)
    _ = ticketOwner.manager.playbackSwitch.visible(hiddenPending, executionID: hiddenExecution)
    precondition(ticketOwner.manager.libraryPlaybackSequence.commit(hiddenPending) != nil)
    refreshPlayback("unseen-outside-alias-committed-only")
    checks["previously-unmapped-page-outside-alias-keeps-raw-and-canonical-playing-queries-equivalent"] =
        ticketOwner.cardState?.canonical(hiddenAlias) == outside && ticketOwner.cardState?.isPlaying(hiddenAlias) == true
        && ticketOwner.cardState?.isPlaying(outside) == true && ticketOwner.cardState?.isSwitching(hiddenAlias) == false
        && ticketOwner.cardState?.committedTicket == hiddenPending
    ticketOwner.manager.stopCurrentPlayback()
    refreshPlayback("unseen-outside-alias-stop-only")

    let mismatchedProposal = ticketOwner.manager.libraryPlaybackSequence.proposeSelection(b, from: playbackSource)!
    var foreignRuntime = PlaybackSwitchTransaction()
    let (foreignTicket, _) = foreignRuntime.begin(.video)
    _ = ticketOwner.manager.playbackSwitch.begin(.video)
    precondition(ticketOwner.manager.libraryPlaybackSequence.stage(mismatchedProposal, ticket: foreignTicket))
    refreshPlayback("mismatched-pending-only")
    checks["different-sequence-and-runtime-pending-tickets-cannot-grant-a-switching-badge"] =
        ticketOwner.cardState?.isSwitching(a) == false && ticketOwner.cardState?.isSwitching(b) == false
    ticketOwner.manager.stopCurrentPlayback()
    refreshPlayback("mismatched-pending-stop-only")
    let committedA = ticketOwner.manager.select(a, source: playbackSource)
    refreshPlayback("aligned-committed-A")
    checks["a-new-aligned-commit-still-uses-the-current-ticket"] = ticketOwner.cardState?.isPlaying(a) == true
        && ticketOwner.cardState?.committedTicket == committedA
    let foreignExecution = UUID()
    _ = foreignRuntime.prepared(foreignTicket, executionID: foreignExecution)
    _ = foreignRuntime.visible(foreignTicket, executionID: foreignExecution)
    ticketOwner.manager.playbackSwitch = foreignRuntime
    refreshPlayback("mismatched-committed-only")
    checks["different-sequence-and-runtime-committed-tickets-clear-playing-and-its-ticket"] =
        ticketOwner.cardState?.isPlaying(a) == false && ticketOwner.cardState?.isPlaying(b) == false
        && ticketOwner.cardState?.committedTicket == nil
    let echoWork = derivedWork(ticketOwner), echoResolvers = WallpaperLibraryQuery.resolverInitializationCount
    ticketOwner.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations, signature: previous, previous: previous)
    checks["identical-playback-echo-does-not-even-repeat-the-small-canonical-resolver"] =
        derivedWork(ticketOwner) == echoWork && WallpaperLibraryQuery.resolverInitializationCount == echoResolvers

    var reordered = ticketState
    reordered.queryResult = .init(items: [content(b), content(a)], unfilteredCount: 2)
    var metadata = ticketState
    metadata.queryResult = .init(items: [content(a, title: "New source metadata"), content(b)], unfilteredCount: 2)
    var metadataCatalog = ticketCatalog; metadataCatalog.videos = metadata.queryResult.items
    var revisedCatalog = ticketCatalog; revisedCatalog.revision += 1
    var newPage = ticketState; newPage.page = .favorites
    var sourceChanges: [(String, WallpaperLibraryPresentationState, WallpaperLibraryCatalog, UserCollectionsSnapshot, UInt64)] = [
        ("item-order", reordered, ticketCatalog, ticketRelations, 3),
        ("same-id-metadata", metadata, metadataCatalog, ticketRelations, 3),
        ("catalog-revision", ticketState, revisedCatalog, ticketRelations, 3),
        ("relationship-revision", ticketState, ticketCatalog, ticketRelationships(revision: 8, name: "Renamed playlist"), 3),
        ("reset-epoch", ticketState, ticketCatalog, ticketRelationships(reset: UUID()), 3),
        ("projection-revision", ticketState, ticketCatalog, ticketRelations, 4),
        ("page", newPage, ticketCatalog, ticketRelations, 3)]
    for (index, query) in queryVariants.enumerated() {
        var next = ticketState; next.query = query
        sourceChanges.append(("query-field-\(index)", next, ticketCatalog, ticketRelations, 3))
    }
    for (label, nextState, nextCatalog, nextRelations, projection) in sourceChanges {
        let owner = ProjectionComposition()
        let first = currentSignature(owner, state: ticketState, catalog: ticketCatalog, relationships: ticketRelations)
        owner.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations, signature: first, previous: nil)
        let before = derivedWork(owner), resolvers = WallpaperLibraryQuery.resolverInitializationCount
        let next = currentSignature(owner, state: nextState, catalog: nextCatalog, relationships: nextRelations, projection: projection)
        owner.prepare(nextState, catalog: nextCatalog, relationships: nextRelations, signature: next, previous: first)
        let after = derivedWork(owner)
        checks["source-" + label + "-still-rebuilds-all-derived-consumers"] = next != first
            && after[0] == before[0] + 1 && after[1] == before[1] + 1
            && zip(after.dropFirst(2), before.dropFirst(2)).allSatisfy { $0.0 > $0.1 }
            && WallpaperLibraryQuery.resolverInitializationCount == resolvers + 2
        checks["source-" + label + "-publishes-current-ordered-and-relationship-values"] =
            owner.workspace.capturedReferences == nextState.queryResult.items.map(\.reference)
            && owner.playlistNames[a] == [nextRelations.playlists[0].name] && owner.cardState?.isFavorite(a) == true
    }
    let many = (0..<5000).map { content(WallpaperReference(provider: .videoLibrary, sourceID: "large-projection-\($0)")) }
    var largeState = ticketState; largeState.queryResult = .init(items: many, unfilteredCount: many.count)
    let largeCatalog = WallpaperLibraryCatalog(videos: many, downloads: [content(download)], revision: 2)
    let largeOwner = ProjectionComposition()
    let largeFirst = currentSignature(largeOwner, state: largeState, catalog: largeCatalog, relationships: ticketRelations)
    largeOwner.prepare(largeState, catalog: largeCatalog, relationships: ticketRelations, signature: largeFirst, previous: nil)
    let largeWork = derivedWork(largeOwner), largeResolvers = WallpaperLibraryQuery.resolverInitializationCount
    let largeSnapshot = largeOwner.sourceSnapshot, largeDownloads = largeOwner.downloadedContent, largeNames = largeOwner.playlistNames
    let largeSource = try WallpaperPlaybackSequence.Snapshot(source: .global, revision: 2,
        entries: many.map { .init(reference: $0.reference, runtime: .video, isPlayable: true) })
    let tail = many.last!.reference
    let largeProposal = largeOwner.manager.libraryPlaybackSequence.proposeSelection(tail, from: largeSource)!
    let (largeTicket, _) = largeOwner.manager.playbackSwitch.begin(.video)
    precondition(largeOwner.manager.libraryPlaybackSequence.stage(largeProposal, ticket: largeTicket))
    let largePending = currentSignature(largeOwner, state: largeState, catalog: largeCatalog, relationships: ticketRelations)
    largeOwner.prepare(largeState, catalog: largeCatalog, relationships: ticketRelations, signature: largePending, previous: largeFirst)
    checks["5000-item-pending-keeps-full-resolve-capture-and-all-derived-assignments-unchanged"] =
        largeOwner.workspace.capturedReferences.count == 5000 && derivedWork(largeOwner) == largeWork
        && WallpaperLibraryQuery.resolverInitializationCount >= largeResolvers
        && WallpaperLibraryQuery.resolverInitializationCount <= largeResolvers + 1
        && largeOwner.sourceSnapshot == largeSnapshot && largeOwner.downloadedContent == largeDownloads && largeOwner.playlistNames == largeNames
    checks["5000-item-tail-pending-is-immediate-without-switching-a-neighbor-or-inventing-playback"] =
        largeOwner.cardState?.isSwitching(tail) == true && largeOwner.cardState?.isSwitching(many[0].reference) == false
        && largeOwner.cardState?.isPlaying(tail) == false && largeOwner.cardState?.committedTicket == nil

    // The original Inspector closure calls the real Commands factories. Only
    // capture's existing leaf is counted; this is not a Workspace/Query cost test.
    let inspectorOwner = ProjectionComposition()
    let inspectorSource = try WallpaperPlaybackSequence.Snapshot(source: .page(.videos), revision: 17,
        entries: many.map { .init(reference: $0.reference, runtime: .video, isPlayable: true) })
    let nextInspectorSource = try WallpaperPlaybackSequence.Snapshot(source: .page(.videos), revision: 18,
        entries: Array(inspectorSource.entries.reversed()))
    let commandWorkspace = CommandWorkspace(inspectorOwner.manager, inspectorSource)
    commandWorkspace.presentation.page = .videos
    inspectorOwner.commands = WallpaperLibraryCommands(inspectorOwner.manager, commandWorkspace)
    inspectorOwner.sourceSnapshot = inspectorSource
    let refreshed = (0..<3).map { _ in inspectorOwner.inspectorPrimaryFactory(many.last!) }
    checks["inspector-primary-refresh-reuses-ready-5000-item-page-without-capture"] =
        refreshed.allSatisfy { $0 != nil } && commandWorkspace.inspectorCaptureEntries == 0
    let heldPrimary = refreshed[0]!
    inspectorOwner.sourceSnapshot = nextInspectorSource
    commandWorkspace.displayed = nextInspectorSource
    heldPrimary()
    checks["inspector-held-primary-keeps-source-captured-before-later-page-input"] =
        commandWorkspace.plays.count == 1 && commandWorkspace.plays[0].0 == tail
        && commandWorkspace.plays[0].1 == inspectorSource
    let capturesBeforeNext = commandWorkspace.inspectorCaptureEntries
    let nextPrimary = inspectorOwner.inspectorPrimaryFactory(many[0])!
    nextPrimary()
    checks["inspector-next-factory-consumes-latest-prepared-source-without-recapture"] =
        commandWorkspace.plays.count == 2 && commandWorkspace.plays[1].0 == many[0].reference
        && commandWorkspace.plays[1].1 == nextInspectorSource
        && commandWorkspace.inspectorCaptureEntries == capturesBeforeNext
    let remoteReference = WallpaperReference(provider: .steamWorkshop, sourceID: "inspector-single")
    let remoteSingle = try WallpaperPlaybackSequence.Snapshot(source: .single(remoteReference), revision: 19,
        entries: [.init(reference: remoteReference, runtime: .video, isPlayable: true)])
    var nilSourcesPreserveFallback = true
    for (page, source, target) in [(WallpaperLibraryPage.videos, inspectorSource, many[1]),
                                   (.workshop, remoteSingle, content(remoteReference))] {
        let owner = ProjectionComposition()
        let workspace = CommandWorkspace(owner.manager, source)
        owner.commands = WallpaperLibraryCommands(workspace.manager, workspace)
        workspace.presentation.page = page
        let action = owner.inspectorPrimaryFactory(target)
        action?()
        nilSourcesPreserveFallback = nilSourcesPreserveFallback && action != nil
            && workspace.inspectorCaptureEntries == 1 && workspace.plays.count == 1
            && workspace.plays[0].0 == target.reference && workspace.plays[0].1 == source
    }
    checks["inspector-nil-local-and-remote-single-source-retain-original-capture-fallback"] = nilSourcesPreserveFallback
    let capturesBeforeStop = commandWorkspace.inspectorCaptureEntries
    let heldStop = inspectorOwner.inspectorPrimaryFactory(many[0])!
    let newerTicket = inspectorOwner.manager.select(many[0].reference, source: inspectorSource)
    heldStop()
    let staleStopRejected = inspectorOwner.manager.stops == 0
        && inspectorOwner.manager.playbackSwitch.committed?.ticket == newerTicket
    inspectorOwner.inspectorPrimaryFactory(many[0])!()
    checks["inspector-stop-keeps-real-ticket-check-and-never-captures-source"] = staleStopRejected
        && inspectorOwner.manager.stops == 1 && inspectorOwner.manager.playbackSwitch.committed == nil
        && commandWorkspace.inspectorCaptureEntries == capturesBeforeStop

    let initiallyAliased = ProjectionComposition()
    let initialAliasTicket = initiallyAliased.manager.select(hiddenAlias, source: playbackSource)
    let initialAliasSignature = currentSignature(initiallyAliased, state: ticketState, catalog: ticketCatalog, relationships: ticketRelations)
    initiallyAliased.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations,
        signature: initialAliasSignature, previous: nil)
    checks["initial-page-outside-playing-alias-is-queryable-with-its-canonical-target"] =
        initiallyAliased.cardState?.canonical(hiddenAlias) == outside && initiallyAliased.cardState?.canonical(outside) == outside
        && initiallyAliased.cardState?.isPlaying(hiddenAlias) == true && initiallyAliased.cardState?.isPlaying(outside) == true
        && initiallyAliased.cardState?.isSwitching(hiddenAlias) == false && initiallyAliased.cardState?.isSwitching(outside) == false
        && initiallyAliased.cardState?.committedTicket == initialAliasTicket
    let aliasWork = derivedWork(initiallyAliased), aliasResolvers = WallpaperLibraryQuery.resolverInitializationCount
    let canonicalTicket = initiallyAliased.manager.select(outside, source: playbackSource)
    let canonicalSignature = currentSignature(initiallyAliased, state: ticketState, catalog: ticketCatalog, relationships: ticketRelations)
    initiallyAliased.prepare(ticketState, catalog: ticketCatalog, relationships: ticketRelations,
        signature: canonicalSignature, previous: initialAliasSignature)
    checks["replacing-initial-playback-only-alias-drops-its-obsolete-canonical-query"] =
        initiallyAliased.cardState?.canonical(hiddenAlias) == hiddenAlias && initiallyAliased.cardState?.canonical(outside) == outside
        && initiallyAliased.cardState?.isPlaying(hiddenAlias) == false && initiallyAliased.cardState?.isPlaying(outside) == true
        && initiallyAliased.cardState?.isSwitching(hiddenAlias) == false && initiallyAliased.cardState?.isSwitching(outside) == false
        && initiallyAliased.cardState?.committedTicket == canonicalTicket
    checks["replacing-initial-playback-only-alias-preserves-the-source-work-budget"] = derivedWork(initiallyAliased) == aliasWork
        && WallpaperLibraryQuery.resolverInitializationCount >= aliasResolvers
        && WallpaperLibraryQuery.resolverInitializationCount <= aliasResolvers + 1
}


@MainActor private final class RemoteNavigationRefreshLeaf {
    var selectedItem: SteamWorkshopBrowserItem?
    var refreshes = 0
    var onRefresh: (() -> Void)?
    func refreshLibraryActions() { refreshes += 1; onRefresh?() }
}

@MainActor private func pixabayNativeMenuChecks(_ composition: RemoteComposition,
    commands: WallpaperLibraryCommands) -> [String: Bool] {
    composition.pixabayBrowserContent.selectedItem = .init(id: 7)
    let selected = composition.selectedBrowserOrganizationActions()!
    selected.onToggleFavorite(); selected.onChoosePlaylist(nil)
    var checks = ["pixabay-native-organization-uses-current-grid-without-an-inspector-slot":
        commands.favoriteActions.count == 2 && commands.playlistActions.count == 2]
    composition.pixabayBrowserContent.selectedItem = .init(id: 8)
    selected.onToggleFavorite(); selected.onChoosePlaylist(nil)
    checks["pixabay-native-organization-held-actions-cannot-retarget-next-grid-item"] =
        commands.favoriteActions.count == 2 && commands.playlistActions.count == 2
    return checks
}

// Actual Composition factories run in CommandTransactions. Only renderer and
// command-write leaves are recording; the navigation token is the service's
// existing owner, not another page/session identity invented by this fixture.
@MainActor private func steamNavigationActionChecks(app: NSApplication) async throws -> [String: Bool] {
    let ref = WallpaperReference(provider: .steamWorkshop, sourceID: "same-card")
    let content = WallpaperContentItem(reference: ref, providerReference: ref, locator: .init(),
        title: "Same card in public and personal feeds", kind: .video, publishedAvailability: .available,
        capabilities: [.play, .organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    let source = try WallpaperPlaybackSequence.Snapshot(source: .single(ref), revision: 1,
        entries: [.init(reference: ref, runtime: .video, isPlayable: true)])
    let manager = WallpaperManager(), workspace = RemoteWorkspace(relationships)
    let commands = WallpaperLibraryCommands(manager, CommandWorkspace(manager, source))
    let composition = RemoteComposition(workspace, commands)
    composition.downloadedContent[ref] = content
    composition.steam.selectedBrowserItem = .init(id: ref.sourceID)
    composition.cardState = try WallpaperLibraryCardStateProjection(items: [content], relationships: relationships,
        committedReference: nil, sequenceTicket: nil, runtimeTicket: nil)
    func invoke(_ menu: NSMenu) {
        for item in menu.items {
            let entry = item.submenu?.items.first ?? item
            if let action = entry.action { _ = app.sendAction(action, to: entry.target, from: entry) }
        }
    }
    let publicCard = composition.organization(.init(id: ref.sourceID))!
    let publicInspector = composition.inspector(.init(id: ref.sourceID))!
    let publicMenu = composition.menu(.init(id: ref.sourceID))!
    let originalSession = workspace.presentation.selectionState.sessionID
    var currentCard = publicCard
    composition.steamBrowserContent.onRefresh = { [weak composition] in
        if let updated = composition?.organization(.init(id: ref.sourceID)) { currentCard = updated }
    }
    composition.steam.navigationVersion += 1
    publicCard.onFavorite?(); publicCard.onPrimary?()
    publicInspector.onToggleFavorite(); publicInspector.onChoosePlaylist(nil); publicInspector.onPrimary()
    invoke(publicMenu)
    var checks = ["same-id-personal-entry-revokes-public-card-inspector-and-submenu-actions":
        commands.favoriteActions.isEmpty && commands.playlistActions.isEmpty && workspace.requests.isEmpty
        && workspace.presentation.page == .workshop && workspace.presentation.selectionState.sessionID == originalSession]
    // Drive only the original main-queue delivery of the actual subscription.
    // The retained item and DTO are identical across both browser contexts.
    let deadline = Date().addingTimeInterval(1)
    while composition.steamBrowserContent.refreshes == 0 && Date() < deadline {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    checks["same-dto-navigation-refreshes-current-card-actions-through-existing-publisher"] =
        composition.steamBrowserContent.refreshes == 1 && composition.downloadedContent[ref] == content
    let personalCard = currentCard
    let personalMenu = composition.menu(.init(id: ref.sourceID))!
    personalCard.onFavorite?(); personalCard.onPrimary?(); invoke(personalMenu)
    checks["fresh-personal-actions-use-the-same-source-ref-without-a-second-page-owner"] =
        commands.favoriteActions == [[ref], [ref]] && commands.playlistActions == [[ref]] && workspace.requests == [ref]
    composition.steam.navigationVersion += 1
    personalCard.onFavorite?(); personalCard.onPrimary?(); invoke(personalMenu)
    checks["personal-author-return-does-not-resurrect-held-actions-for-the-same-id"] =
        commands.favoriteActions.count == 2 && commands.playlistActions.count == 1 && workspace.requests == [ref]
    return checks
}
