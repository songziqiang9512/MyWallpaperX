// Actual Workspace snapshot capture -> Manager timer/advance -> pure sequence.
// Only monotonic clock/Timer delivery and native prepared/visible ACKs are leaves.
@MainActor enum WorkspaceRotationClock { static var now: TimeInterval = 1_000 }

@MainActor final class WorkspaceRotationTimer {
    let timeInterval: TimeInterval
    private let block: @MainActor (WorkspaceRotationTimer) -> Void
    private(set) var isValid = true
    init(timeInterval: TimeInterval, repeats: Bool,
         block: @escaping @MainActor (WorkspaceRotationTimer) -> Void) {
        precondition(!repeats)
        self.timeInterval = timeInterval
        self.block = block
    }
    static func add(_ timer: WorkspaceRotationTimer) {}
    func invalidate() { isValid = false }
    func deliver() { block(self) }
}

@MainActor func runWorkspaceRotationSourceChecks(root: URL) async throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    func content(_ provider: WallpaperProvider, _ name: String, _ kind: WallpaperMediaKind) -> WallpaperContentItem {
        let ref = WallpaperReference(provider: provider, sourceID: name)
        return WallpaperContentItem(reference: ref, providerReference: ref,
            locator: .init(path: "/controlled/\(name)", titleHint: name, mediaKind: kind), title: name,
            kind: kind, publishedAvailability: .available, capabilities: [.inspect, .play, .organize],
            metadata: .init(resourceRevision: "source-bound-v1"), acquisition: .idle, update: .idle, aliases: [])
    }
    let videos = [content(.videoLibrary, "Scope video A", .video), content(.videoLibrary, "Scope video B", .video),
                  content(.videoLibrary, "Outside video", .video)]
    let images = [content(.staticImageLibrary, "Scope image A", .image), content(.staticImageLibrary, "Scope image B", .image),
                  content(.staticImageLibrary, "Outside image", .image)]
    let downloads = [content(.steamWorkshop, "Scope Steam A", .scene), content(.steamWorkshop, "Scope Steam B", .web),
                     content(.steamWorkshop, "Outside Steam", .web), content(.pixabay, "Scope Pixabay A", .video),
                     content(.pixabay, "Scope Pixabay B", .video), content(.pixabay, "Outside Pixabay", .video)]
    let all = videos + images + downloads
    let scoped = all.filter { $0.title.hasPrefix("Scope") }.map(\.reference)
    let outside = [videos[2], images[2]]
    func wait(_ condition: () -> Bool) async -> Bool {
        let limit = Date().addingTimeInterval(3)
        while !condition(), Date() < limit { try? await Task.sleep(for: .milliseconds(3)) }
        return condition()
    }
    for (index, name) in ["videos", "images", "downloads", "recent", "favorites", "playlist"].enumerated() {
        let store = UserCollectionsStore(url: root.appendingPathComponent("rotation-source-\(name).sqlite3"))
        let initial = try await store.snapshot()
        let suite = "mwx.rotation-source." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WallpaperManager()
        let workspace = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: initial, disposition: .published)),
            manager: manager, images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), defaults: defaults)
        let collections = workspace.collections!
        let playlist = try await collections.createPlaylist(name: "Original source", members: all.map(\.organizationItem))
        let replacement = try await collections.createPlaylist(name: "New manual source", members: outside.map(\.organizationItem))
        try await collections.perform(all.map { .setFavorite($0.organizationItem, true, Date(timeIntervalSince1970: 10)) })
        for (position, value) in all.enumerated() {
            collections.recordSuccessfulUse(value.reference, locator: value.locator,
                sequence: UInt64(position + 1), at: Date(timeIntervalSince1970: Double(100 + position)))
        }
        let flushed = await workspace.flush()
        precondition(flushed == nil)
        workspace.catalog.publish(.init(videos: videos, images: images, downloads: downloads, revision: 1,
            loadedProviders: Set(WallpaperProvider.allCases)))
        let ready = await wait { workspace.presentation.queryResult.items.count == videos.count }
        precondition(ready)
        let page: WallpaperLibraryPage
        let expected: Set<WallpaperReference>
        switch index {
        case 0: page = .videos; expected = Set(videos.prefix(2).map(\.reference))
        case 1: page = .images; expected = Set(images.prefix(2).map(\.reference))
        case 2: page = .downloads; expected = Set(downloads.filter { $0.title.hasPrefix("Scope") }.map(\.reference))
        case 3: page = .recent; expected = Set(scoped)
        case 4: page = .favorites; expected = Set(scoped)
        default: page = .playlist(playlist); expected = Set(scoped)
        }
        _ = workspace.presentation.switchPage(page)
        _ = workspace.presentation.setQueryState(.init(search: "Scope", sort: .sourceOrder))
        guard let first = workspace.presentation.queryResult.items.first else { throw CocoaError(.fileReadUnknown) }
        workspace.play(first.reference)
        guard let captured = manager.libraryPlaybackSequence.pending?.proposal.snapshot else { throw CocoaError(.fileReadUnknown) }
        checks["\(name)-manual-play-captures-the-displayed-filtered-source"] = captured.source == .page(page)
            && Set(captured.entries.map(\.reference)) == expected && captured.entries.count == expected.count
            && captured.sourceQuery?.search == "Scope"
        manager.presentPreparedTarget()
        _ = await workspace.flush()
        let originalProvider = manager.libraryPlaybackSnapshotProvider!
        var globalReads = 0
        manager.libraryPlaybackSnapshotProvider = { reference, source, cause in
            if source == .global { globalReads += 1 }
            return originalProvider(reference, source, cause)
        }
        let global = manager.libraryPlaybackSnapshotProvider?(nil, .global, .manualNavigation)
        precondition(globalReads == 1 && global?.entries.count == all.count)
        globalReads = 0
        _ = workspace.presentation.switchPage(.playlist(replacement))
        _ = workspace.presentation.setQueryState(.init(search: "Outside", sort: .name))
        for mode in [WallpaperPlaybackSequence.Mode.sequential, .random] {
            manager.mode = mode
            manager.refreshAutoSwitchTimerIfNeeded()
            guard let timer = manager.autoSwitchTimer else { throw CocoaError(.fileReadUnknown) }
            WorkspaceRotationClock.now += timer.timeInterval + 0.01
            timer.deliver()
            let pending = manager.libraryPlaybackSequence.pending
            let label = mode == .random ? "random" : "sequential"
            checks["\(name)-\(label)-real-timer-keeps-original-source-after-other-page-browsing"] = pending?.proposal.snapshot.source == .page(page)
                && pending?.proposal.snapshot.entries.map(\.reference) == captured.entries.map(\.reference)
                && pending?.proposal.snapshot.sourceQuery?.search == "Scope"
                && pending.map { expected.contains($0.proposal.entry.reference) } == true
                && pending?.proposal.cause == .timer && globalReads == 0
            manager.presentPreparedTarget()
            _ = await workspace.flush()
        }
        manager.mode = .loop
        manager.refreshAutoSwitchTimerIfNeeded()
        checks["\(name)-loop-setting-does-not-rebind-to-the-browsed-list"] = manager.autoSwitchTimer == nil
            && manager.libraryPlaybackSequence.committed?.snapshot.source == .page(page) && globalReads == 0

        // A new explicit play, unlike browsing or settings, deliberately binds
        // the next rotation to the new displayed list.
        manager.mode = .sequential
        _ = workspace.presentation.setQueryState(.init(sort: .sourceOrder))
        workspace.play(outside[0].reference)
        manager.presentPreparedTarget()
        _ = await workspace.flush()
        guard let timer = manager.autoSwitchTimer else { throw CocoaError(.fileReadUnknown) }
        WorkspaceRotationClock.now += timer.timeInterval + 0.01
        timer.deliver()
        let rebound = manager.libraryPlaybackSequence.pending
        checks["\(name)-a-new-manual-play-is-the-source-rebinding-boundary"] = rebound?.proposal.snapshot.source == .page(.playlist(replacement))
            && rebound?.proposal.snapshot.entries.map(\.reference) == outside.map(\.reference)
            && rebound?.proposal.entry.reference == outside[1].reference && globalReads == 0
        manager.stopAutoSwitchTimer()
    }
    return checks
}
