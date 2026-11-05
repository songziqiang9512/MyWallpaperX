import AppKit
import Combine
import QuartzCore

// ACTUAL_PRESENTATION_STATE

@MainActor enum InspectorHostPublicationObservation {
    static var didClose: ((InspectorCardToken) -> Void)?
}

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

// Selection admission is a recording boundary here; the native grid's own
// selection/gesture implementation is covered by test_wallpaper_library_grid.
private final class InspectorCardSelectionLeaf {
    var acceptsSelection = true
    var onSelection: ((Set<WallpaperReference>, WallpaperReference?) -> Void)?
    func select(_ references: Set<WallpaperReference>, focus: WallpaperReference?) -> Bool {
        guard acceptsSelection else { return false }
        onSelection?(references, focus)
        return true
    }
}

private final class InspectorCardRouteProbe {
    let grid = InspectorCardSelectionLeaf()
    let inspector: WallpaperLibraryInspectorCoordinator
    let workspace: WallpaperLibraryWorkspace
    lazy var onInspect: (WallpaperContentItem) -> Void = // ACTUAL_CARD_INSPECT_CALLBACK
    init(workspace: WallpaperLibraryWorkspace, inspector: WallpaperLibraryInspectorCoordinator) {
        self.workspace = workspace; self.inspector = inspector
        grid.onSelection = { [weak workspace] references, focus in
            guard let workspace else { return }
            var state = workspace.presentation.state
            state.selectionState = .init(references: references, focusedReference: focus)
            workspace.presentation.publish(state)
        }
    }
    func synchronizeSelectedContent() {
        let state = workspace.presentation.state
        // ACTUAL_CARD_INSPECT_SELECTION_SYNC
    }
}

@MainActor private func inspectorCardRouteChecks() async -> [String: Bool] {
    let workspace = WallpaperLibraryWorkspace(), steam = SteamWorkshopService()
    func content(_ id: String, title: String) -> WallpaperContentItem {
        let ref = WallpaperReference(provider: .steamWorkshop, sourceID: id)
        return .init(reference: ref, providerReference: ref, locator: .init(titleHint: title, mediaKind: .video),
            title: title, kind: .video, publishedAvailability: .available, capabilities: [.inspect, .play],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    let first = content("card-one", title: "First"), second = content("card-two", title: "Second")
    steam.downloads = [.init(id: "card-one"), .init(id: "card-two")]
    workspace.catalog.catalog.downloads = [first, second]
    workspace.publishPresentation()
    let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: WallpaperManager(),
        images: SILService(), steam: steam, pixabay: PixabayService(), makePrimaryAction: { _ in {} },
        makeFavoriteAction: { _ in nil }, canOrganize: { true },
        availabilityChanges: Empty<Void, Never>().eraseToAnyPublisher(), onChoosePlaylist: { _, _ in })
    let route = InspectorCardRouteProbe(workspace: workspace, inspector: coordinator)
    route.onInspect(first); await WallpaperLibraryInspectorHarness.pump()
    let firstToken = coordinator.inspectorToken
    workspace.catalog.catalog.downloads[0] = content("card-one", title: "First, details completed")
    workspace.catalog.catalog.revision += 1
    workspace.publishPresentation(); route.synchronizeSelectedContent(); await WallpaperLibraryInspectorHarness.pump()
    var checks = ["first-card-details-completion-keeps-panel-open-with-its-original-token":
        coordinator.inspectedReference == first.reference && coordinator.inspectorToken == firstToken && firstToken != nil]
    _ = route.grid.select([first.reference], focus: first.reference)
    route.onInspect(second); await WallpaperLibraryInspectorHarness.pump()
    let secondToken = coordinator.inspectorToken
    route.synchronizeSelectedContent(); await WallpaperLibraryInspectorHarness.pump()
    checks["explicit-card-details-replaces-prior-selection-before-render-echo"] =
        coordinator.inspectedReference == second.reference && coordinator.inspectorToken == secondToken
    route.grid.acceptsSelection = false
    route.onInspect(first); await WallpaperLibraryInspectorHarness.pump()
    checks["rejected-grid-input-cannot-open-another-cards-details"] = coordinator.inspectorToken == secondToken
    route.grid.acceptsSelection = true
    route.onInspect(first); route.onInspect(second)
    workspace.publishPresentation(); route.synchronizeSelectedContent(); await WallpaperLibraryInspectorHarness.pump()
    checks["rapid-card-details-and-late-catalog-echo-keep-last-accepted-target"] = coordinator.inspectedReference == second.reference
    coordinator.closeInspector()
    workspace.publishPresentation(); route.synchronizeSelectedContent(); await WallpaperLibraryInspectorHarness.pump()
    checks["catalog-echo-after-user-close-does-not-reopen-inspector"] = coordinator.inspectedReference == nil
    return checks
}

@MainActor func inspectorPresentationRefreshChecks(split: AppKitMainSplitViewController) async throws -> [String: Bool] {
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
        playlists: [list],
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
    checks.merge(await inspectorCardRouteChecks(), uniquingKeysWith: { _, new in new })
    checks.merge(await inspectorReopenChecks(split: split), uniquingKeysWith: { _, new in new })
    return checks
}

@MainActor private func inspectorReopenChecks(split: AppKitMainSplitViewController) async -> [String: Bool] {
    let workspace = WallpaperLibraryWorkspace(), manager = WallpaperManager()
    let reference = WallpaperReference(provider: .videoLibrary, sourceID: "reopen-video")
    let content = WallpaperContentItem(reference: reference, providerReference: reference,
        locator: .init(titleHint: "Reopen", mediaKind: .video), title: "Reopen", kind: .video,
        publishedAvailability: .available, capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    manager.wallpapers = [.init(id: reference.sourceID)]; workspace.catalog.catalog.videos = [content]
    workspace.publishPresentation()
    let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager,
        images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(),
        makePrimaryAction: { _ in nil }, makeFavoriteAction: { _ in nil }, canOrganize: { false },
        availabilityChanges: Empty<Void, Never>().eraseToAnyPublisher(), onChoosePlaylist: { _, _ in })
    let probe = InspectorProbe()
    let host = split.children.flatMap(\.children).compactMap { $0 as? InspectorHostViewController }.first!
    let animationHost = host.view.superview!, overlay = animationHost.superview!
    let trailing = overlay.constraints.first {
        ($0.firstItem as? NSView) === animationHost && $0.firstAttribute == .trailing
    }!
    func closeButton(in root: NSView) -> NSButton? {
        if let button = root as? NSButton, button.toolTip == "关闭详情" { return button }
        for child in root.subviews { if let button = closeButton(in: child) { return button } }
        return nil
    }
    var checks: [String: Bool] = [:], frames: [[String: Any]] = []
    @discardableResult func record(_ stage: String) -> NSRect? {
        let presentation = animationHost.layer?.presentation()?.frame
        frames.append(["stage": stage, "hostSeconds": ProcessInfo.processInfo.systemUptime,
            "presentationFrame": presentation.map { NSStringFromRect($0) } ?? "nil",
            "modelFrame": NSStringFromRect(animationHost.frame), "trailing": trailing.constant,
            "overlayBounds": NSStringFromRect(overlay.bounds), "hidden": overlay.isHidden,
            "windowVisible": overlay.window?.isVisible == true])
        return presentation
    }
    split.view.window?.makeKeyAndOrderFront(nil)
    var expectedFinalToken: InspectorCardToken?
    InspectorHostPublicationObservation.didClose = { token in
        guard token == expectedFinalToken else { return }
        checks["real-Shell-didClose-is-consumed-before-its-post-returns"] = coordinator.inspectorToken == nil
        record("after-real-didClose-post-returns")
    }
    defer {
        InspectorHostPublicationObservation.didClose = nil
        coordinator.closeInspector(); split.view.window?.orderOut(nil)
    }
    try? await Task.sleep(for: .milliseconds(350))
    func reopen(_ name: String, open: () -> Void) async {
        open()
        checks[name + "-didPresent-mounts-in-the-open-turn"] = probe.mounts.contains {
            $0.0 == coordinator.inspectorToken && $0.1.isDescendant(of: host.view)
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard let token = coordinator.inspectorToken,
              let originalView = probe.mounts.last(where: { $0.0 == token })?.1,
              let close = closeButton(in: host.view) else {
            checks[name + "-real-host-and-close-button-exist"] = false
            return
        }
        checks[name + "-real-host-and-close-button-exist"] = originalView.isDescendant(of: host.view)
        close.performClick(nil)
        checks[name + "-real-close-immediately-releases-overlay-input"] = overlay.hitTest(NSPoint(x: 10, y: 10)) == nil
        try? await Task.sleep(for: .milliseconds(70))
        let closing = record(name + "-mid-close")
        checks[name + "-close-has-real-in-flight-presentation"] = closing.map {
            let offset = $0.maxX - overlay.bounds.maxX
            return offset > 0.5 && offset < animationHost.frame.width + 48
        } == true
        let opens = probe.opens.count, mounts = probe.mounts.count
        open(); record(name + "-reopen-same-turn")
        checks[name + "-explicit-reopen-reuses-token-view-and-mount"] = coordinator.inspectorToken == token
            && originalView.isDescendant(of: host.view) && probe.opens.count == opens + 1 && probe.mounts.count == mounts
        for index in 0..<6 {
            try? await Task.sleep(for: .milliseconds(16)); record(name + "-reopen-frame-\(index)")
        }
        try? await Task.sleep(for: .milliseconds(300))
        record(name + "-after-old-close-completion")
        checks[name + "-old-close-cannot-hide-explicitly-reopened-content"] = coordinator.inspectorToken == token
            && originalView.isDescendant(of: host.view) && !overlay.isHidden
            && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
        coordinator.closeInspector(); try? await Task.sleep(for: .milliseconds(300))
    }
    await reopen("same-video") { coordinator.inspect(content: content) }
    let file = PixabayVideoFile(url: "https://example.invalid/reopen.mp4", width: 1280, height: 720, size: 1, thumbnail: "https://example.invalid/reopen.png")
    let remote = PixabayVideoItem(id: 117, pageURL: "https://pixabay.com/videos/id-117/", tags: "Reopen", duration: 1,
        user: "fixture", videos: .init(large: file, medium: file, small: nil, tiny: nil))
    await reopen("same-pixabay") { coordinator.inspectPixabayItem(remote) }
    let artwork = OnlineImageArtwork(source: .wallhaven, artworkID: "r117", title: "Reopen",
        sourceURL: URL(string: "https://wallhaven.cc/w/r117")!)
    await reopen("same-online-image") { coordinator.inspectOnlineArtwork(artwork) }
    coordinator.inspect(content: content); try? await Task.sleep(for: .milliseconds(350))
    let closingToken = coordinator.inspectorToken
    record("cross-source-before-close-command")
    if let closingToken { InspectorHostActions.postClose(module: closingToken.module, cardID: closingToken.cardID) }
    try? await Task.sleep(for: .milliseconds(32))
    let crossSourceClosing = record("cross-source-mid-close")
    checks["cross-source-close-has-real-in-flight-presentation"] = crossSourceClosing.map {
        let offset = $0.maxX - overlay.bounds.maxX
        return offset > 0.5 && offset < animationHost.frame.width + 48
    } == true
    coordinator.inspectPixabayItem(remote); record("cross-source-reopen-same-turn")
    let crossSourceToken = coordinator.inspectorToken
    let crossSourceView = probe.mounts.last(where: { $0.0 == crossSourceToken })?.1
    for index in 0..<6 {
        try? await Task.sleep(for: .milliseconds(16)); record("cross-source-reopen-frame-\(index)")
    }
    try? await Task.sleep(for: .milliseconds(300))
    record("cross-source-after-old-close-completion")
    checks["cross-source-reopen-keeps-the-new-token-and-view-visible"] = crossSourceToken != nil
        && crossSourceToken != closingToken && coordinator.inspectorToken == crossSourceToken
        && crossSourceView?.isDescendant(of: host.view) == true && !overlay.isHidden
        && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
    coordinator.closeInspector(); try? await Task.sleep(for: .milliseconds(300))
    coordinator.inspect(content: content); try? await Task.sleep(for: .milliseconds(350))
    let opens = probe.opens.count
    expectedFinalToken = coordinator.inspectorToken
    closeButton(in: host.view)?.performClick(nil)
    try? await Task.sleep(for: .milliseconds(70))
    workspace.catalog.catalog.revision += 1; workspace.publishPresentation()
    coordinator.syncSelection(content: content)
    try? await Task.sleep(for: .milliseconds(350))
    checks["catalog-and-selection-render-echo-cannot-reopen-a-closing-inspector"] = coordinator.inspectorToken == nil
        && overlay.isHidden && probe.opens.count == opens
    checks["real-Shell-close-post-return-was-observed"] = checks["real-Shell-didClose-is-consumed-before-its-post-returns"] != nil
    workspace.publishPresentation(); coordinator.syncSelection(content: content)
    await WallpaperLibraryInspectorHarness.pump()
    checks["catalog-and-selection-render-echo-cannot-open-a-hidden-inspector"] = coordinator.inspectorToken == nil
        && overlay.isHidden && probe.opens.count == opens
    coordinator.inspect(content: content)
    try? await Task.sleep(for: .milliseconds(16))
    let beforeBusy = record("entrance-before-Main-busy")
    // The render server must advance the slide while Main cannot run a
    // constraint-animation tick. Do not force layout or display in this interval.
    let busyDeadline = CACurrentMediaTime() + 0.08
    while CACurrentMediaTime() < busyDeadline {}
    // presentationLayer samples the start of the current transaction. End it
    // before the second read; this does not run AppKit layout/animation ticks.
    CATransaction.flush()
    let afterBusy = record("entrance-after-Main-busy")
    checks["inspector-entrance-continues-moving-while-Main-is-busy"] = beforeBusy.flatMap { before in
        afterBusy.map { before.minX - $0.minX > 20 }
    } == true
    checks["busy-entrance-keeps-the-current-content-mounted"] = coordinator.inspectorToken != nil
        && probe.mounts.last?.1.isDescendant(of: host.view) == true && !overlay.isHidden
    coordinator.closeInspector()
    try? await Task.sleep(for: .milliseconds(350))
    let underlay = overlay.superview!.subviews.first { $0 !== overlay }!
    let bar = WallpaperCardControlsView(frame: NSRect(x: 24, y: 40, width: 260, height: 44))
    underlay.addSubview(bar)
    defer { bar.removeFromSuperview() }
    var cardOpens = 0
    bar.onInspect = { cardOpens += 1; coordinator.inspect(content: content) }
    bar.layoutSubtreeIfNeeded()
    bar.detailButton.performClick(nil)
    let cardToken = coordinator.inspectorToken, cardMounts = probe.mounts.count, cardCloses = probe.closes.count
    let detailPoint = bar.detailButton.convert(NSPoint(x: bar.detailButton.bounds.midX, y: bar.detailButton.bounds.midY), to: overlay.superview)
    let playPoint = bar.playButton.convert(NSPoint(x: bar.playButton.bounds.midX, y: bar.playButton.bounds.midY), to: overlay.superview)
    checks["opening-overlay-passes-real-detail-button-but-keeps-play-shielded"] = cardOpens == 1 && cardToken != nil
        && overlay.hitTest(detailPoint) == nil && overlay.hitTest(playPoint) != nil
    bar.detailButton.performClick(nil)
    checks["detail-button-closes-in-flight-host-through-native-responder"] = overlay.hitTest(NSPoint(x: 10, y: 10)) == nil
        && cardOpens == 1 && probe.closes.count == cardCloses + 1
    bar.detailButton.performClick(nil)
    try? await Task.sleep(for: .milliseconds(350))
    checks["next-detail-click-reopens-in-flight-host-without-new-view-or-token"] = cardOpens == 2
        && coordinator.inspectorToken == cardToken && probe.mounts.count == cardMounts && !overlay.isHidden
    coordinator.closeInspector()
    try? await Task.sleep(for: .milliseconds(350))
    if let data = try? JSONSerialization.data(withJSONObject: frames, options: [.sortedKeys]) {
        FileHandle.standardError.write(Data("INSPECTOR REOPEN FRAMES ".utf8)); FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([10]))
    }
    return checks
}
