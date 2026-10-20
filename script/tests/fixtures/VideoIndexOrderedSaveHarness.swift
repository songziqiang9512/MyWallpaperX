import Foundation

/// Only unrelated settings/playback and bundled-resource leaves are replaced.
/// Save/load/flush/revocation bodies and the SQLite store come from production.
@MainActor final class WallpaperManager {
    var wallpapers: [VideoWallpaper] = []
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
    func saveSettings() {}
    func saveTags() {}
    func saveRecentWallpapers() {}
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

    // Frozen pre-U1 manager save body (f5d50dc4d), used only as a baseline.
    // Candidate calls above are extracted from the current production owner.
    func originalSynchronousSave() {
        do {
            try wallpaperIndexStore.saveWallpapers(wallpapers)
            defaults.removeObject(forKey: wallpapersKey)
        } catch {
            saveCodableValue(wallpapers, forKey: wallpapersKey)
        }
    }
}

final class SaveOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
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
        let a = record("A"), b = record("B"), c = record("C")
        var checks: [String: Bool] = [:]
        if mode != "startup" && !mode.hasSuffix("-read") && mode != "bad-fallback" {
            manager.didFinishInitialIndexLoad = true
        }
        switch mode {
        case "startup":
            for original in [true, false] {
                let label = original ? "original" : "candidate"
                let subject = WallpaperManager()
                let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
                store.holdQueueForAudit(entered: entered, release: release)
                precondition(entered.wait(timeout: .now() + 3) == .success)
                let order = SaveOrder()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) {
                    order.append("storage released")
                    release.signal()
                }
                subject.wallpapers = [b]
                if original { subject.originalSynchronousSave() } else { subject.saveWallpapers() }
                order.append("save returned")
                checks[label + "UnsettledSaveKeepsSynchronousQueueOrdering"] = order.snapshot()
                    == ["storage released", "save returned"] && subject.idle && !subject.didFinishInitialIndexLoad
                checks[label + "UnsettledSaveIsDurableOnReturn"] = try store.loadWallpapers() == [b]
                try store.setReadOnlyForAudit(true)
                subject.wallpapers = [c]
                if original { subject.originalSynchronousSave() } else { subject.saveWallpapers() }
                checks[label + "UnsettledReadOnlySaveRetainsLatestFallback"] = subject.fallback == [c]
                try store.setReadOnlyForAudit(false)
                UserDefaults.standard.removeObject(forKey: subject.wallpapersKey)

                try store.saveWallpapers([a])
                subject.loadWallpapers()
                _ = try store.loadWallpapers() // leave the already-read A callback queued
                subject.wallpapers = [b]
                if original { subject.originalSynchronousSave() } else { subject.saveWallpapers() }
                checks[label + "StartupSaveStillCompletesBeforeLoadCallback"] = try store.loadWallpapers() == [b]
                wait("startup callback did not settle") { subject.didFinishInitialIndexLoad }
                // This is the pre-existing startup whole-library replacement race,
                // deliberately recorded rather than claimed fixed by the save change.
                checks[label + "KnownStartupReplacementBehaviorIsPreserved"] = subject.wallpapers == [a]
            }

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
            manager.loadWallpapers()
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
            UserDefaults.standard.synchronize() // test process handoff; not a product flush policy

        case "fallback-read", "empty-read":
            let expected = mode == "empty-read" ? [] : [b]
            checks["restartBeginsWithPreviousProcessFallback"] = manager.fallback == expected
            manager.loadWallpapers()
            checks["fallbackIncludingEmptyIsVisibleBeforeOldSQLiteReply"] = manager.wallpapers == expected
            wait("fallback migration did not complete") { manager.idle && manager.fallback == nil }
            let migrated = try store.loadWallpapers()
            checks["restartDoesNotReplaceFallbackWithOldDatabase"] = manager.wallpapers == expected
                && migrated == expected
            checks["onlySuccessfulMigrationClearsFallback"] = manager.fallback == nil

        case "bad-fallback":
            try store.saveWallpapers([a])
            UserDefaults.standard.set(Data("not json".utf8), forKey: manager.wallpapersKey)
            manager.loadWallpapers()
            wait("valid database did not load") { manager.wallpapers == [a] }
            let afterCorruptFallback = try store.loadWallpapers()
            checks["corruptFallbackIsNotAnEmptyLibrary"] = manager.wallpapers == [a]
                && afterCorruptFallback == [a]
        default: fatalError("unknown scenario")
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
