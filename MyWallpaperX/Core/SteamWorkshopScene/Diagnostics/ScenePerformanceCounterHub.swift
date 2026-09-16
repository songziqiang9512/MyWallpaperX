import Foundation

/// Always-on lightweight performance counters for the Scene runtime frame
/// path (enabled in Release too). Contract: fixed-capacity accumulation
/// slots indexed by metric — no unbounded arrays, no sorting, no
/// percentiles. Each update is one NSLock plus fixed integer work. The hub
/// stores no history windows; callers diff snapshots themselves.
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
    case pipelineStateBinds
    case geometryDrawCalls
    case fallbackBranches
    // Gauges sampled by the daemon at 1 Hz. `gpuAllocatedBytes` is Metal's
    // process/device allocation total; it deliberately does not claim to be
    // texture-only memory. `renderTargetPoolBytes` is the sum of the runtime's
    // bounded render-target pool accounting values.
    case gpuAllocatedBytes
    case renderTargetPoolBytes
    // Renderer frame stages. `prologueMicros` includes the nested
    // `frameAdmissionMicros` window; both accumulate independently.
    case sourceUpdateMicros
    case worldResolveMicros
    case prologueMicros
    case frameAdmissionMicros
    case prepassMicros
    case layerLoopMicros
    case compositorSealMicros
    // Frame-path GPU operation census. These count encoded work — pass
    // creations and whole-texture copies — so a composition change can be
    // aimed at a named operation and then judged by GPU time. They are counts,
    // never durations: no CPU-side bookkeeping can attribute GPU time to a
    // pass, and none of these values may be read as one.
    // `mainPassRenderPasses` includes the `depthRenderPasses` subset;
    // `textureCopyBytes` includes `framebufferCaptureBytes`.
    case mainPassRenderPasses
    case depthRenderPasses
    case offscreenRenderPasses
    case textureCopyPasses
    case framebufferCaptures
    case framebufferCaptureBytes
    case graphOutputPublicationCopies
    case textureCopyBytes
    /// Copies whose pixel format has no known bytes-per-pixel. They are counted
    /// rather than guessed, so a byte total is never silently understated.
    case unmeasuredCopyPasses
    // Offscreen pass categories. They partition `offscreenRenderPasses`, which
    // is what makes a redundant clear/capture pass visible as a named cost
    // instead of one opaque total.
    case resolvedMaterialRenderPasses
    case graphResourceSourceCaptures
    case graphResourceInitializations
    case offscreenEffectCaptures
}

/// Why an offscreen render pass was encoded. Every case must feed exactly one
/// category counter so the categories stay a partition of the offscreen total.
enum SceneOffscreenPassKind: Sendable {
    case resolvedMaterial
    case graphResourceSourceCapture
    case graphResourceInitialization
    case offscreenEffectCapture

    var metric: ScenePerformanceMetric {
        switch self {
        case .resolvedMaterial:
            return .resolvedMaterialRenderPasses
        case .graphResourceSourceCapture:
            return .graphResourceSourceCaptures
        case .graphResourceInitialization:
            return .graphResourceInitializations
        case .offscreenEffectCapture:
            return .offscreenEffectCaptures
        }
    }
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

    func set(_ metric: ScenePerformanceMetric, _ value: UInt64) {
        withLock { counters[metric.rawValue] = value }
    }

    /// Records one submitted Metal draw and its optional prepared/instanced
    /// geometry branch with one lock acquisition.
    func recordDraw(usesGeometry: Bool) {
        withLock {
            counters[ScenePerformanceMetric.drawCalls.rawValue] &+= 1
            if usesGeometry {
                counters[ScenePerformanceMetric.geometryDrawCalls.rawValue] &+= 1
            }
        }
    }

    /// Records one created main composite pass. Each creation is one pass split,
    /// so this is the pass-merge target for AS3; `usesDepth` marks a pass that
    /// carries a depth attachment and therefore a depth load/store.
    func recordMainPassRender(usesDepth: Bool) {
        withLock {
            counters[ScenePerformanceMetric.mainPassRenderPasses.rawValue] &+= 1
            if usesDepth {
                counters[ScenePerformanceMetric.depthRenderPasses.rawValue] &+= 1
            }
        }
    }

    /// An offscreen render pass: resolved material passes, graph resource
    /// captures/initializations, and offscreen effect captures.
    func recordOffscreenRender(_ kind: SceneOffscreenPassKind) {
        withLock {
            counters[ScenePerformanceMetric.offscreenRenderPasses.rawValue] &+= 1
            counters[kind.metric.rawValue] &+= 1
        }
    }

    /// Records one whole-texture copy pass and the bytes it moves. A `nil`
    /// byte count means the pixel format has no known bytes-per-pixel; the
    /// pass is counted as unmeasured instead of contributing a guessed size.
    func recordTextureCopy(byteCount: Int?) {
        withLock { recordCopyLocked(byteCount: byteCount) }
    }

    /// Records one full-frame framebuffer snapshot and its byte volume. This is
    /// the operation AS3 removes first when it has no consumer, so it is kept
    /// separate from ordinary exact copies.
    func recordFramebufferCapture(byteCount: Int?) {
        withLock {
            recordCopyLocked(byteCount: byteCount)
            counters[ScenePerformanceMetric.framebufferCaptures.rawValue] &+= 1
            if let byteCount {
                counters[ScenePerformanceMetric.framebufferCaptureBytes.rawValue] &+= UInt64(
                    max(byteCount, 0)
                )
            }
        }
    }

    /// Records one named-graph-output publication copy and its byte volume.
    func recordGraphOutputPublication(byteCount: Int?) {
        withLock {
            recordCopyLocked(byteCount: byteCount)
            counters[ScenePerformanceMetric.graphOutputPublicationCopies.rawValue] &+= 1
        }
    }

    private func recordCopyLocked(byteCount: Int?) {
        counters[ScenePerformanceMetric.textureCopyPasses.rawValue] &+= 1
        guard let byteCount else {
            counters[ScenePerformanceMetric.unmeasuredCopyPasses.rawValue] &+= 1
            return
        }
        counters[ScenePerformanceMetric.textureCopyBytes.rawValue] &+= UInt64(
            max(byteCount, 0)
        )
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
