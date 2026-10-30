import Combine
import Foundation
import QuartzCore

// STARTUP_OUTCOME
// PUBLICATION_VALUE
// IMPORT_GATE

// The copied production Task increments this only on exit. Waiting on the
// receipt proves a duplicate callback actually ran before asserting no write.
@MainActor enum WorkspaceBackingProbe { static var completed = 0 }
nonisolated enum WorkspaceIdentityQueryProbe { nonisolated(unsafe) static var catalogInitializations = 0 }

// Screen-saver policy is a boundary leaf; only callback timing is recorded here.
@MainActor final class ScreenSaverCoordinator {
    static let shared = ScreenSaverCoordinator()
    private(set) var desktopCommits: [WallpaperReference] = []
    func onDesktopCommitted(_ reference: WallpaperReference) { desktopCommits.append(reference) }
}

// Source owners and the final prepared/visible boundary are controlled leaves.
// The real App binding, SQLite, query, sessions and pure transaction/sequence
// run here. Native provider dispatch and renderer handoff have their own gates.
@MainActor final class WallpaperManager {
    var libraryPlaybackSequence = WallpaperPlaybackSequence()
    var playbackSwitch = PlaybackSwitchTransaction()
    var playbackIntentEpoch: UInt64 { playbackSwitch.epoch }
    func isLocalSourceFileInUse(_ path: String) -> Bool { false }
    var libraryPlaybackSnapshotProvider: ((WallpaperReference?, WallpaperPlaybackSequence.Source, WallpaperPlaybackCause) -> WallpaperPlaybackSequence.Snapshot?)?
    var libraryPlaybackDispatcher: ((WallpaperPlaybackSequence.Pending) -> Bool)?
    var libraryPlaybackCommitted: ((WallpaperPlaybackSequence.Commit) -> Void)?
    var libraryPlaybackPendingChanged: (() -> Void)?
    var libraryPlaybackStopped: (() -> Void)?
    var libraryPlaybackFailed: ((WallpaperPlaybackSequence.Pending) -> Void)?
    var libraryPlaybackResetRequested: (() -> Void)?
    var libraryBackingPublished: ((WallpaperContentBackingPublication) -> Void)?
    var sourceUpdates: [WallpaperPlaybackSequence.SourceUpdateReason] = []
    var sourceSnapshots: [(WallpaperPlaybackSequence.Snapshot, PlaybackSwitchTicket?)] = []
    struct Settings {
        enum Unit { case seconds; var secondsValue: Int { 1 } }
        var autoSwitchEnabled = true, randomInterval = 1
        var timeUnit = Unit.seconds
    }
    var settings = Settings()
    var mode = WallpaperPlaybackSequence.Mode.sequential
    var libraryRotationDeadline = WallpaperRotationDeadline()
    var autoSwitchTimer: WorkspaceRotationTimer?
    func playbackMode() -> WallpaperPlaybackSequence.Mode { mode }
    func isSwitchingPlaybackMode() -> Bool { mode != .loop }
    // ACTUAL_SOURCE_ROTATION
    @discardableResult
    func requestLibraryPlayback(reference: WallpaperReference, from snapshot: WallpaperPlaybackSequence.Snapshot,
                                cause: WallpaperPlaybackCause) -> PlaybackSwitchTicket? {
        guard let proposal = libraryPlaybackSequence.proposeSelection(reference, from: snapshot, cause: cause),
              let runtime = proposal.entry.runtime else { return nil }
        return dispatchLibraryPlayback(proposal, runtime: runtime)
    }
    private func dispatchLibraryPlayback(_ proposal: WallpaperPlaybackSequence.Proposal,
                                        runtime: WallpaperRuntimeKind? = nil) -> PlaybackSwitchTicket? {
        guard let runtime = runtime ?? proposal.entry.runtime else { return nil }
        let ticket = playbackSwitch.begin(runtime).0
        guard libraryPlaybackSequence.stage(proposal, ticket: ticket), let pending = libraryPlaybackSequence.pending,
              libraryPlaybackDispatcher?(pending) == true else { return nil }
        return ticket
    }
    func updateLibraryPlaybackSource(_ snapshot: WallpaperPlaybackSequence.Snapshot, reason: WallpaperPlaybackSequence.SourceUpdateReason,
                                     targetTicket: PlaybackSwitchTicket? = nil) {
        sourceUpdates.append(reason)
        sourceSnapshots.append((snapshot, targetTicket))
        libraryPlaybackSequence.updateSource(snapshot, reason: reason, targetTicket: targetTicket)
    }
    func presentPreparedTarget() {
        guard let pending = libraryPlaybackSequence.pending else { return }
        let execution = UUID()
        var effects = playbackSwitch.prepared(pending.ticket, executionID: execution)
        // The real transaction/sequence run; only native output/exit ACKs are
        // immediate leaves. This permits source-bound timer successors too.
        while !effects.isEmpty {
            switch effects.removeFirst() {
            case .output(let operation): effects += playbackSwitch.activityCompleted(operation, succeeded: true)
            case .activate(let selection): effects += playbackSwitch.visible(selection.ticket, executionID: selection.executionID!)
            case .cancel(let barrier, _): effects += playbackSwitch.cancelled(barrier)
            case .retire(let barrier, _), .handoff(let barrier, _, _): effects += playbackSwitch.retired(barrier)
            case .commit(let selection, let recovery):
                if let commit = libraryPlaybackSequence.commit(selection.ticket, recovery: recovery) {
                    libraryRotationDeadline.commitSuccess(now: WorkspaceRotationClock.now, interval: libraryRotationInterval,
                        eligible: libraryRotationEligible)
                    libraryPlaybackCommitted?(commit)
                    refreshAutoSwitchTimerIfNeeded()
                }
            default: break
            }
        }
    }
}
@MainActor final class SILService {}
@MainActor final class SteamWorkshopService {
    var immediate: WallpaperContentItem?
    func libraryContentItemForExplicitPlayback(id: String) -> WallpaperContentItem? {
        immediate.flatMap { $0.providerReference.sourceID == id ? $0 : nil }
    }
}
@MainActor final class PixabayService {
    var immediate: WallpaperContentItem?
    func libraryContentItemForExplicitPlayback(id: Int) -> WallpaperContentItem? {
        immediate.flatMap { $0.providerReference.sourceID == String(id) ? $0 : nil }
    }
}
@MainActor final class WallpaperLibraryCatalogController {
    @Published private(set) var catalog = WallpaperLibraryCatalog()
    init(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService) {}
    func publish(_ value: WallpaperLibraryCatalog) { catalog = value }

}
@MainActor enum WallpaperLibraryPlaybackRouting {
    static var dispatched: [(WallpaperPlaybackSequence.Pending, WallpaperContentItem)] = []
    static func dispatch(_ pending: WallpaperPlaybackSequence.Pending, content: WallpaperContentItem,
                         manager: WallpaperManager, workshop: SteamWorkshopService,
                         pixabay: PixabayService, images: SILService, relationships: UserCollectionsSnapshot? = nil) -> Bool {
        dispatched.append((pending, content))
        return true
    }
}

@MainActor final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    var isPlaybackPaused = false
    var pauseSnapshots: AnyPublisher<WorkspacePause, Never> { Just(WorkspacePause(isUserPaused: false)).eraseToAnyPublisher() }
}
struct WorkspacePause { let isUserPaused: Bool }
@MainActor final class WallpaperLibraryPlaybackRestoration {
    init(manager: WallpaperManager, defaults: UserDefaults,
         snapshotProvider: @escaping (WallpaperPlaybackSequence.Source, WallpaperLibraryQueryState?) throws -> WallpaperPlaybackSequence.Snapshot?,
         contentResolver: @escaping (WallpaperReference) throws -> WallpaperContentItem?,
         dependencyProvider: @escaping (WallpaperPlaybackSequence.Source, WallpaperLibraryQueryState?) throws -> Set<WallpaperProvider>,
         report: @escaping (Error) -> Void) {}
    func onUserPauseChanged(_ value: Bool) {}
    func onCommitted(_ value: WallpaperPlaybackSequence.Commit) {}
    func onStopped() {}
    func onFailed(_ value: WallpaperPlaybackSequence.Pending) {}
    func reset() {}
    func updateInitialReadiness(loadedProviders: Set<WallpaperProvider>, existingPlaylistIDs: Set<UUID>, resetEpoch: UUID,
                                relationshipsReady: Bool, catalogRevision: UInt64) {}
}

@main struct WallpaperLibraryWorkspaceHarness {
    @MainActor static func main() async throws {
        let database = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = UserCollectionsStore(url: database)
        let initial = try await store.snapshot()
        let suite = "mwx.workspace." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), pixabay = PixabayService()
        let workspace = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: initial, disposition: .published)),
            manager: manager, images: images, steam: steam, pixabay: pixabay, defaults: defaults)
        var checks: [String: Bool] = [:]
        let video = WallpaperReference(provider: .videoLibrary, sourceID: "local-v")
        let image = WallpaperReference(provider: .staticImageLibrary, sourceID: "local-i")
        let download = WallpaperReference(provider: .steamWorkshop, sourceID: "web:remote")
        let pixabayReference = WallpaperReference(provider: .pixabay, sourceID: "9")
        func content(_ ref: WallpaperReference, _ title: String, _ kind: WallpaperMediaKind) -> WallpaperContentItem {
            WallpaperContentItem(reference: ref, providerReference: ref,
                locator: .init(path: "/controlled/\(ref.sourceID)", titleHint: title, mediaKind: kind), title: title,
                kind: kind, publishedAvailability: .available, capabilities: [.inspect, .play, .organize],
                metadata: .init(resourceRevision: "v1"), acquisition: .idle, update: .idle, aliases: [])
        }
        let values = [content(video, "Alpha", .video), content(image, "Alpha image", .image),
                      content(download, "Beta", .web), content(pixabayReference, "Alpha online", .video)]
        func wait(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
            return condition()
        }
        var catalog = WallpaperLibraryCatalog(videos: [values[0]], images: [values[1]], downloads: Array(values.suffix(2)), revision: 1)
        workspace.catalog.publish(catalog)
        checks["app-composes-one-injected-store-and-one-page-model"] = workspace.presentation.collections === workspace.collections
            && workspace.collections?.snapshot.resetEpoch == initial.resetEpoch
        checks["initial-unknown-providers-never-create-a-global-fallback"] = manager.libraryPlaybackSnapshotProvider?(video, .global, .manualNavigation) == nil
        catalog.loadedProviders = Set(WallpaperProvider.allCases)
        workspace.catalog.publish(catalog)
        checks["app-publishes-source-values-before-explicit-play"] = await wait { workspace.presentation.queryResult.items.map(\.reference) == [video] }
        checks["background-catalog-and-page-navigation-do-not-start-wallpapers"] = WallpaperLibraryPlaybackRouting.dispatched.isEmpty && manager.libraryPlaybackSequence.committed == nil
        let currentReceipt = (catalogRevision: catalog.revision, relationshipsRevision: workspace.relationships.revision,
            resetEpoch: workspace.relationships.resetEpoch, items: [values[0]])
        let reused = try workspace.capturePlaybackSnapshot(for: video, resolvedProjection: currentReceipt)
        checks["same-owner-render-receipt-keeps-snapshot-constructor-semantics"] = reused.entries.map(\.reference) == [video]
            && reused.entries.first?.isPlayable == true && reused.source == .page(.videos)
        let wrongReference = WallpaperReference(provider: .videoLibrary, sourceID: "stale-render-only")
        let staleReceiptItems = [content(wrongReference, "Wrong", .video)]
        let changedRevision = try workspace.capturePlaybackSnapshot(for: video,
            resolvedProjection: (catalog.revision, workspace.relationships.revision + 1, workspace.relationships.resetEpoch, staleReceiptItems))
        let changedEpoch = try workspace.capturePlaybackSnapshot(for: video,
            resolvedProjection: (catalog.revision, workspace.relationships.revision, UUID(), staleReceiptItems))
        checks["stale-render-revision-or-reset-epoch-requeries-current-source"] = changedRevision.entries.map(\.reference) == [video]
            && changedEpoch.entries.map(\.reference) == [video]
        let id = try await workspace.collections!.createPlaylist(name: "Mixed", members: values.map(\.organizationItem))
        _ = workspace.presentation.switchPage(.playlists)
        _ = await wait { workspace.presentation.directoryEntries.contains { $0.id == id } }
        _ = workspace.presentation.switchPage(.playlist(id))
        _ = workspace.presentation.setQueryState(.init(search: "Alpha", preferredColumns: 6, scrollAnchor: image, scrollOffset: -19.5, scrollAtTop: false))
        workspace.play(image)
        let pending = manager.libraryPlaybackSequence.pending!
        checks["explicit-page-play-captures-only-the-displayed-mixed-filter-result"] = pending.proposal.snapshot.entries.map(\.reference) == [video, image, pixabayReference]
            && pending.proposal.snapshot.source == .page(.playlist(id)) && pending.ticket.runtime == .systemStill
        checks["playback-query-does-not-copy-view-only-density-or-scroll"] = pending.proposal.snapshot.sourceQuery?.search == "Alpha"
            && pending.proposal.snapshot.sourceQuery?.preferredColumns == 5 && pending.proposal.snapshot.sourceQuery?.scrollAnchor == nil
            && pending.proposal.snapshot.sourceQuery?.scrollOffset == nil && pending.proposal.snapshot.sourceQuery?.scrollAtTop == nil
        checks["preparing-a-target-does-not-write-recent"] = workspace.relationships.recent.isEmpty
            && ScreenSaverCoordinator.shared.desktopCommits.isEmpty
        manager.presentPreparedTarget()
        _ = await workspace.flush()
        checks["one-actual-commit-callback-records-the-original-ticket-sequence"] = workspace.relationships.recent.map(\.reference) == [image]
            && workspace.relationships.recent.first?.commitSequence != nil && manager.libraryPlaybackSequence.committed?.ticket == pending.ticket
            && ScreenSaverCoordinator.shared.desktopCommits == [image]
        _ = workspace.presentation.switchPage(.videos)
        _ = workspace.presentation.setQueryState(.init(search: "unrelated"))
        checks["browsing-another-page-keeps-the-accepted-source-and-query"] = manager.libraryPlaybackSequence.committed?.snapshot.source == .page(.playlist(id))
            && manager.libraryPlaybackSequence.committed?.snapshot.sourceQuery?.search == "Alpha"
        workspace.didEditMembers(of: .playlist(id))
        checks["explicit-membership-refresh-uses-the-original-source-filter"] = manager.libraryPlaybackSequence.committed?.snapshot.entries.map(\.reference) == [video, image, pixabayReference]
        let recentBefore = workspace.relationships.recent
        let screenSaverBefore = ScreenSaverCoordinator.shared.desktopCommits
        let recovery = manager.libraryPlaybackSequence.commit(pending.ticket, recovery: true)
        if let recovery { manager.libraryPlaybackCommitted?(recovery) }
        _ = await workspace.flush()
        checks["internal-recovery-does-not-invent-another-recent-use"] = workspace.relationships.recent == recentBefore
            && recovery?.isRecovery == true && ScreenSaverCoordinator.shared.desktopCommits == screenSaverBefore
        let restoredTicket = manager.requestLibraryPlayback(reference: image, from: manager.libraryPlaybackSequence.committed!.snapshot, cause: .restore)
        manager.presentPreparedTarget()
        _ = await workspace.flush()
        checks["restoring-a-selection-does-not-record-recent-or-notify-screen-saver-following-again"] = restoredTicket != nil
            && manager.libraryPlaybackSequence.committed?.ticket == restoredTicket && workspace.relationships.recent == recentBefore
            && ScreenSaverCoordinator.shared.desktopCommits == screenSaverBefore
        let global = manager.libraryPlaybackSnapshotProvider?(video, .global, .manualNavigation)
        checks["explicit-global-source-resolves-every-local-provider-without-remote-results"] = global?.entries.map(\.reference) == [video, image, download, pixabayReference]
        _ = workspace.presentation.switchPage(.workshop)
        workspace.play(download)
        checks["downloaded-item-played-from-browser-is-a-single-item-source"] = manager.libraryPlaybackSequence.pending?.proposal.snapshot.source == .single(download)
            && manager.libraryPlaybackSequence.pending?.proposal.snapshot.entries.map(\.reference) == [download]
        let readOnlyManager = WallpaperManager()
        let readOnly = WallpaperLibraryWorkspace(startup: .recoveryRequired("keep source bytes"), manager: readOnlyManager,
            images: images, steam: steam, pixabay: pixabay, defaults: defaults)
        readOnly.catalog.publish(catalog)
        _ = await wait { !readOnly.presentation.queryResult.items.isEmpty || readOnly.presentation.page.isRemoteBrowse }
        checks["migration-recovery-can-browse-without-a-second-relationship-writer"] = readOnly.collections == nil
            && !readOnly.presentation.canEditCollections && readOnly.recoveryMessage == "keep source bytes"
        checks["read-only-workspace-flush-has-no-write-back"] = await readOnly.flush() == nil
        do {
            let store = UserCollectionsStore(url: database.deletingLastPathComponent().appendingPathComponent("backing.sqlite3"))
            let seed = try await store.snapshot()
            let localDefaults = UserDefaults(suiteName: suite + ".backing")!
            defer { localDefaults.removePersistentDomain(forName: suite + ".backing") }
            let sourceManager = WallpaperManager()
            let bound = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: seed, disposition: .published)),
                manager: sourceManager, images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), defaults: localDefaults)
            let controller = bound.collections!
            let backing = WallpaperReference(provider: .videoLibrary, sourceID: "accepted-backing")
            let published = WallpaperReference(provider: .pixabay, sourceID: "42")
            try await controller.perform(.setFavorite(content(backing, "Backing", .video).organizationItem, true, Date(timeIntervalSince1970: 10)))
            let receipt = WallpaperContentBackingPublication(backingVideoID: backing.sourceID, publishedReference: published, proof: .publishedDownload)
            var completed = WorkspaceBackingProbe.completed
            sourceManager.libraryBackingPublished?(receipt)
            let firstFinished = await wait { WorkspaceBackingProbe.completed == completed + 1 }
            _ = await bound.flush()
            let linked = controller.snapshot
            checks["first-backing-publication-still-merges-canonical-relationships"] = firstFinished
                && linked.aliases == [receipt.alias!] && linked.favorites.map(\.reference) == [published]
            completed = WorkspaceBackingProbe.completed
            for _ in 0..<3 { sourceManager.libraryBackingPublished?(receipt) }
            let repeatsFinished = await wait { WorkspaceBackingProbe.completed == completed + 3 }
            _ = await bound.flush()
            checks["completed-duplicate-backing-receipts-do-not-submit-empty-revision-writes"] = repeatsFinished && controller.snapshot == linked

            let redirected = WallpaperReference(provider: .pixabay, sourceID: "84")
            try await controller.perform(.linkAlias(.init(alias: published, canonical: redirected, proof: .restoredSourceRecord), Date()))
            let beforeConflict = controller.snapshot
            completed = WorkspaceBackingProbe.completed
            sourceManager.libraryBackingPublished?(receipt)
            let conflictFinished = await wait { WorkspaceBackingProbe.completed == completed + 1 }
            checks["duplicate-backing-shortcut-keeps-the-original-canonical-conflict-check"] = conflictFinished
                && controller.snapshot == beforeConflict && bound.presentation.state.lastError != nil

            completed = WorkspaceBackingProbe.completed
            sourceManager.libraryBackingPublished?(.init(backingVideoID: "late-before-reset", publishedReference: published, proof: .publishedDownload))
            try await controller.reset()
            let reset = controller.snapshot
            let lateFinished = await wait { WorkspaceBackingProbe.completed == completed + 1 }
            _ = await bound.flush()
            checks["late-backing-receipt-cannot-cross-the-original-reset-admission"] = lateFinished
                && controller.snapshot == reset && reset.aliases.isEmpty && reset.favorites.isEmpty
        }
        do {
            let store = UserCollectionsStore(url: database.deletingLastPathComponent().appendingPathComponent("unknown-source.sqlite3"))
            let seed = try await store.snapshot()
            let localDefaults = UserDefaults(suiteName: suite + ".unknown")!
            defer { localDefaults.removePersistentDomain(forName: suite + ".unknown") }
            let sourceManager = WallpaperManager(), workshop = SteamWorkshopService()
            let bound = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: seed, disposition: .published)),
                manager: sourceManager, images: SILService(), steam: workshop, pixabay: PixabayService(), defaults: localDefaults)
            let local = WallpaperReference(provider: .videoLibrary, sourceID: "known-video")
            let nfc = WallpaperReference(provider: .steamWorkshop, sourceID: "\u{e9}")
            let nfd = WallpaperReference(provider: .steamWorkshop, sourceID: "e\u{301}")
            let unknown = (0..<128).map { WallpaperReference(provider: .steamWorkshop, sourceID: "unknown-\($0)") } + [nfc, nfd]
            var inputs = WallpaperLibraryCatalog(videos: [content(local, "Known", .video)], revision: 1, loadedProviders: [.videoLibrary])
            bound.catalog.publish(inputs)
            let initialReady = await wait { bound.projectionRevision > 0 }
            precondition(initialReady)
            let entries = [WallpaperPlaybackSequence.Entry(reference: local, runtime: .video, isPlayable: true, resourceRevision: "v1")]
                + unknown.enumerated().map { .init(reference: $0.element, runtime: .web, isPlayable: true, resourceRevision: "original-\($0.offset)") }
            let original = try WallpaperPlaybackSequence.Snapshot(source: .global, revision: 1, entries: entries)
            let committedTicket = sourceManager.requestLibraryPlayback(reference: local, from: original, cause: .userSelection)!
            sourceManager.presentPreparedTarget()
            workshop.immediate = content(nfd, "Unpublished explicit owner", .web)
            let pendingTicket = sourceManager.requestLibraryPlayback(reference: nfd, from: original, cause: .userSelection)!
            let before = bound.projectionRevision
            inputs.revision += 1
            bound.catalog.publish(inputs)
            let refreshed = await wait { bound.projectionRevision > before }
            let committed = sourceManager.libraryPlaybackSequence.committed
            let pending = sourceManager.libraryPlaybackSequence.pending
            let updates = sourceManager.sourceSnapshots.suffix(2)
            checks["unknown-provider-refresh-preserves-each-original-entry-for-both-fixed-tickets"] = refreshed
                && committed?.ticket == committedTicket && committed?.snapshot.entries == entries
                && pending?.ticket == pendingTicket && pending?.proposal.snapshot.entries == entries
                && updates.contains { $0.1 == committedTicket && $0.0.entries == entries }
                && updates.contains { $0.1 == pendingTicket && $0.0.entries == entries }
            checks["unknown-fallback-lookup-preserves-opaque-nfc-and-nfd-entries"] = committed?.snapshot.entries.suffix(2).map(\.reference) == [nfc, nfd]
                && committed?.snapshot.entries.suffix(2).map(\.resourceRevision) == ["original-128", "original-129"]
            let beforeLoaded = bound.projectionRevision
            inputs.revision += 1; inputs.loadedProviders = Set(WallpaperProvider.allCases)
            inputs.downloads = [content(unknown[0], "Published", .web)]
            bound.catalog.publish(inputs)
            let loaded = await wait { bound.projectionRevision > beforeLoaded }
            let settled = sourceManager.libraryPlaybackSequence.committed?.snapshot.entries ?? []
            checks["completed-source-load-retires-unknown-fallback-and-uses-real-current-facts"] = loaded
                && settled.map(\.reference) == entries.map(\.reference)
                && settled.first?.isPlayable == true && settled.dropFirst().first?.isPlayable == true
                && settled.dropFirst(2).allSatisfy { !$0.isPlayable }
        }
        checks.merge(try await runWorkspaceRotationSourceChecks(root: database.deletingLastPathComponent()), uniquingKeysWith: { _, newer in newer })
        let applyManager = WallpaperManager()
        let applyWorkspace = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: initial, disposition: .published)),
            manager: applyManager, images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), defaults: defaults)
        let initialEpoch = applyManager.playbackIntentEpoch
        let firstImageIntent = OnlineImageLibrary.shared.captureApplyIntent!()
        checks["download-and-apply-capture-does-not-begin-or-stop-a-product-intent"] = firstImageIntent()
            && applyManager.playbackIntentEpoch == initialEpoch && applyManager.libraryPlaybackSequence.pending == nil
        let secondImageIntent = OnlineImageLibrary.shared.captureApplyIntent!()
        checks["new-image-download-intent-revokes-old-gate-without-changing-current-playback"] = !firstImageIntent()
            && secondImageIntent() && applyManager.playbackIntentEpoch == initialEpoch
        _ = applyManager.playbackSwitch.begin(.video)
        checks["later-product-selection-revokes-pending-image-application"] = !secondImageIntent()
        _ = applyWorkspace
        checks.merge(try runWorkspaceIdentityQueryChecks(store: store, epoch: initial.resetEpoch, defaults: defaults),
            uniquingKeysWith: { _, newer in newer })
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

@MainActor private func runWorkspaceIdentityQueryChecks(store: UserCollectionsStore, epoch: UUID,
                                                       defaults: UserDefaults) throws -> [String: Bool] {
    let target = WallpaperReference(provider: .videoLibrary, sourceID: "identity-target")
    let first = WallpaperReference(provider: .steamWorkshop, sourceID: "identity-first")
    let second = WallpaperReference(provider: .pixabay, sourceID: "identity-second")
    let other = WallpaperReference(provider: .videoLibrary, sourceID: "identity-other")
    func alias(_ source: WallpaperReference, _ destination: WallpaperReference) -> WallpaperReferenceAlias {
        .init(alias: source, canonical: destination, proof: .publishedDownload)
    }
    func fixture(aliases: [WallpaperReferenceAlias] = [], favorite: WallpaperReference? = nil,
                 playing: WallpaperReference? = nil, committed: Bool = true, catalog: WallpaperLibraryCatalog = .init(),
                 locators: [WallpaperReferenceLocator] = []) throws -> (WallpaperLibraryWorkspace, WallpaperManager) {
        let manager = WallpaperManager()
        if committed {
            let playing = playing ?? target
            manager.libraryPlaybackDispatcher = { _ in true }
            let snapshot = try WallpaperPlaybackSequence.Snapshot(source: .single(playing), revision: 1,
                entries: [.init(reference: playing, runtime: .video, isPlayable: true)])
            precondition(manager.requestLibraryPlayback(reference: playing, from: snapshot, cause: .userSelection) != nil)
            manager.presentPreparedTarget()
        }
        let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: epoch, migrationManifestID: nil,
            playlists: [], members: [], favorites: [.init(reference: favorite ?? target)], recent: [], aliases: aliases, locators: locators)
        let workspace = WallpaperLibraryWorkspace(startup: .ready(.init(store: store, snapshot: relationships, disposition: .published)),
            manager: manager, images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(), defaults: defaults)
        workspace.catalog.publish(catalog)
        return (workspace, manager)
    }
    var checks: [String: Bool] = [:]
    let chain = [alias(first, second), alias(second, target)]
    let (missing, manager) = try fixture(aliases: chain)
    WorkspaceIdentityQueryProbe.catalogInitializations = 0
    checks["identity-flags-resolve-multiple-alias-hops-without-published-content"] = missing.isFavorite(first)
        && missing.isFavorite(second) && missing.isPlaying(first) && missing.isPlaying(second)
        && missing.isFavorite(target) && missing.isPlaying(target)
    checks["identity-flags-reject-unrelated-missing-reference"] = !missing.isFavorite(other) && !missing.isPlaying(other)
    checks["identity-flags-do-not-construct-full-catalog-resolvers"] = WorkspaceIdentityQueryProbe.catalogInitializations == 0
    manager.playbackSwitch = PlaybackSwitchTransaction()
    checks["identity-playing-still-rejects-a-stale-runtime-ticket"] = !missing.isPlaying(target) && !missing.isPlaying(first)
    let (idle, _) = try fixture(aliases: chain, committed: false)
    checks["identity-playing-still-rejects-an-uncommitted-session"] = !idle.isPlaying(first) && idle.isFavorite(first)

    let cycle = [alias(first, second), alias(second, first)]
    let (cyclic, _) = try fixture(aliases: cycle, favorite: first, playing: first)
    checks["identity-flags-reject-the-requested-alias-cycle"] = !cyclic.isFavorite(first) && !cyclic.isPlaying(first)
    let (conflicting, _) = try fixture(aliases: [alias(first, target), alias(first, other)])
    checks["identity-flags-retain-conflicting-alias-rejection"] = !conflicting.isFavorite(target) && !conflicting.isPlaying(target)

    let broken = WallpaperContentItem(reference: first, providerReference: first,
        locator: .init(path: "/controlled/unrelated", mediaKind: .video), title: "Unrelated cyclic identity", kind: .video,
        publishedAvailability: .available, capabilities: [.play], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    let (unrelatedCatalog, _) = try fixture(aliases: cycle, catalog: .init(videos: [broken]))
    checks["identity-flags-ignore-an-unrelated-catalog-alias-cycle"] = unrelatedCatalog.isFavorite(target) && unrelatedCatalog.isPlaying(target)
    let (unrelatedLocator, _) = try fixture(aliases: cycle,
        locators: [.init(reference: first, locator: .init(path: "/controlled/unrelated", mediaKind: .video))])
    checks["identity-flags-ignore-an-unrelated-locator-alias-cycle"] = unrelatedLocator.isFavorite(target) && unrelatedLocator.isPlaying(target)

    let nfc = WallpaperReference(provider: .steamWorkshop, sourceID: "\u{e9}")
    let nfd = WallpaperReference(provider: .steamWorkshop, sourceID: "e\u{301}")
    let (opaque, _) = try fixture(favorite: nfc, playing: nfc)
    checks["identity-flags-preserve-opaque-reference-byte-distinction"] = opaque.isFavorite(nfc) && !opaque.isFavorite(nfd)
        && opaque.isPlaying(nfc) && !opaque.isPlaying(nfd)
    return checks
}
