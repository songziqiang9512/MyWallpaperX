// Actual Commands removal path with an isolated file and controlled manifest
// failure. This is appended to the main transaction fixture, retaining its
// real relationship controller and original removal/selection checks.
@MainActor private func runOnlineImageRemovalChecks(root: URL, controller: UserCollectionsController,
    workspace: (WallpaperLibraryCatalog, WallpaperLibraryPage) -> RemovalWorkspace) async throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
        return condition()
    }
    for index in 0..<6 {
        let store = UserCollectionsStore(url: root.appendingPathComponent("removal-history-\(index).sqlite3"))
        let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let list = try await collections.createPlaylist(name: "Current list")
        let otherList = try await collections.createPlaylist(name: "Other list")
        let page: WallpaperLibraryPage = [.videos, .images, .downloads, .recent, .favorites, .playlist(list)][index]
        let provider: WallpaperProvider = page == .images ? .staticImageLibrary : (page == .downloads ? .steamWorkshop : .videoLibrary)
        let ref = WallpaperReference(provider: provider, sourceID: "history-\(index)")
        let file = root.appendingPathComponent("history-\(index).mp4")
        try Data([23]).write(to: file)
        let row = WallpaperContentItem(reference: ref, providerReference: ref,
            locator: .init(path: file.path, mediaKind: page == .images ? .image : .video),
            title: "History removal", kind: page == .images ? .image : .video, publishedAvailability: .available,
            capabilities: [.play, .organize, .delete], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        try await collections.perform([.addMembers(list, [row.organizationItem], Date()),
            .addMembers(otherList, [row.organizationItem], Date()), .setFavorite(row.organizationItem, true, Date())])
        collections.recordSuccessfulUse(ref, locator: row.locator, sequence: 1)
        _ = await wait { collections.snapshot.recent.map(\.reference) == [ref] }
        let suite = "mwx.removal.history." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog: WallpaperLibraryCatalog = page == .images ? .init(images: [row], revision: 1)
            : (page == .downloads ? .init(downloads: [row], revision: 1) : .init(videos: [row], revision: 1))
        let view = RemovalWorkspace(collections, catalog, defaults: defaults)
        view.presentation.switchPage(page)
        let commands = RemovalCommands(view)
        view.presentation.setSelection([ref], focused: ref)
        commands.remove(); RecentAlertProbe.finish(.alertSecondButtonReturn)
        checks["cancelled-removal-keeps-history-" + page.persistenceKey] = collections.snapshot.recent.map(\.reference) == [ref]
        commands.remove(); RecentAlertProbe.finish(.alertFirstButtonReturn)
        _ = await wait { !view.edited.isEmpty }
        let bytes = try Data(contentsOf: file)
        checks["successful-removal-also-retires-history-without-touching-other-relations-" + page.persistenceKey] = collections.snapshot.recent.isEmpty
            && collections.snapshot.members.filter { $0.playlistID == otherList }.map(\.reference) == [ref]
            && collections.snapshot.members.filter { $0.playlistID == list }.isEmpty == (page == .playlist(list))
            && collections.snapshot.favorites.isEmpty == (page == .favorites) && bytes == Data([23])
            && commands.manager.requested.isEmpty && commands.images.requested.isEmpty && commands.steam.requested.isEmpty
    }
    do {
        let store = UserCollectionsStore(url: root.appendingPathComponent("partial-removal-history.sqlite3"))
        let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let refs = [WallpaperReference(provider: .pixabay, sourceID: "partial-success"), .init(provider: .pixabay, sourceID: "partial-failed")]
        let urls = [root.appendingPathComponent("partial-success.mp4"), root.appendingPathComponent("partial-failed.mp4")]
        for url in urls { try Data([24]).write(to: url) }
        let rows = zip(refs, urls).map { ref, url in WallpaperContentItem(reference: ref, providerReference: ref,
            locator: .init(path: url.path, mediaKind: .video), title: ref.sourceID, kind: .video,
            publishedAvailability: .available, capabilities: [.play, .organize, .delete], metadata: .init(), acquisition: .idle, update: .idle, aliases: []) }
        let alias = WallpaperReference(provider: .videoLibrary, sourceID: "imported-partial-success")
        try await collections.perform(.linkAlias(.init(alias: alias, canonical: refs[0], proof: .publishedDownload), Date()))
        collections.recordSuccessfulUse(alias, locator: nil, sequence: 1)
        collections.recordSuccessfulUse(refs[1], locator: nil, sequence: 2)
        _ = await wait { collections.snapshot.recent.count == 2 }
        let suite = "mwx.removal.partial." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let view = RemovalWorkspace(collections, .init(downloads: rows, revision: 1), defaults: defaults)
        view.presentation.switchPage(.downloads); view.presentation.setSelection(Set(refs), focused: refs[0], isSelecting: true)
        let commands = RemovalCommands(view); commands.pixabay.failingNames = [urls[1].lastPathComponent]
        commands.remove(); RecentAlertProbe.alert?.suppressionButton?.state = .on; RecentAlertProbe.finish(.alertFirstButtonReturn)
        _ = await wait { !view.edited.isEmpty }
        checks["partial-file-delete-removes-only-successful-canonical-history"] = collections.snapshot.recent.map(\.reference) == [refs[1]]
            && !FileManager.default.fileExists(atPath: urls[0].path) && FileManager.default.fileExists(atPath: urls[1].path)
            && view.presentation.selectionState.references == [refs[1]]
    }
    let imageRef = WallpaperReference(provider: .pixiv, sourceID: "42:p2"), imageURL = root.appendingPathComponent("online-image.png")
    let imageRevision = UUID()
    try Data([4]).write(to: imageURL)
    let imageRow = WallpaperContentItem(reference: imageRef, providerReference: imageRef, locator: .init(path: imageURL.path, mediaKind: .image),
        title: "Online image", kind: .image, publishedAvailability: .available, capabilities: [.play, .organize, .delete],
        metadata: .init(resourceRevision: imageRevision.uuidString), acquisition: .idle, update: .idle, aliases: [])
    // Production action factory and Sequence/Transaction run unchanged. The
    // source recovery leaf records delegation; its actual eligibility/network
    // admission remains covered by DownloadRecovery's own focused gate.
    for source in OnlineImageSource.allCases {
        let reference = OnlineImageAssetID(source: source, artworkID: "42").reference
        let sourceSnapshot = try WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 1,
            entries: [.init(reference: reference, runtime: .systemStill, isPlayable: true)])
        let manager = WallpaperManager()
        let commandView = CommandWorkspace(manager, sourceSnapshot), commands = WallpaperLibraryCommands(manager, commandView)
        let oldTicket = manager.select(reference, source: sourceSnapshot)
        let available = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: .image), title: "Applied image", kind: .image,
            publishedAvailability: .available, capabilities: [.play], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        let oldStop = commands.makePrimaryAction(for: available, from: sourceSnapshot,
            renderedPlaying: true, renderedTicket: oldTicket)
        let newer = manager.select(reference, source: sourceSnapshot)
        oldStop?()
        checks["online-image-old-stop-does-not-borrow-new-ticket-" + source.rawValue] = oldStop != nil
            && manager.stops == 0 && manager.playbackSwitch.committed?.ticket == newer && commandView.plays.isEmpty
        let stop = commands.makePrimaryAction(for: available, from: sourceSnapshot,
            renderedPlaying: true, renderedTicket: newer)
        stop?()
        checks["online-image-playing-primary-stops-current-ticket-" + source.rawValue] = stop != nil
            && manager.stops == 1 && manager.playbackSwitch.committed == nil && commandView.plays.isEmpty
        let replay = commands.makePrimaryAction(for: available, from: sourceSnapshot, renderedPlaying: false)
        replay?()
        checks["online-image-stopped-primary-applies-original-source-" + source.rawValue] = replay != nil
            && manager.stops == 1 && commandView.plays.count == 1 && commandView.plays.first?.0 == reference
            && commandView.plays.first?.1 == sourceSnapshot && manager.playbackSwitch.committed?.ticket != newer
            && manager.playbackSwitch.committed?.ticket.runtime == .systemStill
        let missing = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: .image), title: "Missing image", kind: .image,
            publishedAvailability: .unavailable, capabilities: [.retryDownload], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        OnlineImageCommandRecoveryProbe.requests = []
        let stopMissing = commands.makePrimaryAction(for: missing, from: sourceSnapshot,
            renderedPlaying: true, renderedTicket: manager.playbackSwitch.committed?.ticket)
        stopMissing?()
        checks["missing-but-current-online-image-primary-stops-" + source.rawValue] = stopMissing != nil
            && manager.stops == 2 && manager.playbackSwitch.committed == nil && OnlineImageCommandRecoveryProbe.requests.isEmpty
        let retry = commands.makePrimaryAction(for: missing, from: sourceSnapshot, renderedPlaying: false)
        retry?()
        checks["missing-online-image-primary-still-delegates-retry-without-apply-or-stop-" + source.rawValue] = retry != nil
            && OnlineImageCommandRecoveryProbe.requests == [reference] && commandView.plays.count == 1 && manager.stops == 2

    }
    let onlineView = workspace(.init(downloads: [imageRow], revision: 700), .downloads), onlineCommands = RemovalCommands(onlineView)
    let library = OnlineImageLibrary.shared
    library.snapshot.records = [.init(assetID: .init(source: .pixiv, artworkID: "42", pageIndex: 2), title: "Online image",
        sourceURL: URL(string: "https://example.invalid/42")!, author: nil, authorID: nil, tags: [], relativePath: imageURL.lastPathComponent,
        pixelWidth: 1, pixelHeight: 1, fileSizeBytes: 1, firstDownloadedAt: Date(), revision: imageRevision)]
    library.deletions = []; library.deletion = { _ in
        try FileManager.default.removeItem(at: imageURL)
        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Manifest save failed after unlink"])
    }
    onlineView.presentation.setSelection([imageRef], focused: imageRef)
    controller.recordSuccessfulUse(imageRef, locator: imageRow.locator, sequence: 900)
    _ = await wait { controller.snapshot.recent.contains { $0.reference == imageRef } }
    onlineCommands.remove(); (RecentAlertProbe.alert?.suppressionButton)?.state = .on
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    _ = await wait { !onlineView.edited.isEmpty }
    checks["online-image-delete-dispatch-retains-failed-record-after-confirmed-file-unlink"] = library.deletions == [imageRef]
        && !FileManager.default.fileExists(atPath: imageURL.path) && onlineView.presentation.selectionState.references == [imageRef]
        && !controller.snapshot.excludedLibraryReferences.contains { $0.reference == imageRef }
        && controller.snapshot.recent.contains { $0.reference == imageRef }
        && RecentAlertProbe.alert?.message.contains("Manifest save failed after unlink") == true
    library.deletion = nil; library.snapshot = .init()
    return checks
}

@MainActor private enum OnlineImageCommandRecoveryProbe {
    static var requests: [WallpaperReference] = []
    static func action(for item: WallpaperContentItem) -> (() -> Void)? {
        guard [.wallhaven, .pixiv].contains(item.providerReference.provider), item.capabilities.contains(.retryDownload) else { return nil }
        return { requests.append(item.reference) }
    }
}
