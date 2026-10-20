import AppKit
import Foundation

private final class ProbeFileManager: @unchecked Sendable {
    static let shared = ProbeFileManager()
    private let lock = NSLock()
    private var results: [String: Bool] = [:]
    private var barrier: DispatchSemaphore?
    private var paths: [String] = []
    private var active = 0
    private var maximumActive = 0
    private var offMain = true

    func reset(missing: [String]) {
        lock.lock(); defer { lock.unlock() }
        precondition(active == 0)
        results = Dictionary(uniqueKeysWithValues: missing.map { ($0, false) })
        paths = []
        maximumActive = 0
        offMain = true
    }
    func blockNext() -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        let value = DispatchSemaphore(value: 0)
        barrier = value
        return value
    }
    var observation: (paths: [String], active: Int, maxActive: Int, offMain: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (paths, active, maximumActive, offMain)
    }
    func fileExists(atPath path: String) -> Bool {
        lock.lock()
        paths.append(path)
        active += 1
        maximumActive = max(maximumActive, active)
        offMain = offMain && !Thread.isMainThread
        let result = results[path] ?? true
        let pending = barrier
        barrier = nil
        lock.unlock()
        pending?.wait()
        lock.lock()
        active -= 1
        lock.unlock()
        return result
    }
}
private struct Record { let id: String; let path: String }
@MainActor private final class Collection {
    var visible = Set<IndexPath>()
    var reloads: [Set<IndexPath>] = []
    func indexPathsForVisibleItems() -> Set<IndexPath> { visible }
    func reloadItems(at paths: Set<IndexPath>) { reloads.append(paths) }
}
@MainActor private final class Grid {
    // Window/timer admission is exercised separately with real NSWindow owners.
    private var canProbeMissingPaths: Bool { true }
    let collectionView = Collection()
    var orderedIDs: [String] = []
    var wallpapersByID: [String: Record] = [:]
    // PRODUCTION_STATE

    init(_ records: [Record], visible: Set<IndexPath>) {
        replace(records)
        collectionView.visible = visible
    }
    func replace(_ records: [Record]) {
        orderedIDs = records.map(\.id)
        wallpapersByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }
    var inFlight: Bool { isMissingPathProbeInFlight }
    func fire() { probeMissingPaths() }
    // PRODUCTION_PROBE
}

@main private enum Checks {
    @MainActor static func wait(_ reason: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            precondition(Date() < deadline, reason)
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
    }
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let a = Record(id: "a", path: "/fixture/a.png")
        let b = Record(id: "b", path: "/fixture/b.png")
        let first = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)
        let files = ProbeFileManager.shared
        files.reset(missing: [a.path])
        let barrier = files.blockNext()
        let grid = Grid([a], visible: [first])
        grid.fire()
        wait("probe did not enter stat") { files.observation.active == 1 }
        var mainQueueRan = false
        DispatchQueue.main.async { mainQueueRan = true }
        wait("slow stat blocked main queue") { mainQueueRan }
        for _ in 0..<40 { grid.fire() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["slowStatLeavesMainQueueResponsive"] = mainQueueRan && grid.inFlight
        checks["statRunsOffMain"] = files.observation.offMain
        checks["timerBurstDoesNotQueueAnotherBatch"] = files.observation.paths == [a.path]
            && files.observation.maxActive == 1
        barrier.signal()
        wait("missing completion did not release slot") { !grid.inFlight }
        checks["currentMissingRecordReloads"] = grid.collectionView.reloads == [[first]]
        grid.fire()
        wait("second missing completion did not release slot") { !grid.inFlight }
        checks["missingCompletionAllowsNextBatch"] = files.observation.paths == [a.path, a.path]

        files.reset(missing: [])
        let healthy = Grid([a, b], visible: [first])
        healthy.fire()
        wait("healthy completion did not release slot") { !healthy.inFlight }
        healthy.fire()
        wait("second healthy completion did not release slot") { !healthy.inFlight }
        checks["allPresentCompletionAlsoAllowsNextBatch"] = files.observation.paths == [a.path, a.path]
            && healthy.collectionView.reloads.isEmpty
        checks["offscreenRecordsAreNotProbed"] = !files.observation.paths.contains(b.path)

        for scenario in ["pathReplacement", "reorder", "delete", "notVisible"] {
            files.reset(missing: [a.path])
            let pending = files.blockNext()
            let stale = Grid([a, b], visible: [first])
            stale.fire()
            wait("stale stat did not start") { files.observation.active == 1 }
            switch scenario {
            case "pathReplacement": stale.replace([Record(id: a.id, path: "/fixture/new.png"), b])
            case "reorder": stale.replace([b, a]); stale.collectionView.visible = [first, second]
            case "delete": stale.replace([]); stale.collectionView.visible = []
            default: stale.collectionView.visible = [second]
            }
            pending.signal()
            wait("stale result did not release slot") { !stale.inFlight }
            checks["\(scenario)RejectsOldMissingResult"] = stale.collectionView.reloads.isEmpty
        }

        files.reset(missing: [])
        let invisible = Grid([a], visible: [])
        invisible.fire()
        checks["emptyViewportDoesNotReserveOrProbe"] = !invisible.inFlight && files.observation.paths.isEmpty
        files.reset(missing: [a.path])
        let releaseBarrier = files.blockNext()
        var retired: Grid? = Grid([a], visible: [first])
        let collection = retired!.collectionView
        retired?.fire()
        wait("retired stat did not start") { files.observation.active == 1 }
        weak var weakGrid = retired
        retired = nil
        checks["workerDoesNotRetainGrid"] = weakGrid == nil
        releaseBarrier.signal()
        wait("retired stat did not finish") { files.observation.active == 0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        checks["lateCompletionDoesNotReloadRetiredGrid"] = weakGrid == nil && collection.reloads.isEmpty
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
