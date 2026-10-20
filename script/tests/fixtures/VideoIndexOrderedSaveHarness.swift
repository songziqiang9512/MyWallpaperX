import AppKit
import Foundation

/// Only unrelated settings/playback and bundled-resource leaves are replaced.
/// Save/load/flush/revocation bodies and the SQLite store come from production.
@MainActor final class WallpaperManager {
    static let recentWallpapersLimit = 25
    enum RuntimeSwitchSelection { case video(VideoWallpaper); case other }
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    var currentWallpaper: VideoWallpaper?
    var pendingWallpaper: VideoWallpaper?
    var selectedWallpaperId: String?
    var selectedWallpaperIds = Set<String>()
    var inspectedWallpaperID: String?
    var isMultiSelectMode = false
    var currentIndex = 0
    var recentlyUsedWallpapers: [VideoWallpaper] = []
    let recentWallpapersKey = "RecentWallpapers"
    var unreadableRecoveryCount = 0
    var importSummaries: [ImportSummary] = []
    var scheduledImportURLs: [URL] = []
    var autoplayRequests = 0
    let wallpapersKey = "Wallpapers"
    var settingsAutoSaveWorkItem: DispatchWorkItem?
    var wallpapersAutoSaveWorkItem: DispatchWorkItem?
    var recentWallpapersAutoSaveWorkItem: DispatchWorkItem?
    // PRODUCTION_STATE
    // PRODUCTION_METHODS

    func migratedBundledVideoWallpaper(_ value: VideoWallpaper) -> VideoWallpaper { value }
    func migratedBundledVideoIndex(_ value: [VideoWallpaper]) -> [VideoWallpaper] { value }
    func scheduleMissingIndexedSourceFilesScan() {}
    func scanForMissingMetadata() {}
    func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
    func startInitialLoad() { loadWallpapers(); finishInitialIndexBootstrap() }
    func pathExists(_ path: String) -> Bool { true }
    func refreshAutoSwitchTimerIfNeeded() {}
    func presentImportSummary(_ summary: ImportSummary, in window: NSWindow?) { importSummaries.append(summary) }
    func scheduleImportedAssetsProcessing(_ urls: [URL]) { scheduledImportURLs.append(contentsOf: urls) }
    func setAsWallpaper(_ value: VideoWallpaper, userInitiated: Bool) { autoplayRequests += 1 }
    func applyExistingImportForAudit(path: String, context: ImportContext, preparedBranch: Bool) {
        let entry = PreparedImportEntry(sourceURL: URL(fileURLWithPath: path), title: "filename",
                                       normalizedPath: path, cachedThumbnailPath: nil, cachedStaticFramePath: nil)
        let result = ImportPreparationResult(requestedCount: 1,
                                             preparedImports: preparedBranch ? [entry] : [],
                                             existingPathsToLink: preparedBranch ? [] : [path], counters: ImportCounters())
        applyPreparedImportResult(result, presentingIn: nil, context: context, autoplayToken: nil, resourceLifetime: nil)
    }
    func saveSettings() {}
    func saveTags() {}
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
        let store = WallpaperIndexStore.shared
        let manager = WallpaperManager()
        defer {
            if ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_CLEANUP"] == "1" {
                manager.defaults.removePersistentDomain(forName: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_DOMAIN"]!)
            }
        }
        let a = record("A"), b = record("B"), c = record("C")
        var checks: [String: Bool] = [:]
        if !mode.hasPrefix("startup") && !mode.hasSuffix("-read") && mode != "bad-fallback" {
            manager.didFinishInitialIndexLoad = true
        }
        switch mode {
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
            manager.selectedWallpaperId = temporary.id; manager.selectedWallpaperIds = [temporary.id]
            manager.inspectedWallpaperID = temporary.id
            let ticket = UUID(); manager.switchSelections[ticket] = .video(temporary)
            wait("same-path merge did not finish") { manager.didFinishInitialIndexLoad && manager.idle }
            let samePath = manager.wallpapers.first { $0.path == a.path }!
            checks["samePathImportPreservesStableIDTitleFavoriteTagsAndMetadata"] = samePath == stored
            if case .video(let selected) = manager.switchSelections[ticket] {
                checks["futureCommitUsesStableIdentity"] = selected.id == a.id
            }
            checks["allVisibleReferencesRebindWithoutPlayback"] = manager.currentWallpaper?.id == a.id
                && manager.pendingWallpaper?.id == a.id && manager.selectedWallpaperId == a.id
                && manager.selectedWallpaperIds == [a.id] && manager.inspectedWallpaperID == a.id

            let subject = WallpaperManager()
            subject.startInitialLoad(); _ = try store.loadWallpapers()
            var imported = record("profile-id", path: a.path)
            imported = VideoWallpaper(id: imported.id, title: "user title", path: imported.path, tags: ["new"])
            subject.wallpapers = [imported]
            subject.recordInitialIndexExplicitEdit(imported, fields: [.favorite, .title], addedTags: ["new"])
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
            manager.recentlyUsedWallpapers = [old, unseen]
            manager.constrainRecentWallpapersToLibrary(); manager.saveRecentWallpapers()
            checks["unresolvedLibraryCannotPruneRecent"] = manager.recentlyUsedWallpapers.count == 2
            manager.withInitialIndexGlobalMutation(.renameTag("old", "new")) { manager.wallpapers[0].tags = ["new", "z"] }
            manager.wallpapers[0].tags.append("old")
            manager.withInitialIndexGlobalMutation(.removeTag("z")) { manager.wallpapers[0].tags.removeAll { $0 == "z" } }
            manager.withInitialIndexGlobalMutation(.clearPreviews) { manager.wallpapers[0].thumbnailPath = nil }
            wait("ordered global merge did not finish") { manager.didFinishInitialIndexLoad && manager.idle }
            let merged = manager.wallpapers
            checks["globalActionsReachUnseenRowsAndKeepLaterTagAddition"] = merged[0].tags == ["new", "old"]
                && merged[1].tags == ["new"] && merged.allSatisfy { $0.thumbnailPath == nil && $0.staticFramePath == nil }
            checks["recentSurvivesCompleteMergeWithCanonicalRows"] = manager.recentlyUsedWallpapers.map(\.id) == [a.id, c.id]
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
                for context in [ImportContext.favorites, .tag("import-tag"), .library] {
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
                    checks[label + "ExplicitContextSurvivesNoOpProvisionalValue"] = merged.id == a.id
                        && merged.title == a.title && merged.isFavorite == (context == .favorites)
                        && merged.tags == (context == .tag("import-tag") ? ["kept", "import-tag"] : ["kept"])
                    checks[label + "NoDuplicateAssetsOrAutoplayAndOriginalSummary"] = subject.wallpapers.count == 1
                        && subject.scheduledImportURLs.isEmpty && subject.autoplayRequests == 0
                        && subject.importSummaries.last?.linkedCount == 0 && subject.importSummaries.last?.skippedCount == 1
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
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
