@main struct WallpaperLibraryWorkspaceAliasHarness {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 3_000_000) }
        precondition(condition(), "Workspace publication did not settle")
    }
    static func content(_ reference: WallpaperReference, _ kind: WallpaperMediaKind) -> WallpaperContentItem {
        .init(reference: reference, providerReference: reference,
              locator: .init(path: "/fixture/" + reference.sourceID, mediaKind: kind), title: "Selected " + reference.sourceID,
              kind: kind, publishedAvailability: .available, capabilities: [.play, .organize, .inspect],
              metadata: .init(resourceRevision: "original"), acquisition: .idle, update: .idle, aliases: [])
    }
    @MainActor static func aliasScenario(_ root: URL, explicit: Bool) async throws -> [String: Bool] {
        let store = UserCollectionsStore(url: root)
        let initial = try await store.snapshot()
        let domain = "mwx.alias-workspace." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = WallpaperManager()
        let workspace = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: initial, disposition: .published)),
            manager: manager, images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), defaults: defaults)
        let backing = WallpaperReference(provider: .videoLibrary, sourceID: "backing")
        let canonical = WallpaperReference(provider: .pixabay, sourceID: "9")
        let image = WallpaperReference(provider: .staticImageLibrary, sourceID: "image")
        let values = [content(backing, .video), content(canonical, .video), content(image, .image)]
        workspace.catalog.publish(.init(videos: [values[0]], images: [values[2]], downloads: [values[1]],
            revision: 1, loadedProviders: Set(WallpaperProvider.allCases)))
        let id = try await workspace.collections!.createPlaylist(name: "Captured", members: values.map(\.organizationItem))
        _ = workspace.presentation.switchPage(.playlists)
        try await wait { workspace.presentation.directoryEntries.contains { $0.id == id } }
        _ = workspace.presentation.switchPage(.playlist(id))
        _ = workspace.presentation.setQueryState(.init(search: "Selected"))
        workspace.play(backing)
        manager.presentPreparedTarget()
        workspace.play(canonical)
        let ticket = manager.libraryPlaybackSequence.pending!.ticket
        let before = manager.sourceUpdates.count
        manager.libraryBackingPublished?(.init(backingVideoID: backing.sourceID, publishedReference: canonical, proof: .publishedDownload))
        try await wait { !workspace.relationships.aliases.isEmpty && manager.sourceUpdates.count > before }
        if explicit { workspace.didEditMembers(of: .playlist(id)) }
        let label = explicit ? "ExplicitMembership" : "Availability"
        let fixed = manager.libraryPlaybackSequence.pending?.ticket == ticket
            && manager.libraryPlaybackSequence.pending?.proposal.entry.reference == canonical
        let previous = manager.libraryPlaybackSequence.committed!
        let preservesCommitted = previous.reference == backing
            && previous.snapshot.entries.contains { $0.reference == backing && $0.isPlayable }
            && !previous.snapshot.entries.contains { $0.reference == canonical && $0.isPlayable }
        manager.presentPreparedTarget()
        let committed = manager.libraryPlaybackSequence.committed!
        let canonicalIDs = try WallpaperLibraryQuery.canonicalReferences(Set(committed.snapshot.entries.map(\.reference)), relationships: workspace.relationships)
        let playableSameResource = committed.snapshot.entries.filter { $0.isPlayable && canonicalIDs[$0.reference] == canonical }
        var checks = [
            label + "AliasKeepsOriginalAcceptedTicket": fixed,
            label + "AliasUpdatesEachCommittedAndPendingLiteralIdentitySeparately": preservesCommitted,
            label + "AliasPreservesPendingCanonicalEntryAvailability": committed.snapshot.entries.contains { $0.reference == canonical && $0.isPlayable },
            label + "AliasDoesNotOfferSameCanonicalAsNextWallpaper": playableSameResource.count == 1 && playableSameResource.first?.reference == canonical
        ]
        // Deleting a preparing source detaches its immutable capture; browsing
        // elsewhere never lends that pending request a different page/query.
        workspace.play(image)
        let pending = manager.libraryPlaybackSequence.pending!
        _ = workspace.presentation.switchPage(.videos)
        _ = workspace.presentation.setQueryState(.init(search: "unrelated"))
        _ = try await workspace.collections!.perform(.deletePlaylist(id))
        workspace.didEditMembers(of: .playlist(id), deleted: true)
        manager.presentPreparedTarget()
        checks[label + "DeletedPendingSourceCommitsDetachedFixedCapture"] = manager.libraryPlaybackSequence.committed?.reference == image
            && manager.libraryPlaybackSequence.committed?.ticket == pending.ticket
            && manager.libraryPlaybackSequence.committed?.snapshot.source == .page(.playlist(id))
            && manager.libraryPlaybackSequence.committed?.snapshot.sourceQuery?.search == "Selected"
            && manager.libraryPlaybackSequence.committed?.isDetached == true
        return checks
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks = try await aliasScenario(root.appendingPathComponent("availability.sqlite3"), explicit: false)
        checks.merge(try await aliasScenario(root.appendingPathComponent("membership.sqlite3"), explicit: true)) { _, newer in newer }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
