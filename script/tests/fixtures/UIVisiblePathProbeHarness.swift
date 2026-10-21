import AppKit
import Foundation

private final class SourceBarrier: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
}

/// Both file-query leaves can block deterministically. Lock their recorders;
/// only the preview preparation command remains on the main thread.
private final class ProbeManager: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Bool] = [:]
    private var paths: [String] = []
    private var active = 0
    private var maximumActive = 0
    private var offMain = true
    private var nextBarrier: SourceBarrier?
    private var previewBarrier: SourceBarrier?
    private var previewIDs: [String] = []
    private var preparationIDs: [String] = []
    private var cachedIDs = Set<String>()
    private var previewOffMain = true
    private var preparationOnMain = true
    var previewChecks: [String] { lock.lock(); defer { lock.unlock() }; return previewIDs }
    var preparedIDs: [String] { lock.lock(); defer { lock.unlock() }; return preparationIDs }
    var cachedThumbnailIDs: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return cachedIDs }
        set { lock.lock(); defer { lock.unlock() }; cachedIDs = newValue }
    }
    var previewResolutionStayedOffMain: Bool { lock.lock(); defer { lock.unlock() }; return previewOffMain }
    var preparationStayedOnMain: Bool { lock.lock(); defer { lock.unlock() }; return preparationOnMain }
    func blockNextPreviewProbe() -> SourceBarrier {
        let barrier = SourceBarrier()
        lock.lock(); defer { lock.unlock() }
        previewBarrier = barrier
        return barrier
    }

    var recordedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return paths
    }
    var activeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    var maxActiveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return maximumActive
    }
    var sourceMethodsStayedOffMain: Bool {
        lock.lock(); defer { lock.unlock() }
        return offMain
    }
    func setResponse(_ path: String, exists: Bool) {
        lock.lock(); defer { lock.unlock() }
        responses[path] = exists
    }
    func blockNextSourceProbe() -> SourceBarrier {
        let barrier = SourceBarrier()
        lock.lock(); defer { lock.unlock() }
        nextBarrier = barrier
        return barrier
    }
    func normalizedSourcePathExists(_ path: String) -> Bool {
        lock.lock()
        paths.append(path)
        active += 1
        maximumActive = max(maximumActive, active)
        offMain = offMain && !Thread.isMainThread
        let response = responses[path] ?? true
        let barrier = nextBarrier
        nextBarrier = nil
        lock.unlock()
        barrier?.release.wait()
        lock.lock()
        active -= 1
        lock.unlock()
        return response
    }
    func resolvedThumbnailPath(for wallpaper: VideoWallpaper) -> String? {
        lock.lock()
        previewIDs.append(wallpaper.id)
        previewOffMain = previewOffMain && !Thread.isMainThread
        let cached = cachedIDs.contains(wallpaper.id)
        let barrier = previewBarrier
        previewBarrier = nil
        lock.unlock()
        barrier?.release.wait()
        return cached ? "/fixture/thumbnail.jpg" : nil
    }
    func ensurePreviewAssetsForWallpaper(_ wallpaper: VideoWallpaper) {
        lock.lock(); defer { lock.unlock() }
        preparationOnMain = preparationOnMain && Thread.isMainThread
        preparationIDs.append(wallpaper.id)
    }
}

@MainActor private final class ProbeCollection {
    var visible = Set<IndexPath>()
    func indexPathsForVisibleItems() -> Set<IndexPath> { visible }
}

@MainActor private final class GridProbe {
    // Window/timer admission is exercised separately with real NSWindow owners.
    private var canProbeMissingPaths: Bool { true }
    let wallpaperManager: ProbeManager
    let collectionView = ProbeCollection()
    var orderedIDs: [String] = []
    var wallpapersByID: [String: VideoWallpaper] = [:]
    var reloads: [Set<String>] = []
    // PRODUCTION_PROBE_STATE

    init(_ manager: ProbeManager, records: [VideoWallpaper], visible: Set<IndexPath>) {
        wallpaperManager = manager
        replaceRecords(records)
        collectionView.visible = visible
    }
    func replaceRecords(_ records: [VideoWallpaper]) {
        orderedIDs = records.map(\.id)
        wallpapersByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }
    func fireTimerForAudit() { probeVisibleMissingWallpapers() }
    var inFlight: Bool { isMissingPathProbeInFlight }
    var missingIDs: Set<String> {
        get { visibleMissingWallpaperIDs }
        set { visibleMissingWallpaperIDs = newValue }
    }
    func reloadVisibleItems(forIDs ids: Set<String>) {
        if !ids.isEmpty { reloads.append(ids) }
    }
    // PRODUCTION_VISIBLE_PROBE
}

@main private struct UIVisiblePathProbeHarness {
    @MainActor static func wait(_ description: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, description)
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
    }
    static func record(_ id: String, _ path: String? = nil) -> VideoWallpaper {
        VideoWallpaper(id: id, title: id, path: path ?? "/fixture/\(id).mp4", lastUsed: .distantPast)
    }
    @MainActor static func finish(_ grid: GridProbe) {
        wait("source probe did not commit") { !grid.inFlight }
    }

    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let a = record("A")
        let b = record("B")
        let first = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)

        let manager = ProbeManager()
        manager.setResponse(a.path, exists: false)
        let slow = manager.blockNextSourceProbe()
        let grid = GridProbe(manager, records: [a], visible: [first])
        grid.fireTimerForAudit()
        wait("source probe did not enter the leaf") { manager.activeCount == 1 }
        var mainQueueRan = false
        DispatchQueue.main.async { mainQueueRan = true }
        wait("blocked source probe blocked the main queue") { mainQueueRan }
        checks["slowSourceProbeLeavesMainQueueResponsive"] = grid.inFlight && mainQueueRan
        checks["sourcePathProbeRunsOffMain"] = manager.sourceMethodsStayedOffMain
        for _ in 0..<40 { grid.fireTimerForAudit() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        checks["repeatedTimerTriggersDoNotQueueMoreProbes"] = manager.recordedPaths == [a.path]
            && manager.maxActiveCount == 1 && grid.inFlight
        slow.release.signal()
        finish(grid)
        checks["missingSourceUpdatesCurrentMissingSet"] = grid.missingIDs == [a.id]
        checks["missingSourceDoesNotResolveOrPreparePreview"] = manager.previewChecks.isEmpty
            && manager.preparedIDs.isEmpty && grid.reloads.isEmpty

        manager.setResponse(a.path, exists: true)
        grid.fireTimerForAudit()
        finish(grid)
        checks["missingThenRecoveredReloadsCurrentID"] = grid.reloads == [[a.id]] && grid.missingIDs.isEmpty
        checks["recoveryKeepsPreviewPreparation"] = manager.previewChecks == [a.id] && manager.preparedIDs == [a.id]
        checks["previewResolutionLeavesMainThread"] = manager.previewResolutionStayedOffMain
        checks["previewPreparationRemainsOnMain"] = manager.preparationStayedOnMain
        checks["completedProbeAllowsNextTimer"] = manager.recordedPaths == [a.path, a.path]

        let reorderedManager = ProbeManager()
        let reorderBarrier = reorderedManager.blockNextSourceProbe()
        let reordered = GridProbe(reorderedManager, records: [a, b], visible: [first])
        reordered.missingIDs = [a.id]
        reordered.fireTimerForAudit()
        wait("reordered source probe did not start") { reorderedManager.activeCount == 1 }
        reordered.replaceRecords([b, a])
        reordered.collectionView.visible = [second]
        reorderBarrier.release.signal()
        finish(reordered)
        checks["reorderedItemRecoversByIDAtItsNewIndex"] = reordered.reloads == [[a.id]]
            && reorderedManager.previewChecks == [a.id] && reordered.missingIDs.isEmpty
        checks["reorderNeverRetagsResultToOldIndexOccupant"] = !reorderedManager.preparedIDs.contains(b.id)
            && reorderedManager.recordedPaths == [a.path]

        for scenario in ["reuse", "pathReplacement", "delete", "notVisible"] {
            let staleManager = ProbeManager()
            let barrier = staleManager.blockNextSourceProbe()
            let stale = GridProbe(staleManager, records: [a, b], visible: [first])
            stale.missingIDs = [a.id]
            stale.fireTimerForAudit()
            wait("stale source probe did not start") { staleManager.activeCount == 1 }
            switch scenario {
            case "reuse":
                stale.replaceRecords([b])
            case "pathReplacement":
                stale.replaceRecords([record(a.id, "/fixture/replacement.mp4"), b])
            case "delete":
                stale.replaceRecords([])
                stale.collectionView.visible = []
            default:
                stale.collectionView.visible = [second]
            }
            barrier.release.signal()
            finish(stale)
            checks["\(scenario)DropsOldRecoveryAndPreviewCommit"] = stale.reloads.isEmpty
                && staleManager.preparedIDs.isEmpty
            checks["\(scenario)ClearsUnvalidatedMissingIdentity"] = stale.missingIDs.isEmpty
                && staleManager.recordedPaths == [a.path]
        }

        let previewManager = ProbeManager()
        let previewBarrier = previewManager.blockNextPreviewProbe()
        let previewGrid = GridProbe(previewManager, records: [a], visible: [first])
        previewGrid.fireTimerForAudit()
        wait("preview probe did not start") { previewManager.previewChecks == [a.id] }
        var previewMainQueueRan = false
        DispatchQueue.main.async { previewMainQueueRan = true }
        wait("blocked thumbnail stat blocked main queue") { previewMainQueueRan }
        checks["slowThumbnailProbeLeavesMainQueueResponsive"] = previewGrid.inFlight && previewMainQueueRan
        for _ in 0..<40 { previewGrid.fireTimerForAudit() }
        checks["slowThumbnailProbeDoesNotStackTimerWork"] = previewManager.recordedPaths == [a.path]
        var replacedPreview = a
        replacedPreview.thumbnailPath = "/fixture/new-thumbnail.jpg"
        previewGrid.replaceRecords([replacedPreview])
        previewGrid.missingIDs = [a.id]
        previewBarrier.release.signal()
        finish(previewGrid)
        checks["changedPreviewRejectsOldMissingThumbnailResult"] = previewManager.preparedIDs.isEmpty
        checks["changedPreviewKeepsSourceRecoveryByID"] = previewGrid.reloads == [[a.id]]
            && previewGrid.missingIDs.isEmpty
        previewGrid.fireTimerForAudit()
        finish(previewGrid)
        checks["nextProbeUsesCurrentPreviewSnapshot"] = previewManager.preparedIDs == [a.id]
            && previewManager.previewResolutionStayedOffMain && previewManager.preparationStayedOnMain

        let cachedManager = ProbeManager()
        cachedManager.cachedThumbnailIDs = [a.id]
        let cached = GridProbe(cachedManager, records: [a], visible: [first])
        cached.fireTimerForAudit()
        finish(cached)
        checks["existingPreviewDoesNotSchedulePreparation"] = cachedManager.previewChecks == [a.id]
            && cachedManager.preparedIDs.isEmpty && cached.reloads.isEmpty
        let invisibleManager = ProbeManager()
        let invisible = GridProbe(invisibleManager, records: [a], visible: [])
        invisible.missingIDs = [a.id]
        invisible.fireTimerForAudit()
        checks["noVisibleItemsClearMissingStateWithoutWorker"] = !invisible.inFlight
            && invisible.missingIDs.isEmpty && invisibleManager.recordedPaths.isEmpty

        let releasedManager = ProbeManager()
        let releaseBarrier = releasedManager.blockNextSourceProbe()
        var released: GridProbe? = GridProbe(releasedManager, records: [a], visible: [first])
        released?.fireTimerForAudit()
        wait("released source probe did not start") { releasedManager.activeCount == 1 }
        weak let weakGrid = released
        released = nil
        checks["slowWorkerDoesNotRetainReleasedGrid"] = weakGrid == nil
        releaseBarrier.release.signal()
        wait("released source probe did not finish") { releasedManager.activeCount == 0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["lateCompletionDoesNotReviveOrPrepareReleasedGrid"] = weakGrid == nil
            && releasedManager.preparedIDs.isEmpty

        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
