import AppKit

// ACTUAL_PRIMARY_COMMAND_LEAVES

/// The existing Stop leaf revokes real playback reducers. The factory and
/// fixed-ticket command bodies are the production Commands implementation.
@MainActor func playingImagePrimary(_ reference: WallpaperReference) throws
    -> (commands: WallpaperLibraryCommands, content: WallpaperContentItem) {
    let snapshot = try WallpaperPlaybackSequence.Snapshot(source: .page(.images), revision: 1,
        entries: [.init(reference: reference, runtime: .systemStill, isPlayable: true)])
    let manager = WallpaperManager()
    let proposal = manager.libraryPlaybackSequence.proposeSelection(reference, from: snapshot)!
    let (ticket, _) = manager.playbackSwitch.begin(.systemStill)
    precondition(manager.libraryPlaybackSequence.stage(proposal, ticket: ticket))
    let execution = UUID()
    _ = manager.playbackSwitch.prepared(ticket, executionID: execution)
    _ = manager.playbackSwitch.visible(ticket, executionID: execution)
    precondition(manager.libraryPlaybackSequence.commit(ticket) != nil)
    let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    let workspace = AppliedImageWorkspace(manager, snapshot: snapshot, relationships: relationships)
    let content = WallpaperContentItem(reference: reference, providerReference: reference, locator: .init(mediaKind: .image),
        title: "Playing image", kind: .image, publishedAvailability: .available,
        capabilities: [.play], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    return (WallpaperLibraryCommands(workspace), content)
}
