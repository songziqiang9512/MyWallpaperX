import AppKit
import Combine
import Foundation

// This storage gate does not accept a playback Pending. Actual sequence/ticket
// behavior is covered by its focused gate; only the typed boundary is needed.
nonisolated enum WallpaperPlaybackSequence {
    struct Pending: Equatable, Sendable {}
}

enum BundledVideoLibrary {
    static func migratedURL(forPersistedPath path: String) -> URL? {
        path == "/fixture/bundled-old.mp4" ? URL(fileURLWithPath: "/fixture/bundled-current.mp4") : nil
    }
}

/// Only unrelated settings/playback and bundled-resource leaves are replaced.
/// Save/load/flush/revocation bodies and the SQLite store come from production.
@MainActor final class WallpaperManager {
    var migrationRecoveryMessage: String?
    var preservesLegacyMigrationInputs: Bool { migrationRecoveryMessage != nil }
    var allowsLibraryMutation: Bool { !preservesLegacyMigrationInputs }
    static var defersMissingFileCleanupForPersonalSettingsRecovery = false
    enum RuntimeSwitchSelection { case video(VideoWallpaper); case other }
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    var currentWallpaper: VideoWallpaper?
    var pendingWallpaper: VideoWallpaper?
    var currentIndex = 0
    let recentWallpapersKey = "RecentWallpapers"
    var unreadableRecoveryCount = 0
    var importSummaries: [ImportSummary] = []
    var scheduledImportURLs: [URL] = []
    var autoplayRequests = 0
    var libraryBackingPublished: ((WallpaperContentBackingPublication) -> Void)?
    let wallpapersKey = "Wallpapers"
    var settingsAutoSaveWorkItem: DispatchWorkItem?
    var wallpapersAutoSaveWorkItem: DispatchWorkItem?
#if VIDEO_INDEX_ASSET_PUBLICATION
    var cancellables = Set<AnyCancellable>()
    var auditPublications = 0
    var auditCurrentPublications = 0
    var auditScheduleEntries = 0
    func observeAssetPublication() {
        $wallpapers.dropFirst().sink { [weak self] _ in self?.auditPublications += 1 }.store(in: &cancellables)
        $currentWallpaper.dropFirst().sink { [weak self] _ in self?.auditCurrentPublications += 1 }.store(in: &cancellables)
        // ACTUAL_ASSET_SINK
    }
#endif
    // PRODUCTION_STATE
    // PRODUCTION_METHODS

    // PRODUCTION_BUNDLED_COPY
    func migratedBundledVideoIndex(_ value: [VideoWallpaper]) -> [VideoWallpaper] { value }
    nonisolated func normalizedSourcePathExists(_ path: String) -> Bool { path != "/fixture/bundled-old.mp4" }
    func scheduleMissingIndexedSourceFilesScan() {}
    func scanForMissingMetadata() {}
    func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
    func startInitialLoad() { loadWallpapers(); finishInitialIndexBootstrap() }
    func pathExists(_ path: String) -> Bool { true }
    func refreshAutoSwitchTimerIfNeeded() {}
    func presentImportSummary(_ summary: ImportSummary, in window: NSWindow?) { importSummaries.append(summary) }
    func scheduleImportedAssetsProcessing(_ urls: [URL]) { scheduledImportURLs.append(contentsOf: urls) }
    func setAsWallpaper(_ value: VideoWallpaper, userInitiated: Bool = true, admission: ImportedVideoPlaybackAdmission? = nil) { autoplayRequests += 1 }
    // This storage/context harness never submits a playback admission. The
    // actual acceptance/failure transaction is exercised by its focused gate.
    func acceptsImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission) -> Bool { false }
    func failImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission, reason: String) {}
    func applyExistingImportForAudit(path: String, context: ImportContext, preparedBranch: Bool) {
        let entry = PreparedImportEntry(sourceURL: URL(fileURLWithPath: path), title: "filename",
                                       normalizedPath: path, cachedThumbnailPath: nil, cachedStaticFramePath: nil)
        let result = ImportPreparationResult(requestedCount: 1,
                                             preparedImports: preparedBranch ? [entry] : [],
                                             existingPathsToLink: preparedBranch ? [] : [path], counters: ImportCounters())
        applyPreparedImportResult(result, presentingIn: nil, context: context, indexEpoch: wallpaperIndexSaveEpoch,
                                  admission: nil, resourceLifetime: nil,
                                  presentsSummary: true, orderedPaths: [path], completion: nil)
    }
    func existingThumbnailPath(for url: URL) -> String? { nil }
    func existingStaticFramePath(for url: URL) -> String? { nil }
    func sampleFactoryForAudit(_ path: String) -> VideoWallpaper { makeImportedWallpaper(from: URL(fileURLWithPath: path), title: "sample") }
    func mergeForAudit(_ incoming: VideoWallpaper, into existing: inout VideoWallpaper) { mergeWallpaper(incoming, into: &existing) }
    func saveSettings() {}
    func savePlaybackState() {}
    func saveActiveWallpaperRuntime() {}
    func persistCurrentWallpaperSnapshot() {}
    func resetIndexForAudit() {
        invalidateWallpaperIndexPersistence()
        WallpaperIndexStore.shared.resetStore()
        wallpapers = []
    }
    var idle: Bool { wallpaperIndexSaveInFlight == nil && pendingWallpaperIndexSave == nil }
    var fallback: [VideoWallpaper]? { loadCodableValue(forKey: wallpapersKey) }

}

@main enum VideoIndexOrderedSaveChecks {
    static func record(_ id: String, path: String? = nil) -> VideoWallpaper {
        VideoWallpaper(id: id, title: id, path: path ?? "/fixture/\(id).mp4", lastUsed: .distantPast, fileSize: 1)
    }
    @MainActor static func wait(_ reason: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            precondition(Date() < deadline, reason)
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
    }
    @MainActor static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.04)) }
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        WallpaperIndexStore.startupMigrationReadOnly = mode.hasPrefix("migration-")
        let store = WallpaperIndexStore.shared
        let manager = WallpaperManager()
        if mode.hasPrefix("migration-") { manager.migrationRecoveryMessage = "Startup migration failed" }
        defer {
            if ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_CLEANUP"] == "1" {
                manager.defaults.removePersistentDomain(forName: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_DOMAIN"]!)
            }
        }
#if VIDEO_INDEX_ASSET_PUBLICATION
        if mode == "exit-index" {
            try exitIndex(manager, store: store)
            return
        }
        if mode == "asset-publication" {
            try assetPublication(manager, store: store)
            return
        }
#endif
        let a = record("A"), b = record("B"), c = record("C")
        var checks: [String: Bool] = [:]
        // Source persistence must not resurrect retired relationship/view
        // writers. Settings/runtime save methods above remain controlled
        // unrelated leaves; this does not forbid their legitimate App owners.
        let retiredKeys = ["WallpaperTags", "RecentWallpapers", "PerSelectionSortStates", "gridZoomOffset",
                           "SILTags", "SILSortState", "SILGridZoomOffset"]
        let frozenKeys = ["WallpaperSettings", "PerSelectionSortStates", "SILSortState", "gridZoomOffset", "SILGridZoomOffset",
                          "CurrentWallpaper", "PlaybackState", "ActiveWallpaperRuntime", "LastWorkshopPlaybackRecordID"]
        let sentinelKeys = Set(retiredKeys + frozenKeys)
        for key in sentinelKeys { manager.defaults.set(Data(("raw sentinel " + key).utf8), forKey: key) }
        var sentinelValues = Dictionary(uniqueKeysWithValues: sentinelKeys.map { ($0, manager.defaults.data(forKey: $0)!) })
        if !mode.hasPrefix("startup") && !mode.hasSuffix("-read") && mode != "bad-fallback" {
            manager.didFinishInitialIndexLoad = true
        }
        switch mode {
        case "migration-readonly", "migration-legacy-index":
            let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!).appendingPathComponent("index.sqlite3")
            let before = try Data(contentsOf: url)
            var journal = WallpaperIndexStartupChanges()
            journal.record(path: b.path, old: b, new: nil)
            journal.record(path: c.path, old: nil, new: c)
            let encoded = try JSONEncoder().encode(journal)
            let recent = try JSONEncoder().encode([a, b])
            manager.defaults.set(encoded, forKey: manager.initialIndexChangesKey)
            manager.defaults.set(recent, forKey: manager.recentWallpapersKey)
            sentinelValues[manager.recentWallpapersKey] = recent
            manager.startInitialLoad()
            wait("recovery read-only did not materialize old index") { manager.didFinishInitialIndexLoad }
            checks["failedMigrationStillReadsAndMergesJournal"] = manager.wallpapers.map(\.id) == ["A", "C"]
            let afterReadonlyRead = try Data(contentsOf: url)
            checks["readonlyLegacySchemaDoesNotInventAdmissionOrAlterDatabase"] = manager.wallpapers.allSatisfy { $0.firstIndexedAt == nil }
                && afterReadonlyRead == before
            manager.saveWallpapers(); manager.flushPersistentState()
            checks["failedMigrationFlushCannotRewriteSourceIndex"] = try Data(contentsOf: url) == before
            checks["failedMigrationKeepsOriginalJournalAndRecentBytes"] = manager.defaults.data(forKey: manager.initialIndexChangesKey) == encoded
                && manager.defaults.data(forKey: manager.recentWallpapersKey) == recent
            do { try store.saveWallpapers([]); checks["failedMigrationIndexRejectsExplicitWrite"] = false }
            catch { checks["failedMigrationIndexRejectsExplicitWrite"] = true }
            store.resetStore()
            checks["failedMigrationIndexResetDoesNotDeleteSource"] = try Data(contentsOf: url) == before
        case "migration-missing-index":
            manager.startInitialLoad(); _ = try? store.loadWallpapers(); pump()
            manager.saveWallpapers(); manager.flushPersistentState()
            let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!).appendingPathComponent("index.sqlite3")
            checks["failedMigrationReadDoesNotCreateMissingOldIndex"] = !FileManager.default.fileExists(atPath: url.path)
                && !manager.didFinishInitialIndexLoad && manager.fallback == nil
        case "first-indexed":
            let date = Date(timeIntervalSince1970: 1_700_000_000.375)
            var dated = record("dated"); dated.firstIndexedAt = date
            let oldJSON = try JSONEncoder().encode(a)
            checks["legacyCodableWithoutAdmissionTimeStaysUnknown"] = try JSONDecoder().decode(VideoWallpaper.self, from: oldJSON).firstIndexedAt == nil
                && (JSONSerialization.jsonObject(with: oldJSON) as! [String: Any])["firstIndexedAt"] == nil
            try store.saveWallpapers([a, dated])
            checks["originalSQLitePersistsKnownAdmissionAndNullIndependentlyOfLastUsed"] = try store.loadWallpapers() == [a, dated]
                && dated.lastUsed != date
            let before = Date()
            manager.wallpapers = []
            manager.applyExistingImportForAudit(path: "/fixture/new-admission.mp4", context: .library, preparedBranch: true)
            let imported = manager.wallpapers[0], after = Date()
            checks["realPreparedImportRecordsItsAdmissionClock"] = imported.firstIndexedAt.map { $0 >= before && $0 <= after } == true
            let sample = manager.sampleFactoryForAudit("/fixture/sample.mp4")
            checks["sampleFactoryRecordsRealNewAdmission"] = sample.firstIndexedAt.map { $0 >= before && $0 <= Date() } == true
            manager.applyExistingImportForAudit(path: imported.path, context: .library, preparedBranch: true)
            checks["duplicatePreparedImportPreservesOriginalAdmission"] = manager.wallpapers.count == 1
                && manager.wallpapers[0].firstIndexedAt == imported.firstIndexedAt
            var mergedKnown = dated, mergedUnknown = a
            manager.mergeForAudit(imported, into: &mergedKnown); manager.mergeForAudit(imported, into: &mergedUnknown)
            checks["ordinaryUpsertAndDerivedUpdatesKeepKnownAndUnknownAdmission"] = mergedKnown.firstIndexedAt == date && mergedUnknown.firstIndexedAt == nil
            var oldBundled = record("dated", path: "/fixture/bundled-old.mp4"); oldBundled.firstIndexedAt = date
            let bundledCopy = manager.migratedBundledVideoWallpaper(oldBundled)
            var expectedBundled = record("dated", path: "/fixture/bundled-current.mp4"); expectedBundled.firstIndexedAt = date
            oldBundled.firstIndexedAt = nil
            checks["bundledPathMigrationPreservesKnownAndUnknownSourceMetadata"] = bundledCopy == expectedBundled
                && manager.migratedBundledVideoWallpaper(oldBundled).firstIndexedAt == nil
            var early = record("provisional", path: a.path); early.firstIndexedAt = date
            var journal = WallpaperIndexStartupChanges(); journal.record(path: a.path, old: nil, new: early)
            journal = try JSONDecoder().decode(WallpaperIndexStartupChanges.self, from: JSONEncoder().encode(journal))
            checks["unseenLegacyBaselineCannotBeDatedByProvisionalDuplicate"] = journal.merged(with: [a], normalize: manager.normalizedPath).first?.firstIndexedAt == nil
                && journal.merged(with: [a], normalize: manager.normalizedPath).first?.id == a.id
            checks["journalKeepsAdmissionForTrulyNewPath"] = journal.merged(with: [], normalize: manager.normalizedPath).first?.firstIndexedAt == date
            var knownBaseline = a; knownBaseline.firstIndexedAt = Date(timeIntervalSince1970: 40)
            checks["persistedJournalCannotReplaceKnownBaselineAdmission"] = journal.merged(with: [knownBaseline], normalize: manager.normalizedPath).first?.firstIndexedAt == knownBaseline.firstIndexedAt
            var explicit = a; explicit.firstIndexedAt = date
            var patch = WallpaperIndexStartupChanges(); patch.record(path: a.path, old: a, new: explicit)
            checks["explicitUnknownMetadataPatchKeepsJournalAdmission"] = patch.merged(with: [a], normalize: manager.normalizedPath).first?.firstIndexedAt == date
            // Exercise the original queued initial-load merge, not only the pure journal.
            try store.saveWallpapers([a])
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            store.holdQueueForAudit(entered: entered, release: release)
            precondition(entered.wait(timeout: .now() + 3) == .success)
            let loading = WallpaperManager(); loading.startInitialLoad()
            loading.applyExistingImportForAudit(path: a.path, context: .library, preparedBranch: true)
            checks["provisionalImportBeforeSQLiteHasItsOwnUncommittedClock"] = loading.wallpapers.first?.firstIndexedAt != nil
            release.signal()
            wait("admission merge did not finish") { loading.didFinishInitialIndexLoad && loading.idle }
            checks["realInitialLoadPreservesUnseenLegacyUnknownAndIdentity"] = try loading.wallpapers.first?.id == a.id
                && loading.wallpapers.first?.firstIndexedAt == nil && store.loadWallpapers().first?.firstIndexedAt == nil
        case "first-indexed-sql-write":
            var dated = b; dated.firstIndexedAt = Date(timeIntervalSinceReferenceDate: 800_000_000.0000001)
            try store.saveWallpapers([a, dated])
            checks["durableSQLiteContainsMixedKnownAndUnknownAdmission"] = try store.loadWallpapers() == [a, dated]
        case "first-indexed-sql-read":
            var dated = b; dated.firstIndexedAt = Date(timeIntervalSinceReferenceDate: 800_000_000.0000001)
            checks["processRestartRetainsSQLiteAdmissionWithOddReferenceDateULP"] = try store.loadWallpapers() == [a, dated]
        case "first-indexed-fallback-write":
            try store.saveWallpapers([a]); try store.setReadOnlyForAudit(true)
            var dated = record("dated"); dated.firstIndexedAt = Date(timeIntervalSince1970: 1_700_000_000.375)
            manager.wallpapers = [dated]; manager.saveWallpapers(); manager.flushPersistentState()
            checks["failedSaveFallbackRetainsAdmissionTimestamp"] = manager.fallback == [dated]
            manager.defaults.synchronize()
        case "first-indexed-fallback-read":
            let expected = Date(timeIntervalSince1970: 1_700_000_000.375)
            checks["processRestartDecodesAdmissionFromCompleteFallback"] = manager.fallback?.first?.firstIndexedAt == expected
            manager.startInitialLoad()
            wait("admission fallback did not commit") { manager.idle && manager.fallback == nil }
            checks["completeFallbackAdmissionSurvivesSQLitePublication"] = try store.loadWallpapers().first?.firstIndexedAt == expected
                && manager.wallpapers.first?.firstIndexedAt == expected
        case "first-indexed-legacy":
            let original = try store.loadWallpapers()
            checks["writableLegacySchemaAddsNullableAdmissionWithoutInventingHistory"] = original.count == 2 && original.allSatisfy { $0.firstIndexedAt == nil }
            var dated = original[0]; dated.firstIndexedAt = Date(timeIntervalSince1970: 10)
            try store.saveWallpapers([dated, original[1]])
            checks["upgradedLegacySchemaPersistsKnownAndUnknownAdmission"] = try store.loadWallpapers() == [dated, original[1]]
        case "startup":
            try store.saveWallpapers([a])
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            store.holdQueueForAudit(entered: entered, release: release)
            precondition(entered.wait(timeout: .now() + 3) == .success)
            manager.startInitialLoad()
            manager.wallpapers.append(b)
            manager.saveWallpapers()
            checks["unsettledSaveReturnsWithoutWaitingForSQLite"] = !manager.didFinishInitialIndexLoad
                && manager.fallback == nil && manager.defaults.data(forKey: manager.initialIndexChangesKey) != nil
            var mainRan = false
            DispatchQueue.main.async { mainRan = true }
            wait("main not responsive while initial read held") { mainRan }
            release.signal()
            wait("initial merge did not finish") { manager.didFinishInitialIndexLoad && manager.idle }
            checks["unseenOldLibraryAndNewImportBothSurvive"] = try store.loadWallpapers() == [a, b]
            checks["startupDeltaClearsOnlyAfterCompleteSave"] = manager.defaults.data(forKey: manager.initialIndexChangesKey) == nil

        case "bounded":
            try store.saveWallpapers([a])
            let duplicate = record("duplicate", path: a.path)
            do { try store.saveWallpapers([a, duplicate]); checks["constraintFailureIsRejected"] = false }
            catch { checks["constraintFailureIsRejected"] = true }
            checks["failedReplacementRollsBackDeleteAndPartialInsert"] = try store.loadWallpapers() == [a]
            store.clearAudit()
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            store.holdQueueForAudit(entered: entered, release: release)
            precondition(entered.wait(timeout: .now() + 3) == .success)
            manager.wallpapers = [a]
            manager.saveWallpapers()
            manager.wallpapers[0].tags.append("changed after submission")
            for index in 0..<20 {
                manager.wallpapers = [record("pending-\(index)")]
                manager.saveWallpapers()
            }
            checks["oneInFlightAndOnlyNewestPendingSnapshot"] = manager.wallpaperIndexSaveInFlight?.wallpapers == [a]
                && manager.pendingWallpaperIndexSave?.wallpapers.map(\.id) == ["pending-19"]
            var mainRan = false
            DispatchQueue.main.async { mainRan = true }
            wait("main queue blocked behind ordinary save") { mainRan }
            checks["ordinarySaveReturnsWhileStoreQueueIsBlocked"] = mainRan && !manager.idle
            release.signal()
            wait("bounded saves did not finish") { manager.idle }
            checks["middleVersionsNeverReachSQLite"] = store.savedIDsForAudit() == [["A"], ["pending-19"]]
            checks["latestSnapshotIsDurable"] = try store.loadWallpapers().map(\.id) == ["pending-19"]
            manager.wallpapers = [b]
            manager.saveWallpapers()
            manager.wallpapers = [c]
            manager.flushPersistentState()
            checks["exitFlushCommitsLatestWithoutMainCallback"] = try store.loadWallpapers() == [c]
                && manager.idle && manager.fallback == nil
            pump()
            checks["oldCompletionAfterExitFlushCannotReplaceLatest"] = try store.loadWallpapers() == [c]
                && manager.fallback == nil

        case "callbacks":
            manager.wallpapers = [a]
            manager.saveWallpapers()
            _ = try store.loadWallpapers() // complete IO, leave the main callback queued
            try store.setReadOnlyForAudit(true)
            manager.wallpapers = [b]
            manager.flushPersistentState()
            checks["failedSynchronousFlushPersistsLatestFallback"] = manager.fallback == [b]
            pump()
            checks["oldSuccessDoesNotClearNewFailureFallback"] = manager.fallback == [b]
            try store.setReadOnlyForAudit(false)
            manager.wallpapers = [a, record("duplicate", path: a.path)]
            manager.saveWallpapers()
            _ = try store.loadWallpapers()
            manager.wallpapers = [c]
            manager.flushPersistentState()
            pump()
            let afterNewSuccess = try store.loadWallpapers()
            checks["oldFailureDoesNotReviveFallbackAfterNewSuccess"] = manager.fallback == nil
                && afterNewSuccess == [c]

            store.clearAudit()
            manager.wallpapers = [a]
            manager.saveWallpapers()
            manager.wallpapers = [b]
            manager.saveWallpapers()
            manager.resetIndexForAudit()
            manager.wallpapers = [c]
            manager.saveWallpapers()
            wait("reset saves did not finish") { manager.idle }
            let afterResetSave = try store.loadWallpapers()
            checks["resetDropsPendingOldEpochAndKeepsOrderedNewSave"] = store.savedIDsForAudit() == [["A"], ["C"]]
                && afterResetSave == [c] && manager.fallback == nil
            manager.startInitialLoad()
            _ = try store.loadWallpapers()
            manager.resetIndexForAudit()
            manager.wallpapers = [b]
            manager.saveWallpapers()
            wait("reset during load did not finish") { manager.idle }
            pump()
            let afterResetDuringLoad = try store.loadWallpapers()
            checks["oldLoadCannotResurrectResetLibrary"] = manager.wallpapers == [b]
                && afterResetDuringLoad == [b]

        case "fallback-write", "empty-write":
            try store.saveWallpapers([a])
            try store.setReadOnlyForAudit(true)
            manager.wallpapers = mode == "empty-write" ? [] : [b]
            manager.saveWallpapers()
            wait("read-only save did not complete") { manager.idle }
            checks["readOnlyOrdinarySaveKeepsLatestFallback"] = manager.fallback == manager.wallpapers
            manager.flushPersistentState()
            let afterFailedFlush = try store.loadWallpapers()
            checks["readOnlyExitFlushKeepsLatestFallback"] = manager.fallback == manager.wallpapers
                && afterFailedFlush == [a]
            manager.defaults.synchronize() // test process handoff; not a product flush policy

        case "fallback-read", "empty-read":
            let expected = mode == "empty-read" ? [] : [b]
            checks["restartBeginsWithPreviousProcessFallback"] = manager.fallback == expected
            manager.startInitialLoad()
            checks["fallbackIncludingEmptyIsVisibleBeforeOldSQLiteReply"] = manager.wallpapers == expected
            wait("fallback migration did not complete") { manager.idle && manager.fallback == nil }
            let migrated = try store.loadWallpapers()
            checks["restartDoesNotReplaceFallbackWithOldDatabase"] = manager.wallpapers == expected
                && migrated == expected
            checks["onlySuccessfulMigrationClearsFallback"] = manager.fallback == nil

        case "bad-fallback":
            try store.saveWallpapers([a])
            manager.defaults.set(Data("not json".utf8), forKey: manager.wallpapersKey)
            manager.startInitialLoad()
            wait("valid database did not load") { manager.wallpapers == [a] }
            let afterCorruptFallback = try store.loadWallpapers()
            checks["corruptFallbackIsNotAnEmptyLibrary"] = manager.wallpapers == [a]
                && afterCorruptFallback == [a]
        case "startup-merge":
            var stored = a
            stored.isFavorite = true; stored.tags = ["old", "preserved"]
            stored.duration = 45; stored.thumbnailPath = "/existing/thumb"
            try store.saveWallpapers([stored, c])
            manager.startInitialLoad()
            _ = try store.loadWallpapers() // original successful read is queued on main
            var temporary = record("temporary", path: a.path)
            temporary.duration = 12
            manager.wallpapers = [temporary]
            manager.currentWallpaper = temporary; manager.pendingWallpaper = temporary
            let ticket = UUID(); manager.switchSelections[ticket] = .video(temporary)
            wait("same-path merge did not finish") { manager.didFinishInitialIndexLoad && manager.idle }
            let samePath = manager.wallpapers.first { $0.path == a.path }!
            checks["samePathImportPreservesStableIDTitleFavoriteTagsAndMetadata"] = samePath == stored
            if case .video(let selected) = manager.switchSelections[ticket] {
                checks["futureCommitUsesStableIdentity"] = selected.id == a.id
            }
            checks["allVisibleReferencesRebindWithoutPlayback"] = manager.currentWallpaper?.id == a.id
                && manager.pendingWallpaper?.id == a.id && manager.currentIndex == 0 && manager.autoplayRequests == 0

            let subject = WallpaperManager()
            subject.startInitialLoad(); _ = try store.loadWallpapers()
            var imported = record("profile-id", path: a.path)
            imported = VideoWallpaper(id: imported.id, title: "user title", path: imported.path, tags: ["new"])
            subject.wallpapers = [imported]
            // A persisted old explicit-edit journal still has a live decoder
            // and merger, although the former UI write producer is retired.
            subject.initialIndexChanges.record(path: a.path, old: imported, new: imported,
                fields: [.favorite, .title], tags: ["new": true])
            subject.wallpapers[0].isFavorite = true
            subject.wallpapers[0].isFavorite = false // final equals provisional baseline; still an explicit edit
            wait("explicit preferences did not merge") { subject.didFinishInitialIndexLoad && subject.idle }
            let edited = subject.wallpapers.first { $0.path == a.path }!
            checks["explicitFalseTitleAndAddedTagsOverrideOnlyTheirFields"] = edited.id == a.id
                && !edited.isFavorite && edited.title == "user title"
                && edited.tags == ["old", "preserved", "new"] && edited.duration == 45

            let exiting = WallpaperManager()
            exiting.startInitialLoad(); _ = try store.loadWallpapers()
            exiting.wallpapers.append(b)
            exiting.flushPersistentState() // the earlier main callback has not run
            checks["exitReadsAndMergesWithoutMainCallback"] = try store.loadWallpapers().map(\.id) == [a.id, c.id, b.id]
            pump()
            checks["lateReadCannotOverwriteExitMerge"] = exiting.wallpapers.map(\.id) == [a.id, c.id, b.id]

            let external = record("external-playback")
            let outside = WallpaperManager()
            outside.currentWallpaper = external; outside.pendingWallpaper = external
            outside.startInitialLoad()
            wait("external snapshot merge did not finish") { outside.didFinishInitialIndexLoad && outside.idle }
            checks["nonmemberCurrentAndPendingKeepPlaybackChoice"] = outside.currentWallpaper == external && outside.pendingWallpaper == external

            let deleted = WallpaperManager()
            deleted.startInitialLoad(); _ = try store.loadWallpapers()
            deleted.wallpapers = [a]; deleted.currentWallpaper = a; deleted.pendingWallpaper = a
            deleted.wallpapers.removeAll()
            wait("known removal did not settle") { deleted.didFinishInitialIndexLoad && deleted.idle }
            checks["explicitTombstoneDoesNotRebindDeletedSnapshot"] = deleted.currentWallpaper == nil && deleted.pendingWallpaper == nil
                && !deleted.wallpapers.contains { $0.path == a.path }

        case "startup-failure-write":
            try store.saveWallpapers([a, c])
            try store.denySelectForAudit(true)
            manager.loadWallpapers()
            manager.wallpapers = [a] // current snapshot recovery during synchronous bootstrap
            manager.finishInitialIndexBootstrap()
            manager.wallpapers.removeAll { $0.id == a.id }
            manager.wallpapers.append(b)
            manager.saveWallpapers()
            wait("failed initial read never returned") { !manager.initialIndexLoadInFlight }
            manager.flushPersistentState()
            checks["unknownBaselineFailurePersistsDeltaNotFullFallback"] = !manager.didFinishInitialIndexLoad
                && manager.fallback == nil && manager.defaults.data(forKey: manager.initialIndexChangesKey) != nil
            try store.denySelectForAudit(false)
            checks["failedReadAndExitLeaveUnseenSQLiteUntouched"] = try store.loadWallpapers() == [a, c]
            manager.defaults.synchronize()

        case "startup-failure-read":
            manager.startInitialLoad()
            wait("restart did not replay pending delete/import") { manager.didFinishInitialIndexLoad && manager.idle }
            checks["restartReplaysTombstoneAndImportAgainstOldDB"] = try store.loadWallpapers() == [c, b]
            checks["restartClearsJournalOnlyAfterDurableMerge"] = manager.defaults.data(forKey: manager.initialIndexChangesKey) == nil

        case "startup-retry":
            try store.saveWallpapers([a])
            try store.denySelectForAudit(true)
            manager.startInitialLoad(); manager.wallpapers.append(b); manager.saveWallpapers()
            wait("failed retry did not finish") { !manager.initialIndexLoadInFlight }
            try store.denySelectForAudit(false)
            manager.saveWallpapers()
            wait("later save did not retry") { manager.didFinishInitialIndexLoad && manager.idle }
            checks["existingSaveRetriesWithoutTimerOrLostActions"] = try store.loadWallpapers() == [a, b]

        case "startup-empty":
            try store.saveWallpapers([])
            manager.loadWallpapers()
            manager.initialIndexSeedWallpapers = [a]
            manager.wallpapers = [a]
            manager.finishInitialIndexBootstrap()
            manager.wallpapers[0].duration = 99 // a derived update is not an import
            wait("initialized empty did not settle") { manager.didFinishInitialIndexLoad && manager.idle }
            let emptyIndex = try store.loadInitialIndex()
            checks["initializedEmptyDoesNotResurrectSeedOrDerivedUpdate"] = manager.wallpapers.isEmpty && emptyIndex.initialized
            store.resetStore()
            let fresh = WallpaperManager()
            fresh.loadWallpapers(); fresh.initialIndexSeedWallpapers = [b]; fresh.wallpapers = [b]
            fresh.finishInitialIndexBootstrap()
            wait("fresh seed did not settle") { fresh.didFinishInitialIndexLoad && fresh.idle }
            checks["uninitializedDatabaseRetainsFirstInstallSeed"] = try store.loadWallpapers() == [b]

        case "startup-global":
            var old = a; old.tags = ["old", "z"]; old.thumbnailPath = "/old/thumb"
            var unseen = c; unseen.tags = ["old"]; unseen.staticFramePath = "/old/frame"
            try store.saveWallpapers([old, unseen])
            manager.startInitialLoad(); _ = try store.loadWallpapers()
            manager.wallpapers = [old]
            let recentBytes = try JSONEncoder().encode([old, unseen])
            manager.defaults.set(recentBytes, forKey: manager.recentWallpapersKey)
            sentinelValues[manager.recentWallpapersKey] = recentBytes
            manager.saveWallpapers()
            checks["unresolvedSourceSaveCannotPruneRetiredRecentBytes"] = manager.defaults.data(forKey: manager.recentWallpapersKey) == recentBytes
            manager.withInitialIndexGlobalMutation(.renameTag("old", "new")) { manager.wallpapers[0].tags = ["new", "z"] }
            manager.wallpapers[0].tags.append("old")
            manager.withInitialIndexGlobalMutation(.removeTag("z")) { manager.wallpapers[0].tags.removeAll { $0 == "z" } }
            manager.withInitialIndexGlobalMutation(.clearPreviews) { manager.wallpapers[0].thumbnailPath = nil }
            wait("ordered global merge did not finish") { manager.didFinishInitialIndexLoad && manager.idle }
            let merged = manager.wallpapers
            checks["globalActionsReachUnseenRowsAndKeepLaterTagAddition"] = merged[0].tags == ["new", "old"]
                && merged[1].tags == ["new"] && merged.allSatisfy { $0.thumbnailPath == nil && $0.staticFramePath == nil }
            checks["retiredRecentBytesSurviveCompleteSourceMerge"] = manager.defaults.data(forKey: manager.recentWallpapersKey) == recentBytes
            let deleting = WallpaperManager()
            deleting.startInitialLoad(); _ = try store.loadWallpapers()
            deleting.wallpapers = [old]
            deleting.wallpapers.removeAll()
            deleting.wallpapers.append(b)
            deleting.wallpapers.removeAll()
            var readded = record("fresh-A", path: a.path); readded.tags = ["last addition"]
            deleting.wallpapers.append(readded)
            wait("delete/readd did not settle") { deleting.didFinishInitialIndexLoad && deleting.idle }
            checks["deleteThenReaddPreservesLatestActionAndUnseenRows"] = try store.loadWallpapers() == [merged[1], readded]

        case "startup-import-context":
            for preparedBranch in [false, true] {
                for context in [ImportContext.library, .pixabayPlayback, .steamPlayback] {
                    var stored = a; stored.tags = ["kept"]
                    try store.saveWallpapers([stored])
                    let subject = WallpaperManager()
                    subject.loadWallpapers()
                    var provisional = record("temporary", path: a.path)
                    provisional.isFavorite = true; provisional.tags = ["import-tag", "stale-snapshot-tag"]
                    subject.wallpapers = [provisional] // restored current snapshot, before bootstrap finishes
                    subject.finishInitialIndexBootstrap()
                    _ = try store.loadWallpapers() // leave the complete SQLite baseline callback queued
                    subject.applyExistingImportForAudit(path: a.path, context: context, preparedBranch: preparedBranch)
                    subject.saveWallpapers()
                    wait("no-op import context did not settle") { subject.didFinishInitialIndexLoad && subject.idle }
                    let merged = subject.wallpapers[0]
                    let label = (preparedBranch ? "preparedExisting" : "existingLink") + "-" + String(describing: context)
                    checks[label + "SourceImportPreservesStableLegacyValuesWithoutRelationshipWrite"] = merged.id == a.id
                        && merged.title == a.title && !merged.isFavorite && merged.tags == ["kept"]
                    checks[label + "NoDuplicateAssetsOrAutoplayAndOriginalSummary"] = subject.wallpapers.count == 1
                        && subject.scheduledImportURLs.isEmpty && subject.autoplayRequests == 0
                        && (context == .library
                            ? subject.importSummaries.last?.linkedCount == 0 && subject.importSummaries.last?.skippedCount == 1
                            : subject.importSummaries.isEmpty)
                }
            }

        case "startup-size":
            let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!).appendingPathComponent("metadata.bin")
            try Data(repeating: 7, count: 19).write(to: file)
            let sized = VideoWallpaper(id: "sized", title: "sized", path: file.path, duration: 12, resolution: "1x1")
            try store.saveWallpapers([sized])
            manager.startInitialLoad()
            wait("existing metadata record did not receive missing size") { manager.didFinishInitialIndexLoad && manager.wallpapers.first?.fileSize == 19 }
            checks["sizeOnlyMissingStillBackfillsWithoutFullMetadataScan"] = manager.wallpapers.first?.duration == 12
                && manager.wallpapers.first?.resolution == "1x1"

        case "startup-corrupt":
            try store.saveWallpapers([a])
            let invalid = Data("{bad journal}".utf8)
            manager.defaults.set(invalid, forKey: manager.initialIndexChangesKey)
            manager.startInitialLoad()
            wait("corrupt journal blocked valid database") { manager.didFinishInitialIndexLoad && manager.idle }
            let afterCorruptJournal = try store.loadWallpapers()
            checks["corruptJournalPreservesRawBytesAndWarnsWithoutEmptyOverwrite"] = manager.unreadableRecoveryCount == 1
                && manager.defaults.data(forKey: manager.unreadableInitialIndexChangesKey) == invalid
                && afterCorruptJournal == [a]

        case "read-interrupt":
            try store.saveWallpapers((0..<200).map { record("row-\($0)") })
            store.interruptReadForAudit(after: 150)
            do { _ = try store.loadWallpapers(); checks["midReadInterruptIsRejected"] = false }
            catch { checks["midReadInterruptIsRejected"] = true }
            let rows = store.readRowsForAudit()
            checks["interruptOccurredAfterSomeButNotAllRows"] = rows > 0 && rows < 200
            store.interruptReadForAudit(after: 0)
            checks["interruptedReadDoesNotMutateCompleteDatabase"] = try store.loadWallpapers().count == 200

        default: fatalError("unknown scenario")
        }
        checks["sourcePersistenceLeavesRetiredPreferencesAndFrozenAuxiliarySentinelsUntouched"] = sentinelValues.allSatisfy {
            manager.defaults.data(forKey: $0.key) == $0.value
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}

#if VIDEO_INDEX_ASSET_PUBLICATION
extension VideoIndexOrderedSaveChecks {
    @MainActor static func exitIndex(_ manager: WallpaperManager, store: WallpaperIndexStore) throws {
        let rows = (0..<1_200).map { record("video-\($0)") }
        manager.didFinishInitialIndexLoad = true
        manager.wallpapers = rows
        try store.saveWallpapers(rows)
        manager.observeAssetPublication()
        var checks: [String: Bool] = [:], writes: [String: Int] = [:]
        store.clearAudit()
        manager.flushPersistentState()
        writes["clean"] = store.savedIDsForAudit().count
        checks["cleanExitPreservesAll1200Rows"] = try store.loadWallpapers() == rows

        manager.wallpapers.reverse()
        manager.wallpapers.removeLast()
        manager.wallpapers[0].tags.append("Edited immediately before exit")
        let edited = manager.wallpapers
        checks["realCombineMutationSchedulesDebouncedSave"] = manager.wallpapersAutoSaveWorkItem != nil
        store.clearAudit()
        manager.flushPersistentState()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        writes["debounced"] = store.savedIDsForAudit().count
        checks["exitBeforeDebounceRetainsOrderDeletionAndEdit"] = try store.loadWallpapers() == edited

        manager.wallpapers[0].thumbnailPath = "late-thumbnail.jpg"
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        wait("ordinary save did not settle") { manager.idle }
        store.clearAudit()
        manager.flushPersistentState()
        writes["afterOrdinarySave"] = store.savedIDsForAudit().count
        checks["settledSaveRetainsLatestThumbnail"] = try store.loadWallpapers() == manager.wallpapers

        try store.setReadOnlyForAudit(true)
        manager.wallpapers[0].tags.append("Retained failed save")
        manager.saveWallpapers()
        wait("failed save did not settle") { manager.idle }
        checks["failedSaveRetainsFallback"] = manager.fallback == manager.wallpapers
        try store.setReadOnlyForAudit(false)
        store.clearAudit()
        manager.flushPersistentState()
        writes["retryFailure"] = store.savedIDsForAudit().count
        checks["exitRetriesFallbackAndClearsOnlyAfterSuccess"] = try manager.fallback == nil
            && store.loadWallpapers() == manager.wallpapers

        manager.resetIndexForAudit()
        store.clearAudit()
        manager.flushPersistentState()
        writes["reset"] = store.savedIDsForAudit().count
        checks["resetPersistsAnEmptyLibrary"] = try store.loadWallpapers().isEmpty
        let result: [String: Any] = ["checks": checks, "writes": writes]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func assetPublication(_ manager: WallpaperManager, store: WallpaperIndexStore) throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!)
        let source = root.appendingPathComponent("source.mp4"), alias = root.appendingPathComponent("source-alias.mp4")
        try Data("owned path fixture".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        var a = record("A", path: source.path), b = record("B", path: root.appendingPathComponent("other.mp4").path)
        a.thumbnailPath = "thumb-A"; a.staticFramePath = "frame-A"
        a.tags = ["retained"]; a.isFavorite = true; a.firstIndexedAt = Date(timeIntervalSinceReferenceDate: 123)
        b.tags = ["peer"]
        var functional: [String: Any] = [:], work: [String: Any] = [:]
        func seed(_ rows: [VideoWallpaper], current: VideoWallpaper?) throws {
            manager.cancellables.removeAll()
            manager.wallpapersAutoSaveWorkItem?.cancel(); manager.wallpapersAutoSaveWorkItem = nil
            manager.migrationRecoveryMessage = nil; manager.didFinishInitialIndexLoad = true
            manager.initialIndexChanges = WallpaperIndexStartupChanges()
            manager.initialIndexSeedWallpapers = []; manager.initialIndexLoadInFlight = false
            manager.wallpapers = rows; manager.currentWallpaper = current
            try store.saveWallpapers(rows); store.clearAudit()
            manager.auditPublications = 0; manager.auditCurrentPublications = 0; manager.auditScheduleEntries = 0
            manager.observeAssetPublication()
        }
        func settle() {
            // Exercise the original 250ms scheduling, not a manually invoked save.
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            wait("asset persistence drained") { manager.idle }
        }
        func json<Value: Encodable>(_ value: Value) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
        }
        func capture(_ phase: String, expectedRows: [VideoWallpaper], expectedCurrent: VideoWallpaper?,
                     expectedDatabase: [VideoWallpaper]? = nil, extra: [String: Bool] = [:],
                     extraWork: [String: Int] = [:]) throws {
            settle()
            let database = try store.loadWallpapers()
            var checks = extra
            checks["rows"] = manager.wallpapers == expectedRows
            checks["current"] = manager.currentWallpaper == expectedCurrent
            checks["database"] = database == (expectedDatabase ?? expectedRows)
            checks["mainThread"] = Thread.isMainThread
            functional[phase] = ["rows": try json(manager.wallpapers), "current": try json(manager.currentWallpaper),
                "database": try json(database), "checks": checks]
            var counts = extraWork
            counts["publications"] = manager.auditPublications
            counts["currentPublications"] = manager.auditCurrentPublications
            counts["scheduleEntries"] = manager.auditScheduleEntries
            counts["saveEntries"] = store.savedIDsForAudit().count
            work[phase] = counts
        }
        try seed([a, b], current: a)
        manager.updateWallpaperAssetPaths(forPath: a.path, thumbnailPath: a.thumbnailPath, staticFramePath: a.staticFramePath)
        try capture("sameValue", expectedRows: [a, b], expectedCurrent: a)
        try seed([a, b], current: a)
        manager.updateWallpaperAssetPaths(forPath: a.path)
        try capture("nilInputs", expectedRows: [a, b], expectedCurrent: a)

        try seed([a, b], current: a)
        var changed = a; changed.thumbnailPath = "thumb-B"; changed.staticFramePath = "frame-B"
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: changed.staticFramePath)
        manager.updateWallpaperAssetPaths(forPath: a.path, thumbnailPath: changed.thumbnailPath)
        try capture("changedBatch", expectedRows: [changed, b], expectedCurrent: changed)

        try seed([a, b], current: a)
        var frameChanged = a; frameChanged.staticFramePath = "frame-B"
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: frameChanged.staticFramePath)
        let originalTimer = manager.wallpapersAutoSaveWorkItem
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: frameChanged.staticFramePath)
        let retainedTimer = originalTimer != nil && originalTimer === manager.wallpapersAutoSaveWorkItem
            && originalTimer?.isCancelled == false
        try capture("pendingThenNoop", expectedRows: [frameChanged, b], expectedCurrent: frameChanged,
            extraWork: ["retainedPendingTimer": retainedTimer ? 1 : 0])

        var unpreparedCurrent = a; unpreparedCurrent.thumbnailPath = nil; unpreparedCurrent.staticFramePath = nil
        try seed([a, b], current: unpreparedCurrent)
        manager.updateWallpaperAssetPaths(forPath: a.path, thumbnailPath: a.thumbnailPath, staticFramePath: a.staticFramePath)
        try capture("currentOnly", expectedRows: [a, b], expectedCurrent: a)
        try seed([b], current: unpreparedCurrent)
        manager.updateWallpaperAssetPaths(forPath: a.path, thumbnailPath: a.thumbnailPath, staticFramePath: a.staticFramePath)
        try capture("absentRowCurrent", expectedRows: [b], expectedCurrent: a)

        try seed([a, b], current: b)
        DispatchQueue.main.async { manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: "late-frame") }
        manager.wallpapers.removeAll { $0.id == a.id }
        try capture("removedBeforeCallback", expectedRows: [b], expectedCurrent: b)

        var duplicate = record("alias-peer", path: alias.path); duplicate.staticFramePath = "peer-frame"
        var duplicateCurrent = duplicate; duplicateCurrent.staticFramePath = "alias-frame"
        var aliasChanged = a; aliasChanged.staticFramePath = "alias-frame"
        try seed([a, duplicate, b], current: duplicate)
        manager.updateWallpaperAssetPaths(forPath: alias.path, staticFramePath: "alias-frame")
        // Distinct stored spellings resolve to one source. The original
        // first-match lookup must update only the first indexed row.
        try capture("aliasFirstMatch", expectedRows: [aliasChanged, duplicate, b], expectedCurrent: duplicateCurrent)

        try seed([a, b], current: a)
        var empty = a; empty.staticFramePath = ""
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: "")
        try capture("emptyString", expectedRows: [empty, b], expectedCurrent: empty)

        try seed([a, b], current: a)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        store.holdQueueForAudit(entered: entered, release: release)
        precondition(entered.wait(timeout: .now() + 5) == .success)
        manager.didFinishInitialIndexLoad = false
        manager.retryInitialIndexLoadIfNeeded()
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: a.staticFramePath)
        let noFalseDelta = manager.initialIndexChanges.isEmpty
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: frameChanged.staticFramePath)
        let trueDelta = !manager.initialIndexChanges.isEmpty
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: frameChanged.staticFramePath)
        release.signal()
        wait("real initial reply merged") { manager.didFinishInitialIndexLoad && manager.idle }
        try capture("initialLoad", expectedRows: [frameChanged, b], expectedCurrent: frameChanged,
            extra: ["sameValueCreatesNoDelta": noFalseDelta, "changedValueCreatesDelta": trueDelta,
                "journalClearedAfterDurableSave": manager.defaults.data(forKey: manager.initialIndexChangesKey) == nil])

        try seed([a, b], current: a)
        manager.migrationRecoveryMessage = "owned recovery-mode fixture"
        manager.updateWallpaperAssetPaths(forPath: a.path, staticFramePath: frameChanged.staticFramePath)
        try capture("readOnly", expectedRows: [frameChanged, b], expectedCurrent: frameChanged, expectedDatabase: [a, b])
        print(String(data: try JSONSerialization.data(withJSONObject: ["functional": functional, "work": work],
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
#endif
