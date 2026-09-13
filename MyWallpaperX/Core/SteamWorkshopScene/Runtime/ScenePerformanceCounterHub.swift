import Foundation

/// Always-on lightweight performance counters for the Scene runtime frame
/// path (enabled in Release too). Contract: fixed-capacity accumulation
/// slots indexed by metric — no unbounded arrays, no sorting, no
/// percentiles. Per-frame cost is one NSLock plus a few integer adds. The
/// hub stores no history windows; callers diff snapshots themselves.
enum ScenePerformanceMetric: Int, CaseIterable, Sendable {
    case frameAttempts
    case framesRendered
    case framesBusy
    case framesDropped
    case framesInactive
    case cpuFrameMicros
    case rendererMicros
    case drawableWaitMicros
    case drawCalls
    // Renderer frame stages. `prologueMicros` includes the nested
    // `frameAdmissionMicros` window; both accumulate independently.
    case sourceUpdateMicros
    case worldResolveMicros
    case prologueMicros
    case frameAdmissionMicros
    case prepassMicros
    case layerLoopMicros
    case compositorSealMicros
}

/// Scene launch phases with first-occurrence uptime timestamps. Capacity is
/// bounded by the enum case count; repeated recordings are ignored.
enum SceneLaunchPhase: String, CaseIterable, Sendable {
    case accepted
    case preparingModel
    case preparingPrograms
    case preparingResources
    case preparingSurfaces
    case launched
    case firstVisibleFrame
}

nonisolated final class ScenePerformanceCounterHub: @unchecked Sendable {
    static let shared = ScenePerformanceCounterHub()

    private let lock = NSLock()
    private var counters: [UInt64] = Array(
        repeating: 0, count: ScenePerformanceMetric.allCases.count
    )
    private var firstLaunchPhaseUptimeMicros: [SceneLaunchPhase: UInt64] = [:]

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    func bump(_ metric: ScenePerformanceMetric) {
        withLock { counters[metric.rawValue] &+= 1 }
    }

    func add(_ metric: ScenePerformanceMetric, _ amount: UInt64) {
        withLock { counters[metric.rawValue] &+= amount }
    }

    func snapshot() -> [ScenePerformanceMetric: UInt64] {
        withLock {
            Dictionary(
                uniqueKeysWithValues: ScenePerformanceMetric.allCases.map {
                    ($0, counters[$0.rawValue])
                }
            )
        }
    }

    /// Records only the first observation of a launch phase; later calls
    /// for an already-recorded phase are ignored.
    func recordLaunchPhase(_ phase: SceneLaunchPhase, uptimeMicros: UInt64) {
        withLock {
            guard firstLaunchPhaseUptimeMicros[phase] == nil else { return }
            firstLaunchPhaseUptimeMicros[phase] = uptimeMicros
        }
    }

    func launchPhaseSnapshot() -> [SceneLaunchPhase: UInt64] {
        withLock { firstLaunchPhaseUptimeMicros }
    }

    /// Current process uptime in microseconds, the same time domain used
    /// for launch phase timestamps.
    static func nowUptimeMicros() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
    }

    /// Elapsed microseconds since a prior `systemUptime` sample, clamped
    /// to zero so counter math can never trap on clock jitter.
    static func micros(since start: TimeInterval) -> UInt64 {
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000_000
        return elapsed > 0 ? UInt64(elapsed) : 0
    }
}
