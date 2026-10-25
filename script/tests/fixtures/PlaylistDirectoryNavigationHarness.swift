import Combine
import Foundation

@MainActor private final class NavigationSteamLeaf {
    enum Section: Equatable { case personal, discovery }
    var isBrowsingAuthorWorkshop = false
    var pendingDownloadsScrollRestoreOffsetY: Double? = 42
    var events: [String] = []
    func returnToDiscoveryBrowse(selectOrigin: Bool) {
        events.append("return-author-\(selectOrigin)"); isBrowsingAuthorWorkshop = false
    }
    func enterBrowseSection(_ section: Section) {
        events.append(section == .personal ? "enter-personal" : "enter-discovery")
    }
    func prepareForBrowserEntry() { events.append("prepare") }
}

@MainActor private final class NavigationGridLeaf {
    var scrollToTopCalls = 0
    func scrollToTop() { scrollToTopCalls += 1 }
}

@MainActor private final class NavigationWorkspace {
    let collections: UserCollectionsController
    let presentation: WallpaperLibraryPresentation
    let catalog: WallpaperLibraryCatalog
    var relationships: UserCollectionsSnapshot { collections.snapshot }
    var playbackRequests: [WallpaperReference] = []
    init(collections: UserCollectionsController, presentation: WallpaperLibraryPresentation, catalog: WallpaperLibraryCatalog) {
        self.collections = collections; self.presentation = presentation; self.catalog = catalog
    }
    func play(_ reference: WallpaperReference) { playbackRequests.append(reference) }
}

/// This shell compiles the product's declarations without editing their bodies.
/// It supplies only the source/input leaves and forwards test entry points to
/// the actual private methods; it owns no additional return/navigation state.
@MainActor private final class CompositionNavigationChecks {
    let workspace: NavigationWorkspace
    let steam = NavigationSteamLeaf()
    let grid = NavigationGridLeaf()
    var permitsInput = true
    var onNavigationContextChanged: (() -> Void)?

    init(_ workspace: NavigationWorkspace) { self.workspace = workspace }

    // ACTUAL_DIRECTORY_NAVIGATION

    func openDirectoryCard(_ id: UUID) { openPlaylist(id, fromDirectory: true) }
    func openWithoutDirectoryContext(_ id: UUID) { openPlaylist(id, fromDirectory: false) }
    var storesDirectoryReturnContext: Bool { directoryReturnContext != nil }
    func publishRelationships() {
        workspace.presentation.update(catalog: workspace.catalog, relationships: workspace.relationships)
        invalidateDirectoryReturnContext()
    }
}

@main enum PlaylistDirectoryNavigationHarness {
    @MainActor static func main() async throws {
        var checks: [String: Bool] = [:]
        let store = UserCollectionsStore(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let initial = try await store.snapshot()
        let collections = UserCollectionsController(store: store, snapshot: initial)
        let suite = "mwx.directory-navigation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let presentation = WallpaperLibraryPresentation(collections: collections, defaults: defaults)
        let reference = WallpaperReference(provider: .videoLibrary, sourceID: "navigation-video")
        let content = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(path: "/isolated/navigation-video.mp4", mediaKind: .video), title: "Navigation video", kind: .video,
            publishedAvailability: .available, capabilities: [.inspect, .play, .organize], metadata: .init(),
            acquisition: .idle, update: .idle, aliases: [])
        let a = try await collections.createPlaylist(name: "Playlist A", members: [content.organizationItem])
        let b = try await collections.createPlaylist(name: "Playlist B")
        let c = try await collections.createPlaylist(name: "Playlist C")
        let workspace = NavigationWorkspace(collections: collections, presentation: presentation,
            catalog: .init(videos: [content], loadedProviders: [.videoLibrary]))
        let owner = CompositionNavigationChecks(workspace)
        var toolbarContextRefreshes = 0
        owner.onNavigationContextChanged = { toolbarContextRefreshes += 1 }
        owner.publishRelationships()
        owner.navigate(to: .playlists)
        let directoryQuery = WallpaperLibraryQueryState(search: "Playlist", sort: .name, ascending: false, preferredColumns: 4)
        presentation.setQueryState(directoryQuery)
        presentation.setDirectoryScrollAnchor(b, offset: -17.25, atTop: false)
        let directoryIDs = presentation.directoryEntries.map(\.id)
        let beforeNavigation = try await store.snapshot()
        owner.openDirectoryCard(a)
        let firstReturn = owner.makeDirectoryReturnAction()
        checks["actual-directory-card-open-creates-return-context-for-the-same-uuid"] = presentation.page == .playlist(a)
            && firstReturn != nil && presentation.queryResult.items.map(\.reference) == [reference] && directoryIDs == [c, b, a]
        presentation.setQueryState(.init(search: "different member query", sort: .name, preferredColumns: 3))
        firstReturn?()
        checks["actual-return-restores-directory-query-density-and-uuid-anchor"] = presentation.page == .playlists
            && presentation.queryState == directoryQuery && presentation.directoryEntries.map(\.id) == directoryIDs
            && presentation.directoryScrollAnchor == b && presentation.directoryScrollOffset == -17.25
            && presentation.directoryScrollAtTop == false && owner.makeDirectoryReturnAction() == nil
        let afterNavigation = try await store.snapshot()
        checks["directory-return-does-not-enter-steam-play-scroll-top-or-write-relationships"] = owner.steam.events.isEmpty
            && owner.steam.pendingDownloadsScrollRestoreOffsetY == 42 && workspace.playbackRequests.isEmpty
            && owner.grid.scrollToTopCalls == 0 && afterNavigation == beforeNavigation

        owner.navigate(to: .playlist(b))
        checks["actual-sidebar-direct-playlist-navigation-has-no-return-context"] = presentation.page == .playlist(b)
            && owner.makeDirectoryReturnAction() == nil
        owner.navigate(to: .playlists); owner.openDirectoryCard(a)
        let beforeSidebarReselect = owner.grid.scrollToTopCalls
        owner.navigate(to: .playlist(a))
        checks["same-playlist-sidebar-reselection-revokes-directory-return-and-retains-native-top-behavior"] = owner.makeDirectoryReturnAction() == nil
            && owner.grid.scrollToTopCalls == beforeSidebarReselect + 1 && presentation.page == .playlist(a)

        owner.navigate(to: .playlists); owner.openDirectoryCard(a)
        let obsoleteAdmission = owner.makeDirectoryReturnAction()!
        owner.navigate(to: .videos); owner.navigate(to: .playlists); owner.openDirectoryCard(a)
        obsoleteAdmission()
        checks["A-sidebar-directory-A-rejects-old-held-return-despite-same-id-page-and-epoch"] = presentation.page == .playlist(a)
            && owner.makeDirectoryReturnAction() != nil
        owner.makeDirectoryReturnAction()?()
        checks["new-admission-return-still-works-after-old-held-action-is-rejected"] = presentation.page == .playlists

        owner.openDirectoryCard(a)
        let modalHeldReturn = owner.makeDirectoryReturnAction()!
        owner.permitsInput = false
        modalHeldReturn()
        checks["new-held-return-input-is-rejected-while-main-input-leaf-is-blocked"] = presentation.page == .playlist(a)
            && owner.makeDirectoryReturnAction() != nil
        owner.permitsInput = true
        modalHeldReturn()
        checks["ending-modal-input-block-keeps-the-current-return-admission-usable"] = presentation.page == .playlists

        owner.openDirectoryCard(a)
        let renameHeldReturn = owner.makeDirectoryReturnAction()!
        let previousMetadata = collections.snapshot.playlists.first { $0.id == a }!.metadata
        var renamed = previousMetadata; renamed.name = "Playlist A renamed"
        _ = try await collections.editPlaylistMetadata(id: a, expected: previousMetadata, replacement: renamed,
            expectedEpoch: collections.snapshot.resetEpoch)
        owner.publishRelationships()
        checks["ordinary-real-metadata-rename-does-not-clear-directory-return-context"] = presentation.page == .playlist(a)
            && owner.makeDirectoryReturnAction() != nil && owner.storesDirectoryReturnContext
        renameHeldReturn()
        checks["return-after-real-rename-keeps-directory-query-and-original-uuid-anchor"] = presentation.page == .playlists
            && presentation.queryState == directoryQuery && presentation.directoryScrollAnchor == b
            && presentation.directoryScrollOffset == -17.25 && presentation.directoryEntries.contains { $0.id == a && $0.name == renamed.name }

        owner.openDirectoryCard(a)
        let deletedHeldReturn = owner.makeDirectoryReturnAction()!
        try await collections.perform(.deletePlaylist(a))
        owner.publishRelationships()
        let afterDeletion = try await store.snapshot()
        deletedHeldReturn()
        let afterRejectedDeletionReturn = try await store.snapshot()
        checks["actual-target-deletion-clears-return-context-and-rejects-held-action"] = presentation.page == .playlists
            && owner.makeDirectoryReturnAction() == nil && !owner.storesDirectoryReturnContext
            && !presentation.directoryEntries.contains { $0.id == a }
            && afterRejectedDeletionReturn == afterDeletion
        owner.openDirectoryCard(a)
        checks["deleted-directory-card-cannot-open-a-ghost-playlist"] = presentation.page == .playlists && owner.makeDirectoryReturnAction() == nil

        owner.openDirectoryCard(b)
        let resetHeldReturn = owner.makeDirectoryReturnAction()!
        let originalB = collections.snapshot.playlists.first { $0.id == b }!, oldEpoch = collections.snapshot.resetEpoch
        try await collections.reset()
        owner.publishRelationships()
        checks["real-reset-invalidates-old-directory-return-context"] = collections.snapshot.resetEpoch != oldEpoch
            && owner.makeDirectoryReturnAction() == nil && !owner.storesDirectoryReturnContext
        try await collections.perform(.createPlaylistWithCover(originalB, nil))
        owner.publishRelationships(); owner.navigate(to: .playlists); owner.openDirectoryCard(b)
        resetHeldReturn()
        checks["same-uuid-recreated-after-real-reset-cannot-revive-old-held-return"] = presentation.page == .playlist(b)
            && owner.makeDirectoryReturnAction() != nil && collections.snapshot.playlists.map(\.id) == [b]
        owner.makeDirectoryReturnAction()?()
        checks["new-epoch-return-remains-usable-after-rejecting-old-epoch-action"] = presentation.page == .playlists
        owner.openWithoutDirectoryContext(b)
        checks["non-directory-open-entry-explicitly-keeps-return-context-absent"] = presentation.page == .playlist(b)
            && owner.makeDirectoryReturnAction() == nil

        let beforeSteam = owner.steam.events.count
        owner.navigate(to: .workshop)
        checks["actual-steam-navigation-uses-recorded-original-entry-leaves-as-positive-control"] = owner.steam.events.count == beforeSteam + 2
            && owner.steam.events.suffix(2).elementsEqual(["enter-discovery", "prepare"])
            && owner.steam.pendingDownloadsScrollRestoreOffsetY == nil
        checks["actual-context-lifecycle-notifies-toolbar-without-entering-playback"] = workspace.playbackRequests.isEmpty
            && toolbarContextRefreshes > 0
        workspace.play(reference)
        checks["recording-playback-leaf-detects-an-invocation-as-positive-control"] = workspace.playbackRequests == [reference]
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
