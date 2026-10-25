import Foundation
import Combine
import SQLite3

@main struct UserCollectionsControllerHarness {
    static func sql(_ url: URL, _ statement: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    }

    @MainActor static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = UserCollectionsStore(url: url)
        let initial = try await store.snapshot()
        let controller = UserCollectionsController(store: store, snapshot: initial)
        var snapshotPublications = 0
        let observation = controller.$snapshot.dropFirst().sink { _ in snapshotPublications += 1 }
        defer { observation.cancel() }
        let a = WallpaperReference(provider: .videoLibrary, sourceID: "a")
        let b = WallpaperReference(provider: .steamWorkshop, sourceID: "b")
        let local = WallpaperOrganizationItem(reference: a, locator: .init(titleHint: "A", mediaKind: .video), isPublishedLocally: true, isAvailable: true)
        let remote = WallpaperOrganizationItem(reference: b, locator: .init(titleHint: "B", mediaKind: .scene), isPublishedLocally: false, isAvailable: false)
        var checks: [String: Bool] = [:]
        let id = try await controller.createPlaylist(name: "  Mixed / 中文 ⭐️  ", members: [local], at: Date(timeIntervalSince1970: 100))
        checks["createWithMembersPublishesOneAtomicRevision"] = controller.snapshot.revision == 1 && controller.snapshot.playlists.count == 1 && controller.snapshot.members.map(\.reference) == [a]
        checks["sheetNameTrimsOnlyEdgesAndKeepsNonFilenameCharacters"] = controller.snapshot.playlists[0].name == "Mixed / 中文 ⭐️"
        let beforeBad = controller.snapshot
        do {
            _ = try await controller.createPlaylist(name: "Ghost", members: [local, remote])
            checks["badMemberDoesNotLeaveGhostPlaylistOrPartialRows"] = false
        } catch UserCollectionsError.unavailableForOrganization {
            let persisted = try await store.snapshot()
            checks["badMemberDoesNotLeaveGhostPlaylistOrPartialRows"] = controller.snapshot == beforeBad && persisted == beforeBad
        }
        checks["failedUICommandIsReportedWithoutPublishingPhantomState"] = controller.lastError != nil
        let metadata = controller.snapshot.playlists.first { $0.id == id }!.metadata
        var replacement = metadata; replacement.name = "Renamed"
        _ = try await controller.perform(.editPlaylistMetadata(id: id, expected: metadata,
            replacement: replacement, coverAsset: nil, at: Date(timeIntervalSince1970: 101)))
        checks["successfulCommandPublishesOnlyCommittedSnapshot"] = controller.snapshot.playlists[0].name == "Renamed" && controller.lastError == nil
        let tasks = (0..<20).map { index in
            Task { @MainActor in
                try await controller.createPlaylist(name: "Concurrent \(index)")
            }
        }
        for task in tasks { _ = try await task.value }
        let afterConcurrent = try await store.snapshot()
        checks["concurrentCommandsDoNotLoseLaterSnapshotOrRevision"] = controller.snapshot.playlists.count == 21 && controller.snapshot.revision == 22 && controller.snapshot == afterConcurrent
        checks["concurrentCreationAppendsUsingCommittedRankAtItsTurn"] = controller.snapshot.playlists.map(\.sidebarRank) == Array(0..<21)
        try await controller.perform(.deletePlaylist(id))
        let afterDeletion = try await controller.createPlaylist(name: "Appended after deletion")
        checks["creationAfterDeletionAppendsWithoutCollidingRanks"] = controller.snapshot.playlists.last?.id == afterDeletion && controller.snapshot.playlists.map(\.sidebarRank) == Array(0..<21)
        checks["ordinary-commands-without-pending-history-do-not-derive-aliases"] = UserCollectionsController.aliasDerivationCount == 0
        let readsBeforeHistory = UserCollectionsStore.snapshotReadCount, publicationsBeforeHistory = snapshotPublications
        controller.recordSuccessfulUse(a, locator: local.locator, sequence: 1, at: Date(timeIntervalSince1970: 300))
        controller.recordSuccessfulUse(b, locator: remote.locator, sequence: 2, at: Date(timeIntervalSince1970: 200))
        controller.recordSuccessfulUse(a, locator: local.locator, sequence: 3, at: Date(timeIntervalSince1970: 100))
        checks["successQueueFlushReportsNoFailure"] = await controller.flush() == nil
        checks["one-real-history-batch-reads-and-publishes-once-despite-queued-empty-drains"] = UserCollectionsStore.snapshotReadCount == readsBeforeHistory + 1
            && snapshotPublications == publicationsBeforeHistory + 1
        let readsAfterHistory = UserCollectionsStore.snapshotReadCount, publicationsAfterHistory = snapshotPublications
        _ = await controller.flush()
        checks["empty-flush-does-not-read-store-or-republish"] = UserCollectionsStore.snapshotReadCount == readsAfterHistory
            && snapshotPublications == publicationsAfterHistory
        checks["synchronousEnqueuePreservesAllDistinctSuccessfulCommits"] = controller.snapshot.recent.map(\.reference) == [a, b] && controller.snapshot.recent.map(\.lastSuccessfulUseAt) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        let beforeRepeat = controller.snapshot
        controller.recordSuccessfulUse(a, locator: nil, sequence: 3, at: Date(timeIntervalSince1970: 1000))
        _ = await controller.flush()
        checks["duplicateACKCannotReorderOrRetimestampSuccess"] = controller.snapshot == beforeRepeat
        // Metadata failure stays queued; the next success cannot leap over it.
        let invalid = WallpaperReference(provider: .videoLibrary, sourceID: "")
        controller.recordSuccessfulUse(invalid, locator: nil, sequence: 4)
        controller.recordSuccessfulUse(b, locator: nil, sequence: 5)
        checks["failedMetadataRemainsObservableForExitRetry"] = await controller.flush() != nil
        checks["metadataFailureDoesNotLeapfrogOrEraseCommittedHistory"] = controller.snapshot.recent == beforeRepeat.recent
        let oldEpoch = controller.snapshot.resetEpoch
        let queued = (0..<20).map { index in Task { @MainActor in try await controller.createPlaylist(name: "Before reset \(index)") } }
        let resetting = Task { @MainActor in try await controller.reset() }
        _ = try await resetting.value
        for task in queued { _ = try? await task.value }
        _ = await controller.flush()
        checks["resetRevokesQueuedCommandsAndFailedMetadata"] = controller.snapshot.playlists.isEmpty && controller.snapshot.recent.isEmpty && controller.snapshot.resetEpoch != oldEpoch && controller.lastError == nil
        controller.recordSuccessfulUse(b, locator: nil, sequence: 6)
        _ = await controller.flush()
        checks["newSuccessAfterResetAcquiresFreshPublisher"] = controller.snapshot.recent.map(\.reference) == [b]
        try await controller.reset()
        try await controller.reset()
        checks["repeatedResetsDoNotResurrectHistoryOrRows"] = controller.snapshot.recent.isEmpty && controller.snapshot.playlists.isEmpty && controller.snapshot.migrationManifestID == "reset-complete"
        let reopened = UserCollectionsStore(url: url, allowCreate: false)
        checks["independentReopenSeesExactlyPublishedFinalState"] = try await reopened.snapshot() == controller.snapshot
        let source = try await controller.createPlaylist(name: "Offline mix", members: [local])
        let beforeCopy = controller.snapshot
        let copy = try await controller.duplicatePlaylist(source, at: Date(timeIntervalSince1970: 500))
        checks["duplicateUsesNewUUIDAndCopiesOrderedReferencesWithoutTouchingOtherRelations"] = copy != source
            && controller.snapshot.playlists.last?.id == copy && controller.snapshot.playlists.last?.name == "Offline mix 副本"
            && controller.snapshot.members.filter { $0.playlistID == copy }.map(\.reference) == [a]
            && controller.snapshot.recent == beforeCopy.recent && controller.snapshot.favorites == beforeCopy.favorites
            && controller.snapshot.revision == beforeCopy.revision + 1
        let missingSource = UUID(), beforeMissingCopy = controller.snapshot
        do {
            _ = try await controller.duplicatePlaylist(missingSource)
            checks["deletedSourceCannotProduceGhostCopyOrChangeRanks"] = false
        } catch UserCollectionsError.missingPlaylist {
            let persisted = try await store.snapshot()
            checks["deletedSourceCannotProduceGhostCopyOrChangeRanks"] = controller.snapshot == beforeMissingCopy
                && persisted == beforeMissingCopy
        }
        let offlineReferences: [WallpaperReference] = [
            .init(provider: .staticImageLibrary, sourceID: "offline-image"),
            .init(provider: .videoLibrary, sourceID: "offline-video"),
            .init(provider: .steamWorkshop, sourceID: "offline-web"),
            .init(provider: .steamWorkshop, sourceID: "offline-scene")]
        let kinds: [WallpaperMediaKind] = [.image, .video, .web, .scene]
        let missingRoot = url.deletingLastPathComponent().appendingPathComponent("never-created-media")
        let offlineItems = zip(offlineReferences, kinds).map { reference, kind in
            WallpaperOrganizationItem(reference: reference, locator: .init(path: missingRoot.appendingPathComponent(reference.sourceID).path, mediaKind: kind),
                                      isPublishedLocally: true, isAvailable: true)
        }
        // Membership was admitted when the source reported ready. Losing the
        // media later must not turn a metadata-only duplicate into an import.
        let appendOrder = [offlineItems[3], offlineItems[0], offlineItems[2], offlineItems[1]]
        let persistedOrder = appendOrder.map(\.reference)
        let offlineSource = try await controller.createPlaylist(name: "Four missing types", members: appendOrder,
                                                               at: Date(timeIntervalSince1970: 600))
        let beforeOfflineCopy = controller.snapshot
        let offlineCopy = try await controller.duplicatePlaylist(offlineSource, at: Date(timeIntervalSince1970: 700))
        let copied = controller.snapshot.members.filter { $0.playlistID == offlineCopy }
        checks["fourTypeOfflineCopyKeepsPersistedAppendOrderWithoutProbingOrAcquiringMedia"] = copied.map(\.reference) == persistedOrder
            && copied.map(\.position) == [0, 1, 2, 3]
            && offlineItems.allSatisfy { !FileManager.default.fileExists(atPath: $0.locator.path!) }
            && controller.snapshot.locators == beforeOfflineCopy.locators
        checks["copyResetsAddedDateOnlyForNewMembershipAndCommitsOneRevision"] = copied.allSatisfy { $0.addedAt == Date(timeIntervalSince1970: 700) }
            && controller.snapshot.members.filter { $0.playlistID == offlineSource } == beforeOfflineCopy.members.filter { $0.playlistID == offlineSource }
            && controller.snapshot.revision == beforeOfflineCopy.revision + 1
            && controller.snapshot.favorites == beforeOfflineCopy.favorites && controller.snapshot.recent == beforeOfflineCopy.recent
        let aliasURL = url.deletingLastPathComponent().appendingPathComponent("pending-alias.sqlite3")
        let aliasStore = UserCollectionsStore(url: aliasURL)
        let aliasController = UserCollectionsController(store: aliasStore, snapshot: try await aliasStore.snapshot())
        let raw = WallpaperReference(provider: .videoLibrary, sourceID: "raw")
        let target = WallpaperReference(provider: .steamWorkshop, sourceID: "target")
        let retained = WallpaperReference(provider: .staticImageLibrary, sourceID: "retained")
        _ = try await aliasController.perform(.linkAlias(.init(alias: raw, canonical: target, proof: .publishedDownload), Date()))
        try sql(aliasURL, "CREATE TRIGGER history_fail BEFORE INSERT ON recent BEGIN SELECT RAISE(ABORT,'pending history'); END")
        aliasController.recordSuccessfulUse(raw, locator: nil, sequence: 1)
        aliasController.recordSuccessfulUse(retained, locator: nil, sequence: 2)
        let pendingError = await aliasController.flush()
        let beforeOrdinary = UserCollectionsController.aliasDerivationCount
        _ = try await aliasController.perform(.rememberLocator(.init(reference: retained, locator: .init(titleHint: "Retained"))))
        checks["ordinary-command-with-real-pending-history-still-skips-alias-derivation"] = pendingError != nil
            && UserCollectionsController.aliasDerivationCount == beforeOrdinary
        _ = try await aliasController.perform(.removeRecent([target]))
        let derivedOnce = UserCollectionsController.aliasDerivationCount == beforeOrdinary + 1
        try sql(aliasURL, "DROP TRIGGER history_fail")
        let removedError = await aliasController.flush()
        checks["remove-recent-retires-only-admitted-canonical-pending-event"] = derivedOnce && removedError == nil
            && aliasController.snapshot.recent.map(\.reference) == [retained]
        aliasController.recordSuccessfulUse(raw, locator: nil, sequence: 3)
        _ = await aliasController.flush()
        checks["new-success-after-canonical-removal-is-not-suppressed"] = aliasController.snapshot.recent.map(\.reference) == [target, retained]
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
