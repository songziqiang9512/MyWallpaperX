import AppKit
import Combine

// ACTUAL_PRESENTATION_STATE

/// Publish the production state value through the Coordinator's real Combine
/// subscription. Only source metadata/views remain the existing recording leaves.
final class InspectorPresentation: ObservableObject {
    @Published var state = WallpaperLibraryPresentationState()
    var canEditCollections = true
    private(set) var publications = 0
    var errors: [String] = []
    func report(_ error: Error) { errors.append(error.localizedDescription) }
    func publish(_ value: WallpaperLibraryPresentationState) { publications += 1; state = value }
}

// Match the source owner's snapshot boundary; this leaf owns no projection work.
final class InspectorCatalog { var catalog = WallpaperLibraryCatalog() }

extension WallpaperLibraryWorkspace {
    func publishPresentation() {
        var value = presentation.state
        let items = catalog.catalog.videos + catalog.catalog.images + catalog.catalog.downloads
        value.queryResult = .init(items: items, unfilteredCount: items.count)
        value.allowsEditing = presentation.canEditCollections
        presentation.publish(value)
    }
}

@MainActor func inspectorPresentationRefreshChecks() async throws -> [String: Bool] {
    let workspace = WallpaperLibraryWorkspace(), manager = WallpaperManager()
    let reference = WallpaperReference(provider: .videoLibrary, sourceID: "refresh-input")
    let value = WallpaperContentItem(reference: reference, providerReference: reference,
        locator: .init(titleHint: "Refresh", mediaKind: .video), title: "Refresh", kind: .video,
        publishedAvailability: .available, capabilities: [.play, .inspect, .organize], metadata: .init(),
        acquisition: .idle, update: .idle, aliases: [])
    workspace.catalog.catalog.videos = [value]; manager.wallpapers = [.init(id: reference.sourceID)]
    workspace.publishPresentation()
    let availability = PassthroughSubject<Void, Never>()
    var preparations = 0
    let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager,
        images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(),
        makePrimaryAction: { content in preparations += 1; return content.capabilities.contains(.play) ? {} : nil },
        makeFavoriteAction: { _ in nil }, canOrganize: { workspace.presentation.canEditCollections },
        availabilityChanges: availability.eraseToAnyPublisher(), onChoosePlaylist: { _, _ in })
    await WallpaperLibraryInspectorHarness.pump()
    coordinator.inspect(content: value)
    let token = coordinator.inspectorToken, prepared = preparations, reads = workspace.contentReads
    let published = workspace.presentation.publications
    for index in 0..<3 {
        var state = workspace.presentation.state
        state.query.scrollAnchor = reference; state.query.scrollOffset = Double(index + 1)
        state.query.scrollAtTop = false; state.query.preferredColumns = index + 3
        state.lastErrorEvent += 1
        workspace.presentation.publish(state)
        await WallpaperLibraryInspectorHarness.pump()
    }
    var checks = ["scroll-zoom-and-notice-publications-do-not-resolve-or-prepare-inspector-again":
        workspace.presentation.publications == published + 3 && workspace.contentReads == reads
            && preparations == prepared && coordinator.inspectorToken == token]
    let list = WallpaperPlaylist(name: "Updated membership", sidebarRank: 0)
    let previous = workspace.relationships
    workspace.relationships = .init(revision: previous.revision + 1, resetEpoch: previous.resetEpoch,
        migrationManifestID: nil, playlists: [list],
        members: [.init(playlistID: list.id, reference: reference, position: 0, addedAt: Date())],
        favorites: [], recent: [], aliases: [], locators: [])
    workspace.publishPresentation(); await WallpaperLibraryInspectorHarness.pump()
    checks["relationship-revision-with-identical-items-refreshes-existing-inspector"] = preparations == prepared + 1
        && coordinator.inspectorToken == token
    var state = workspace.presentation.state
    state.selectionState = .init(references: [reference], focusedReference: reference)
    workspace.presentation.publish(state); await WallpaperLibraryInspectorHarness.pump()
    checks["selection-session-publication-refreshes-fixed-action-bindings"] = preparations == prepared + 2
    workspace.catalog.catalog.revision += 1
    workspace.presentation.publish(workspace.presentation.state); await WallpaperLibraryInspectorHarness.pump()
    checks["catalog-revision-refreshes-inspector-even-when-page-items-are-identical"] = preparations == prepared + 3
    state = workspace.presentation.state; state.query.search = "Refresh"
    workspace.presentation.publish(state); await WallpaperLibraryInspectorHarness.pump()
    checks["playback-source-query-publication-refreshes-actions"] = preparations == prepared + 4
    workspace.playing = reference
    coordinator.syncSelection(content: value)
    checks["playback-sync-refreshes-actions-without-needing-a-presentation-change"] = preparations == prepared + 5
    availability.send()
    checks["original-availability-publisher-still-refreshes-synchronously"] = preparations == prepared + 6
    workspace.catalog.catalog.videos = [WallpaperContentItem(reference: reference, providerReference: reference,
        locator: value.locator, title: value.title, kind: .video, publishedAvailability: .unavailable,
        capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])]
    workspace.publishPresentation(); await WallpaperLibraryInspectorHarness.pump()
    checks["changed-source-availability-refreshes-without-another-selection"] = preparations == prepared + 7
        && coordinator.inspectorToken == token
    workspace.presentation.canEditCollections = false
    workspace.publishPresentation(); await WallpaperLibraryInspectorHarness.pump()
    checks["editing-admission-publication-still-refreshes-inspector"] = preparations == prepared + 8
    coordinator.closeInspector()
    let library = OnlineImageLibrary.shared, previousSnapshot = library.snapshot
    defer { library.snapshot = previousSnapshot }
    let id = OnlineImageAssetID(source: .pixiv, artworkID: "7331")
    let record = OnlineImageLocalRecord(assetID: id, title: "Playback publisher", sourceURL: URL(string: "https://www.pixiv.net/artworks/7331")!,
        author: nil, authorID: nil, tags: [], relativePath: "publisher.png", pixelWidth: 8, pixelHeight: 8,
        fileSizeBytes: 1, firstDownloadedAt: Date(), revision: UUID())
    library.snapshot = .init(records: [record])
    let online = library.content(for: id.reference)!
    workspace.catalog.catalog.downloads = [online]
    state = workspace.presentation.state; state.page = .pixiv
    workspace.presentation.publish(state)
    workspace.playing = id.reference
    var stops = 0, applies = 0
    let onlineCoordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager,
        images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), makePrimaryAction: { content in
            let expected = workspace.playing
            return {
                guard workspace.playing == expected else { return }
                if expected == content.reference { workspace.playing = nil; stops += 1 }
                else { workspace.playing = content.reference; applies += 1 }
                workspace.playbackChanges.send()
            }
        }, makeFavoriteAction: { _ in nil }, canOrganize: { true },
        availabilityChanges: availability.eraseToAnyPublisher(), onChoosePlaylist: { _, _ in })
    let probe = InspectorProbe()
    onlineCoordinator.inspect(content: online)
    await WallpaperLibraryInspectorHarness.pump()
    guard let view = probe.mounts.last(where: { $0.0 == onlineCoordinator.inspectorToken })?.1 as? OnlineImageInspectorView else {
        checks["online-playback-publisher-mounted-original-inspector"] = false
        onlineCoordinator.closeInspector()
        return checks
    }
    workspace.playbackChanges.send(); await WallpaperLibraryInspectorHarness.pump()
    let onlineToken = onlineCoordinator.inspectorToken, mounts = probe.mounts.count
    let unchangedPresentation = workspace.presentation.publications, staleStop = view.actions?.onPrimary
    view.actions?.onPrimary(); await WallpaperLibraryInspectorHarness.pump()
    checks["online-Stop-publisher-restores-Apply-without-selection-or-metadata-publication"] = stops == 1 && applies == 0
        && view.actions?.state.isPlaying == false && view.actions?.state.primaryTitle == "设为壁纸"
        && onlineCoordinator.inspectorToken == onlineToken && probe.mounts.count == mounts
        && workspace.presentation.publications == unchangedPresentation
    staleStop?()
    view.actions?.onPrimary(); await WallpaperLibraryInspectorHarness.pump()
    checks["online-Apply-after-Stop-uses-refreshed-fixed-action-and-retires-old-Stop"] = stops == 1 && applies == 1
        && workspace.playing == id.reference && view.actions?.state.isPlaying == true
        && onlineCoordinator.inspectorToken == onlineToken && probe.mounts.count == mounts
        && workspace.presentation.publications == unchangedPresentation
    onlineCoordinator.closeInspector()
    return checks
}
