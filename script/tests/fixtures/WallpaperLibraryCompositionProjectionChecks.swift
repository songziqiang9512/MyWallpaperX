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
    var downloadedContent: [WallpaperReference: WallpaperContentItem] = [:]
    var cardState: WallpaperLibraryCardStateProjection?
    var playlistNames: [WallpaperReference: [String]] = [:]
    var sourceSnapshot: WallpaperPlaybackSequence.Snapshot?

    func prepare(_ state: WallpaperLibraryPresentationState, catalog: WallpaperLibraryCatalog,
                 relationships: UserCollectionsSnapshot, signature: RenderSignature, previous: RenderSignature?) {
        prepareCardState(state, catalog: catalog, relationships: relationships, signature: signature, previousSignature: previous)
    }
    // ACTUAL_CARD_STATE_PREPARATION
}

@MainActor private func runCompositionProjectionChecks(_ checks: inout [String: Bool]) throws {
    let selection = WallpaperLibrarySelectionState(), epoch = UUID()
    func oldSignature(_ projection: UInt64, canEdit: Bool = true, notice: String? = nil, error: String? = nil) -> RenderSignature {
        .init(page: .videos, query: .init(), items: [], selection: selection, catalogRevision: 2, projectionRevision: projection,
            relationshipsRevision: 7, resetEpoch: epoch, sequenceReference: nil, sequenceTicket: nil, ticket: nil, canEdit: canEdit,
            recoveryNotice: notice, operationError: error, visible: true)
    }
    checks["late-accepted-projection-is-distinct-from-early-render-of-same-source-revision"] = oldSignature(1) != oldSignature(2)
    checks["render-signature-still-recognizes-identical-echo-and-editing-errors"] = oldSignature(2) == oldSignature(2)
        && oldSignature(2) != oldSignature(2, canEdit: false) && oldSignature(2) != oldSignature(2, notice: "Read-only recovery")
    checks["operation-error-is-not-masked-by-an-unchanged-recovery-notice-in-render-signature"] =
        oldSignature(2, notice: "Read-only recovery") != oldSignature(2, notice: "Read-only recovery", error: "Rename failed")
        && oldSignature(2, notice: "Read-only recovery", error: "Rename failed") != oldSignature(2, notice: "Read-only recovery", error: "Add failed")

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
                   canEdit: Bool = true, notice: String? = nil, error: String? = nil, visible: Bool = true) -> RenderSignature {
        .init(page: state.page, query: state.query, items: state.queryResult.items, selection: state.selectionState,
            catalogRevision: catalogRevision, projectionRevision: projectionRevision, relationshipsRevision: relationshipsRevision,
            resetEpoch: resetEpoch ?? epoch, sequenceReference: sequenceReference, sequenceTicket: sequenceTicket,
            ticket: runtimeTicket, canEdit: canEdit, recoveryNotice: notice, operationError: error, visible: visible)
    }
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
        && composition.workspace.captures == 1 && scrolled.hasSameCardInputs(as: selected)

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
    let reorderedInvalidates = !signature(changed).hasSameCardInputs(as: scrolled)
    changed.queryResult = .init(items: [content(a, title: "Changed metadata"), content(b)], unfilteredCount: 2)
    let metadataSignature = signature(changed)
    catalog.videos = changed.queryResult.items
    composition.prepare(changed, catalog: catalog, relationships: relationships, signature: metadataSignature, previous: scrolled)
    checks["actual-order-or-same-id-metadata-invalidates-card-data"] = reorderedInvalidates
        && !metadataSignature.hasSameCardInputs(as: scrolled) && composition.workspace.captures == 2
        && WallpaperLibraryQuery.resolverInitializationCount == built + 2
    changed = state; changed.page = .favorites
    let ticket = PlaybackSwitchTicket(epoch: 42, id: UUID(), runtime: .video)
    let ownerChanges: [Bool] = [
        !signature(changed).hasSameCardInputs(as: scrolled),
        !signature(state, catalogRevision: 4).hasSameCardInputs(as: scrolled),
        !signature(state, projectionRevision: 4).hasSameCardInputs(as: scrolled),
        !signature(state, relationshipsRevision: 8).hasSameCardInputs(as: scrolled),
        !signature(state, resetEpoch: UUID()).hasSameCardInputs(as: scrolled),
        !signature(state, sequenceReference: a).hasSameCardInputs(as: scrolled),
        !signature(state, sequenceTicket: ticket).hasSameCardInputs(as: scrolled),
        !signature(state, runtimeTicket: ticket).hasSameCardInputs(as: scrolled)]
    checks["card-data-key-retains-all-owner-revisions-epoch-and-playback-identities"] = ownerChanges.allSatisfy { $0 }
    var queryVariants = [WallpaperLibraryQueryState]()
    var query = state.query; query.search = "Changed"; queryVariants.append(query)
    query = state.query; query.provider = .pixabay; queryVariants.append(query)
    query = state.query; query.kind = .image; queryVariants.append(query)
    query = state.query; query.status = .unavailable; queryVariants.append(query)
    query = state.query; query.sort = .name; queryVariants.append(query)
    query = state.query; query.ascending = false; queryVariants.append(query)
    query = state.query; query.legacyTimeOrder = [b, a]; queryVariants.append(query)
    checks["card-data-key-keeps-every-playback-query-field"] = queryVariants.allSatisfy { query in
        var next = state; next.query = query
        return !signature(next).hasSameCardInputs(as: scrolled)
    }
    checks["permission-notice-error-and-visibility-still-refresh-ui-without-rebuilding-data"] =
        signature(state, canEdit: false, notice: "Read-only", error: "Failed", visible: false).hasSameCardInputs(as: scrolled)

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
}
