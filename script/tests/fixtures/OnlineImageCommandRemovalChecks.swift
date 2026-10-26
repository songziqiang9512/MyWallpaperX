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
        let reapply = commands.makePrimaryAction(for: available, from: sourceSnapshot,
            renderedPlaying: true, renderedTicket: oldTicket)
        reapply?()
        checks["applied-online-image-primary-reapplies-without-stopping-" + source.rawValue] = reapply != nil
            && manager.stops == 0 && commandView.plays.count == 1 && commandView.plays.first?.0 == reference
            && commandView.plays.first?.1 == sourceSnapshot && manager.playbackSwitch.committed?.ticket != oldTicket
            && manager.playbackSwitch.committed?.ticket.runtime == .systemStill
        let missing = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: .image), title: "Missing image", kind: .image,
            publishedAvailability: .unavailable, capabilities: [.retryDownload], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        OnlineImageCommandRecoveryProbe.requests = []
        let retry = commands.makePrimaryAction(for: missing, from: sourceSnapshot,
            renderedPlaying: true, renderedTicket: manager.playbackSwitch.committed?.ticket)
        retry?()
        checks["missing-online-image-primary-still-delegates-retry-without-apply-or-stop-" + source.rawValue] = retry != nil
            && OnlineImageCommandRecoveryProbe.requests == [reference] && commandView.plays.count == 1 && manager.stops == 0
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
    onlineCommands.remove(); (RecentAlertProbe.alert?.accessoryView as? NSButton)?.state = .on
    RecentAlertProbe.finish(.alertFirstButtonReturn)
    _ = await wait { !onlineView.edited.isEmpty }
    checks["online-image-delete-dispatch-retains-failed-record-after-confirmed-file-unlink"] = library.deletions == [imageRef]
        && !FileManager.default.fileExists(atPath: imageURL.path) && onlineView.presentation.selectionState.references == [imageRef]
        && !controller.snapshot.excludedLibraryReferences.contains { $0.reference == imageRef }
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
