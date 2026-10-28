import AppKit
import Foundation

// Source admission/opening and Workspace publication are controlled leaves.
// Query, reference/relationship values, native menu items and their action
// handlers are the production implementations. No network or renderer runs.
@MainActor final class RecoveryCollections { var isResetting = false }
@MainActor final class RecoveryPresentation {
    var canEditCollections = true
    var page: WallpaperLibraryPage = .favorites
}
@MainActor final class WallpaperLibraryWorkspace {
    let manager = WallpaperManager()
    var relationships: UserCollectionsSnapshot
    var catalog = WallpaperLibraryCatalog()
    var collections: RecoveryCollections? = RecoveryCollections()
    let presentation = RecoveryPresentation()
    var plays: [WallpaperReference] = []
    init(_ reference: WallpaperReference) {
        relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [.init(reference: reference, favoritedAt: nil)],
            recent: [], aliases: [], locators: [.init(reference: reference,
                locator: .init(titleHint: "Saved title", mediaKind: .video))])
    }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        try WallpaperLibraryQuery.resolve([reference], catalog: catalog, relationships: relationships)[0]
    }
    func isPlaying(_ reference: WallpaperReference) -> Bool { false }
    func capturePlaybackSnapshot(for reference: WallpaperReference) throws -> WallpaperPlaybackSequence.Snapshot {
        try .init(source: .single(reference), revision: 1, entries: [.init(reference: reference, runtime: .video, isPlayable: true)])
    }
    func play(_ reference: WallpaperReference, from snapshot: WallpaperPlaybackSequence.Snapshot) { plays.append(reference) }
}
@MainActor final class WallpaperManager {
    var playbackSwitch = PlaybackSwitchTransaction()
    var libraryPlaybackSequence = WallpaperPlaybackSequence()
    var stops = 0
    func stopCurrentPlayback() { stops += 1 }
}
@MainActor final class WallpaperLibraryImportCoordinator {
    static func canRelocate(_ content: WallpaperContentItem, relationships: UserCollectionsSnapshot) -> Bool { false }
    func chooseReplacement(for reference: WallpaperReference) { preconditionFailure("Remote recovery cannot invoke local relocation") }
}
@MainActor final class WallpaperLibraryCommands {
    let workspace: WallpaperLibraryWorkspace
    let manager: WallpaperManager
    let steam: SteamWorkshopService
    let pixabay: PixabayService
    let imports = WallpaperLibraryImportCoordinator()
    var canOrganize: Bool { workspace.presentation.canEditCollections }
    init(_ workspace: WallpaperLibraryWorkspace, _ steam: SteamWorkshopService, _ pixabay: PixabayService) {
        self.workspace = workspace; manager = workspace.manager; self.steam = steam; self.pixabay = pixabay
    }
    // ACTUAL_PRIMARY_FACTORY
}
@MainActor final class RecoverySteamClient { var accountEpoch: UInt64 = 1 }
@MainActor final class SteamWorkshopService {
    let steamServiceClient = RecoverySteamClient()
    var existingRecords = Set<String>()
    var downloads: [String] = []
    var pages: [URL] = []
    // ACTUAL_STEAM_ID_VALIDATION
    // ACTUAL_STEAM_RECOVERY_URL
    func latestDownloadRecord(for id: String) -> String? { existingRecords.contains(id) ? id : nil }
    func downloadWorkshopItem(id: String, pageTitle: String?) { downloads.append(id) }
    func openWorkshopDetailPage(itemID: String) { if let url = recoveryWorkshopDetailURL(itemID: itemID) { pages.append(url) } }
}
struct PixabayVideoItem: Equatable { let id: Int; let metadataVersion: Int }
@MainActor final class PixabayService {
    var items: [PixabayVideoItem] = []
    var retriedIDs: [Int] = []
    var pages: [URL] = []
    // ACTUAL_PIXABAY_SOURCE_URL
    func retryDownload(id: Int) { retriedIDs.append(id) }
    func openVideoSourcePage(id: Int) { if let url = Self.videoSourcePageURL(id: id) { pages.append(url) } }
}

@main enum WallpaperLibraryDownloadRecoveryChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let steamRef = WallpaperReference(provider: .steamWorkshop, sourceID: "700000001")
        let pixabayRef = WallpaperReference(provider: .pixabay, sourceID: "125")
        func setup(_ reference: WallpaperReference = steamRef) -> (WallpaperLibraryWorkspace, SteamWorkshopService, PixabayService) {
            (WallpaperLibraryWorkspace(reference), SteamWorkshopService(), PixabayService())
        }
        func menu(_ workspace: WallpaperLibraryWorkspace, _ steam: SteamWorkshopService, _ pixabay: PixabayService,
                  _ reference: WallpaperReference = steamRef) throws -> NSMenu? {
            WallpaperLibraryDownloadRecovery.makeMenu(for: try workspace.content(for: reference),
                workspace: workspace, steam: steam, pixabay: pixabay)
        }
        func invoke(_ menu: NSMenu, _ title: String) {
            let item = menu.items.first { $0.title == title }!
            precondition(item.isEnabled)
            _ = (item.target as? NSObject)?.perform(item.action, with: item)
        }
        func available(_ reference: WallpaperReference) -> WallpaperContentItem {
            .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
                title: "Returned", kind: .video, publishedAvailability: .available,
                capabilities: [.play, .organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let commands = WallpaperLibraryCommands(workspace, steam, pixabay)
            let recovery = commands.makePrimaryAction(for: try workspace.content(for: steamRef))
            recovery?()
            checks["actual-commands-return-recovers-deleted-steam-without-stop-or-play"] = recovery != nil
                && steam.downloads == [steamRef.sourceID] && workspace.plays.isEmpty && workspace.manager.stops == 0
            workspace.catalog = .init(downloads: [available(steamRef)])
            commands.makePrimaryAction(for: available(steamRef))?()
            checks["published-resource-keeps-original-apply-factory-instead-of-downloading"] = workspace.plays == [steamRef]
                && steam.downloads.count == 1 && workspace.manager.stops == 0
        }
        do {
            for reference in [steamRef, pixabayRef] {
                let (workspace, steam, pixabay) = setup(reference)
                let backing = WallpaperReference(provider: .videoLibrary, sourceID: "Retained missing backing")
                let old = workspace.relationships
                workspace.relationships = .init(revision: old.revision + 1, resetEpoch: old.resetEpoch, migrationManifestID: nil,
                    playlists: [], members: [], favorites: old.favorites, recent: [],
                    aliases: [.init(alias: backing, canonical: reference, proof: .publishedDownload)], locators: old.locators)
                let missing = WallpaperContentItem(reference: backing, providerReference: backing,
                    locator: .init(path: "/isolated/missing-video.mp4", mediaKind: .video), title: "Missing backing", kind: .video,
                    publishedAvailability: .unavailable, capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
                workspace.catalog = .init(videos: [missing])
                pixabay.items = [.init(id: 125, metadataVersion: 1)]
                let projected = try workspace.content(for: reference)
                let recovery = WallpaperLibraryCommands(workspace, steam, pixabay).makePrimaryAction(for: projected)
                recovery?()
                let recoveryMenu = try menu(workspace, steam, pixabay, reference)
                checks["trusted-\(reference.provider.rawValue)-missing-backing-retains-canonical-recovery"] = projected.reference == reference
                    && projected.providerReference == backing && recovery != nil
                    && (reference == steamRef ? steam.downloads == [steamRef.sourceID] : pixabay.retriedIDs == [125])
                    && recoveryMenu?.items.count == 2 && workspace.plays.isEmpty
            }
            let (workspace, steam, pixabay) = setup()
            let unproven = WallpaperReference(provider: .videoLibrary, sourceID: "No alias proof")
            workspace.catalog = .init(videos: [.init(reference: steamRef, providerReference: unproven,
                locator: .init(mediaKind: .video), title: "Unproven backing", kind: .video,
                publishedAvailability: .unavailable, capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])])
            let current = try workspace.content(for: steamRef)
            let rejectedMenu = try menu(workspace, steam, pixabay)
            checks["unproven-cross-provider-backing-cannot-authorize-recovery"] = WallpaperLibraryCommands(workspace, steam, pixabay).makePrimaryAction(for: current) == nil
                && rejectedMenu == nil
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let before = workspace.relationships
            let original = try menu(workspace, steam, pixabay)!
            checks["deleted-steam-relationship-has-real-download-and-source-page-actions"] = original.items.map(\.title) == ["重新下载", "查看创意工坊页面"]
            invoke(original, "重新下载"); invoke(original, "查看创意工坊页面")
            checks["steam-actions-use-exact-original-owner-id-without-changing-relationships"] = steam.downloads == [steamRef.sourceID]
                && steam.pages.map(\.absoluteString) == ["https://steamcommunity.com/sharedfiles/filedetails/?id=700000001"]
                && workspace.relationships == before && pixabay.retriedIDs.isEmpty
            let next = WallpaperReference(provider: .steamWorkshop, sourceID: "700000002")
            workspace.catalog = .init(downloads: [available(next)])
            invoke(original, "重新下载")
            checks["held-menu-never-substitutes-another-published-workshop-id"] = steam.downloads == [steamRef.sourceID, steamRef.sourceID]
            steam.steamServiceClient.accountEpoch += 1
            invoke(original, "重新下载"); invoke(original, "查看创意工坊页面")
            checks["changed-steam-account-revokes-held-recovery-actions"] = steam.downloads.count == 2 && steam.pages.count == 1
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let original = try menu(workspace, steam, pixabay)!
            workspace.catalog = .init(downloads: [available(steamRef)])
            invoke(original, "重新下载"); invoke(original, "查看创意工坊页面")
            checks["resource-return-suppresses-old-recovery-actions-and-menu"] = try steam.downloads.isEmpty && steam.pages.isEmpty
                && (try menu(workspace, steam, pixabay)) == nil
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let original = try menu(workspace, steam, pixabay)!
            workspace.relationships = .init(revision: 2, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: workspace.relationships.favorites, recent: [], aliases: [], locators: [])
            invoke(original, "重新下载"); invoke(original, "查看创意工坊页面")
            checks["reset-revokes-all-held-download-recovery-actions"] = steam.downloads.isEmpty && steam.pages.isEmpty
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let original = try menu(workspace, steam, pixabay)!
            workspace.presentation.page = .videos
            invoke(original, "重新下载")
            checks["page-change-cannot-lend-old-menu-a-new-page-selection"] = steam.downloads.isEmpty
            workspace.presentation.page = .favorites
            workspace.collections?.isResetting = true
            invoke(original, "重新下载")
            checks["inflight-reset-refuses-menu-and-queued-action"] = try steam.downloads.isEmpty && (try menu(workspace, steam, pixabay)) == nil
            workspace.collections?.isResetting = false
            workspace.presentation.canEditCollections = false
            checks["read-only-recovery-does-not-admit-source-writes"] = (try menu(workspace, steam, pixabay)) == nil
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let original = try menu(workspace, steam, pixabay)!
            let other = WallpaperReference(provider: .steamWorkshop, sourceID: "700000002")
            workspace.relationships = .init(revision: 2, resetEpoch: workspace.relationships.resetEpoch, migrationManifestID: nil,
                playlists: [], members: [], favorites: workspace.relationships.favorites, recent: [],
                aliases: [.init(alias: steamRef, canonical: other, proof: .restoredSourceRecord)], locators: [])
            invoke(original, "重新下载")
            checks["late-alias-cannot-retarget-a-held-download-command"] = steam.downloads.isEmpty
        }
        do {
            let (workspace, steam, pixabay) = setup()
            let original = try menu(workspace, steam, pixabay)!
            workspace.relationships = .init(revision: 2, resetEpoch: workspace.relationships.resetEpoch, migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: workspace.relationships.locators)
            invoke(original, "重新下载")
            checks["locator-alone-does-not-authorize-recovering-unrelated-remote-items"] = try steam.downloads.isEmpty && (try menu(workspace, steam, pixabay)) == nil
        }
        do {
            let rejected = ["video:700000001", "000000", "0", "12", "１２３４５６", "700000001&x=1", " 700000001"]
            checks["synthetic-video-and-non-workshop-ids-never-create-network-actions"] = try rejected.allSatisfy { id in
                let reference = WallpaperReference(provider: .steamWorkshop, sourceID: id)
                let (workspace, steam, pixabay) = setup(reference)
                return try menu(workspace, steam, pixabay, reference) == nil
            }
            let reference = WallpaperReference(provider: .steamWorkshop, sourceID: "000123")
            let (workspace, steam, pixabay) = setup(reference)
            let preserved = try menu(workspace, steam, pixabay, reference)!
            invoke(preserved, "重新下载")
            checks["original-workshop-leading-zero-validation-and-opaque-id-are-preserved"] = steam.downloads == ["000123"]
                && steam.recoveryWorkshopDetailURL(itemID: "000123")?.query == "id=000123"
            steam.existingRecords.insert(reference.sourceID)
            checks["existing-record-keeps-its-original-source-menu-instead-of-duplicate-recovery"] = (try menu(workspace, steam, pixabay, reference)) == nil
        }
        do {
            let (workspace, steam, pixabay) = setup()
            workspace.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            let failed = WallpaperContentItem(reference: steamRef, providerReference: steamRef,
                locator: .init(mediaKind: .video), title: "Failed original task", kind: .video,
                publishedAvailability: .remote, capabilities: [.inspect, .retryDownload], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
            workspace.catalog = .init(downloads: [failed])
            let commands = WallpaperLibraryCommands(workspace, steam, pixabay)
            let retry = commands.makePrimaryAction(for: failed)
            retry?()
            checks["return-retries-real-source-capability-without-requiring-a-user-relationship"] = retry != nil && steam.downloads == [steamRef.sourceID]
            let busy = WallpaperContentItem(reference: steamRef, providerReference: steamRef,
                locator: failed.locator, title: failed.title, kind: .video, publishedAvailability: .remote,
                capabilities: [.inspect, .cancelDownload], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            workspace.catalog = .init(downloads: [busy])
            retry?()
            checks["held-return-retry-cannot-restart-a-now-busy-source-task"] = steam.downloads.count == 1
                && commands.makePrimaryAction(for: busy) == nil
            workspace.catalog = .init(downloads: [available(steamRef)])
            retry?()
            checks["download-recovery-never-turns-into-play-after-resource-publication"] = steam.downloads.count == 1
                && WallpaperLibraryDownloadRecovery.makePrimaryAction(for: available(steamRef), workspace: workspace, steam: steam, pixabay: pixabay) == nil
        }
        do {
            let (workspace, steam, pixabay) = setup(pixabayRef)
            let pageOnly = try menu(workspace, steam, pixabay, pixabayRef)!
            checks["uncached-pixabay-metadata-retains-fixed-id-retry-without-inventing-download-url"] = pageOnly.items.map(\.title) == ["重新下载", "查看 Pixabay 原网页"]
            let uncached = WallpaperLibraryCommands(workspace, steam, pixabay).makePrimaryAction(for: try workspace.content(for: pixabayRef))
            uncached?()
            checks["uncached-pixabay-return-resolves-the-fixed-id-through-original-source"] = uncached != nil && pixabay.retriedIDs == [125] && pixabay.items.isEmpty
            invoke(pageOnly, "查看 Pixabay 原网页")
            checks["pixabay-source-page-uses-documented-stable-positive-id-rule"] = pixabay.pages.map(\.absoluteString) == ["https://pixabay.com/videos/id-125/"]
                && PixabayService.videoSourcePageURL(id: 0) == nil && PixabayService.videoSourcePageURL(id: -1) == nil
            pixabay.items = [.init(id: 125, metadataVersion: 1)]
            let original = try menu(workspace, steam, pixabay, pixabayRef)!
            pixabay.items = [.init(id: 125, metadataVersion: 2), .init(id: 126, metadataVersion: 3)]
            invoke(original, "重新下载")
            checks["pixabay-retry-keeps-the-fixed-id-after-current-browse-metadata-changes"] = pixabay.retriedIDs == [125, 125]
                && pixabay.items == [.init(id: 125, metadataVersion: 2), .init(id: 126, metadataVersion: 3)] && steam.downloads.isEmpty
            pixabay.items = [.init(id: 126, metadataVersion: 4)]
            invoke(original, "重新下载")
            checks["expired-pixabay-browse-metadata-retries-fixed-id-without-borrowing-another-item"] = pixabay.retriedIDs == [125, 125, 125]
                && pixabay.items == [.init(id: 126, metadataVersion: 4)]
            workspace.relationships = .init(revision: 2, resetEpoch: workspace.relationships.resetEpoch, migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            invoke(pageOnly, "查看 Pixabay 原网页")
            checks["removed-pixabay-relationship-revokes-held-source-page-action"] = pixabay.pages.count == 1
        }
        do {
            let (workspace, steam, pixabay) = setup(pixabayRef)
            workspace.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            let failed = WallpaperContentItem(reference: pixabayRef, providerReference: pixabayRef,
                locator: .init(mediaKind: .video), title: "Failed Pixabay task", kind: .video,
                publishedAvailability: .remote, capabilities: [.inspect, .retryDownload], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
            workspace.catalog = .init(downloads: [failed])
            let commands = WallpaperLibraryCommands(workspace, steam, pixabay)
            let retry = commands.makePrimaryAction(for: failed)
            retry?()
            checks["pixabay-source-retry-capability-does-not-require-browse-results-or-a-relationship"] = retry != nil
                && pixabay.retriedIDs == [125] && pixabay.items.isEmpty && steam.downloads.isEmpty
            let busy = WallpaperContentItem(reference: pixabayRef, providerReference: pixabayRef,
                locator: failed.locator, title: failed.title, kind: .video, publishedAvailability: .remote,
                capabilities: [.inspect, .cancelDownload], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
            workspace.catalog = .init(downloads: [busy]); retry?()
            checks["held-pixabay-retry-cannot-restart-a-now-busy-task"] = pixabay.retriedIDs == [125]
                && commands.makePrimaryAction(for: busy) == nil
            workspace.catalog = .init(downloads: [available(pixabayRef)]); retry?()
            checks["held-pixabay-retry-never-turns-into-play-after-publication"] = pixabay.retriedIDs == [125]
                && workspace.plays.isEmpty && commands.makePrimaryAction(for: available(pixabayRef)) != nil
            workspace.catalog = .init(downloads: [failed])
            let resetBound = commands.makePrimaryAction(for: failed)
            let before = workspace.relationships
            workspace.relationships = .init(revision: before.revision + 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            resetBound?()
            checks["held-pixabay-retry-is-revoked-by-reset"] = resetBound != nil && pixabay.retriedIDs == [125]
            let pageBound = commands.makePrimaryAction(for: failed)
            workspace.presentation.page = .videos; pageBound?()
            checks["held-pixabay-retry-cannot-borrow-a-new-page-selection"] = pageBound != nil && pixabay.retriedIDs == [125]
        }
        for source in OnlineImageSource.allCases {
            let library = OnlineImageLibrary.shared
            let record = OnlineImageLocalRecord(assetID: .init(source: source, artworkID: "42", pageIndex: source == .pixiv ? 2 : 0),
                title: "Missing page", sourceURL: URL(string: "https://example.org/42")!, author: nil, authorID: nil, tags: [],
                relativePath: "missing.png", pixelWidth: 3, pixelHeight: 3, fileSizeBytes: 1, firstDownloadedAt: Date(), revision: UUID())
            library.snapshot = .init(records: [record], unavailable: [record.id])
            library.retries = []
            let (workspace, steam, pixabay) = setup(record.id.reference)
            let action = WallpaperLibraryDownloadRecovery.makePrimaryAction(for: try workspace.content(for: record.id.reference),
                workspace: workspace, steam: steam, pixabay: pixabay)
            action?()
            let recoveryMenu = try menu(workspace, steam, pixabay, record.id.reference)
            checks["online-image-recovery-uses-local-record-without-remote-browser-results-" + source.rawValue] = action != nil
                && library.retries == [record.id.reference] && pixabay.items.isEmpty && workspace.plays.isEmpty
                && recoveryMenu?.items.map(\.title) == ["重新下载", "查看原网页"]
            let before = workspace.relationships
            workspace.relationships = .init(revision: before.revision + 1, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [], members: [], favorites: before.favorites, recent: [], aliases: [], locators: before.locators)
            action?()
            checks["online-image-recovery-held-action-is-revoked-by-reset-" + source.rawValue] = library.retries == [record.id.reference]
            let epoch = workspace.relationships.resetEpoch
            workspace.relationships = .init(revision: before.revision + 2, resetEpoch: epoch, migrationManifestID: nil,
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: before.locators)
            let manifestOnly = WallpaperLibraryDownloadRecovery.makePrimaryAction(for: try workspace.content(for: record.id.reference),
                workspace: workspace, steam: steam, pixabay: pixabay)
            let manifestMenu = try menu(workspace, steam, pixabay, record.id.reference)
            manifestOnly?()
            checks["online-image-manifest-record-admits-recovery-without-favorite-membership-or-history-" + source.rawValue] = manifestOnly != nil
                && manifestMenu?.items.map(\.title) == ["重新下载", "查看原网页"]
                && library.retries == [record.id.reference, record.id.reference] && workspace.plays.isEmpty
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
