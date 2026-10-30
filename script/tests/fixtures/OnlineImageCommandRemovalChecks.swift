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
    checks.merge(try await runSourceDeletionQueryChecks(root: root), uniquingKeysWith: { _, newer in newer })
    return checks
}

@MainActor private func runSourceDeletionQueryChecks(root: URL) async throws -> [String: Bool] {
    var checks: [String: Bool] = [:], suites: [(UserDefaults, String)] = []
    defer { for (defaults, suite) in suites { defaults.removePersistentDomain(forName: suite) } }
    func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
        return condition()
    }
    func row(_ reference: WallpaperReference, path: String, backing: WallpaperReference? = nil,
             availability: WallpaperPublishedAvailability = .available) -> WallpaperContentItem {
        .init(reference: reference, providerReference: backing ?? reference, locator: .init(path: path, mediaKind: .video),
            title: reference.sourceID, kind: .video, publishedAvailability: availability, capabilities: [.play, .organize, .delete],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    func fixture(_ name: String, fixed: [WallpaperContentItem], current: [WallpaperContentItem],
                 aliases: [WallpaperReferenceAlias] = []) async throws -> (RemovalCommands, RemovalWorkspace, UserCollectionsController) {
        let store = UserCollectionsStore(url: root.appendingPathComponent("preflight-\(name).sqlite3")), initial = try await store.snapshot()
        let snapshot = UserCollectionsSnapshot(revision: initial.revision, resetEpoch: initial.resetEpoch, migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: aliases, locators: [])
        let controller = UserCollectionsController(store: store, snapshot: snapshot)
        let suite = "mwx.removal.preflight." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        suites.append((defaults, suite))
        let view = RemovalWorkspace(controller, .init(videos: current, revision: 1), defaults: defaults)
        view.presentation.switchPage(.videos)
        view.presentation.setSelection(Set(fixed.map(\.reference)), focused: fixed.first?.reference, isSelecting: true)
        let commands = RemovalCommands(view)
        commands.manager.wallpapers = current.filter { $0.providerReference.provider == .videoLibrary }
            .map { .init(id: $0.providerReference.sourceID, path: $0.locator.path!) }
        return (commands, view, controller)
    }
    func begin(_ commands: RemovalCommands, _ fixed: [WallpaperContentItem]) {
        commands.remove(fixed); RecentAlertProbe.alert?.suppressionButton?.state = .on
        RecentAlertProbe.finish(.alertFirstButtonReturn)
    }
    let refs = (0..<7).map { WallpaperReference(provider: .videoLibrary, sourceID: "preflight-\($0)") }
    let rows = refs.map { row($0, path: root.appendingPathComponent($0.sourceID + ".mp4").path) }
    let remote = WallpaperReference(provider: .steamWorkshop, sourceID: "preflight-remote")
    let remoteRow = row(remote, path: root.appendingPathComponent("preflight-steam.mp4").path, backing: refs[2])
    do {
        let fixed = [rows[0], rows[1], remoteRow]
        let (commands, view, controller) = try await fixture("batch", fixed: fixed, current: fixed)
        WallpaperLibraryQuery.resolverInitializationCount = 0
        begin(commands, fixed)
        let started = await wait { commands.manager.requested.count == 2 }
        checks["delete-preflight-builds-one-resolver-for-a-mixed-batch"] = started && WallpaperLibraryQuery.resolverInitializationCount == 1
        commands.manager.finish(Set(refs.prefix(2).map(\.sourceID)))
        let steamStarted = await wait { commands.steam.requested == [remote.sourceID] }
        checks["delete-preflight-keeps-a-proven-remote-identity-with-its-original-owner"] = steamStarted
            && commands.manager.requested == refs.prefix(2).map(\.sourceID) && commands.pixabay.requested.isEmpty
        commands.steam.finish([remote.sourceID: true])
        _ = await wait { !view.edited.isEmpty }
        checks["delete-preflight-preserves-each-canonical-success-receipt"] = Set(controller.snapshot.excludedLibraryReferences.map(\.reference)) == Set(fixed.map(\.reference))
    }
    do {
        let cycle = [WallpaperReferenceAlias(alias: refs[1], canonical: refs[2], proof: .publishedDownload),
                     .init(alias: refs[2], canonical: refs[1], proof: .publishedDownload)]
        let (commands, view, controller) = try await fixture("cycle", fixed: Array(rows.prefix(2)), current: [rows[0]], aliases: cycle)
        begin(commands, Array(rows.prefix(2)))
        let started = await wait { commands.manager.requested == [refs[0].sourceID] }
        commands.manager.finish([refs[0].sourceID])
        _ = await wait { !view.edited.isEmpty }
        checks["delete-preflight-keeps-a-requested-cycle-failure-local"] = started
            && controller.snapshot.excludedLibraryReferences.map(\.reference) == [refs[0]]
            && RecentAlertProbe.alert?.message.contains("源文件不可用或条目已变化") == true
    }
    do {
        let conflicts = [WallpaperReferenceAlias(alias: refs[2], canonical: refs[3], proof: .publishedDownload),
                         .init(alias: refs[2], canonical: refs[4], proof: .publishedDownload)]
        let (commands, view, controller) = try await fixture("init-failure", fixed: Array(rows.prefix(2)), current: Array(rows.prefix(2)), aliases: conflicts)
        begin(commands, Array(rows.prefix(2)))
        _ = await wait { !view.edited.isEmpty }
        checks["delete-preflight-initialization-failure-keeps-all-source-owners-idle"] = commands.manager.requested.isEmpty
            && commands.steam.requested.isEmpty && commands.pixabay.requested.isEmpty && controller.snapshot.excludedLibraryReferences.isEmpty
            && RecentAlertProbe.alert?.message.components(separatedBy: "源文件不可用或条目已变化").count == 3
    }
    do {
        let unicodePath = root.path + "/preflight-\u{e9}.mp4"
        let owned = row(refs[5], path: "/controlled/steam/borrowed.mp4")
        let fixed = Array(rows.prefix(4)) + [row(refs[4], path: unicodePath), owned]
        let current = [rows[0], row(refs[1], path: rows[1].locator.path!, backing: refs[6]),
            row(refs[2], path: rows[2].locator.path!, availability: .unavailable), rows[3],
            row(refs[4], path: root.path + "/preflight-e\u{301}.mp4"), owned]
        precondition(!unicodePath.utf8.elementsEqual(current[4].locator.path!.utf8))
        let aliases = [WallpaperReferenceAlias(alias: refs[3], canonical: remote, proof: .publishedDownload)]
        let (commands, view, controller) = try await fixture("changed", fixed: fixed, current: current, aliases: aliases)
        begin(commands, fixed)
        let started = await wait { commands.manager.requested == [refs[0].sourceID] }
        commands.manager.finish([refs[0].sourceID])
        _ = await wait { !view.edited.isEmpty }
        checks["delete-preflight-rejects-only-changed-backing-availability-canonical-and-path-bytes"] = started
            && controller.snapshot.excludedLibraryReferences.map(\.reference) == [refs[0]] && commands.steam.requested.isEmpty
            && RecentAlertProbe.alert?.message.components(separatedBy: "源文件不可用或条目已变化").count == 5
        checks["delete-preflight-retains-the-source-owned-root-rejection"] = RecentAlertProbe.alert?.message.contains("该文件由下载来源管理") == true
    }
    do {
        let pixabay = row(.init(provider: .pixabay, sourceID: "preflight-reset"), path: root.appendingPathComponent("preflight-reset.mp4").path)
        try Data([29]).write(to: URL(fileURLWithPath: pixabay.locator.path!))
        let fixed = [rows[0], pixabay]
        let (commands, view, controller) = try await fixture("reset", fixed: fixed, current: fixed)
        begin(commands, fixed)
        let started = await wait { commands.manager.requested == [refs[0].sourceID] }
        try await controller.reset()
        commands.manager.finish([refs[0].sourceID])
        let refreshed = await wait { view.catalog.refreshes == 1 }
        checks["delete-preflight-reset-during-source-await-revokes-later-owners-and-relationship-writes"] = started && refreshed
            && commands.pixabay.requested.isEmpty && FileManager.default.fileExists(atPath: pixabay.locator.path!)
            && controller.snapshot.excludedLibraryReferences.isEmpty && view.edited.isEmpty
    }
    return checks
}

@MainActor private enum OnlineImageCommandRecoveryProbe {
    static var requests: [WallpaperReference] = []
    static func action(for item: WallpaperContentItem) -> (() -> Void)? {
        guard [.wallhaven, .pixiv].contains(item.providerReference.provider), item.capabilities.contains(.retryDownload) else { return nil }
        return { requests.append(item.reference) }
    }
}
