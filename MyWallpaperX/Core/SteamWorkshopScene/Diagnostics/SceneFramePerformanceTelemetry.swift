import Foundation
@preconcurrency import Metal
@preconcurrency import QuartzCore

nonisolated struct SceneFramePerformanceSnapshot: Sendable {
    let elapsed: TimeInterval
    let driverCallbacks: Int
    let submitted: Int
    let completed: Int
    let failed: Int
    let submittedFPS: Double
    let completedFPS: Double
    let presented: Int
    let presentationStreamCount: Int
    let presentationIntervalCount: Int
    let presentationIntervalP50: TimeInterval
    let presentationIntervalP95: TimeInterval
    let presentationIntervalP99: TimeInterval
    let presentationIntervalMax: TimeInterval
    let presentationOverOneAndHalfBudget: Int
    let callbackIntervalP50: TimeInterval
    let callbackIntervalP95: TimeInterval
    let callbackIntervalMax: TimeInterval
    let callbackOverBudget: Int
    let callbackOverDoubleBudget: Int
    let discontinuityCount: Int
    let droppedFrameTime: TimeInterval
    let maximumRawFrameTime: TimeInterval
    let drawableMissed: Int
    let drawableWaitP95: TimeInterval
    let drawableWaitMax: TimeInterval
    let preEncodeP95: TimeInterval
    let preEncodeMax: TimeInterval
    let mainFrameP95: TimeInterval
    let mainFrameMax: TimeInterval
    let cpuFrameP50: TimeInterval
    let cpuFrameP95: TimeInterval
    let cpuFrameMax: TimeInterval
    let cpuOverBudget: Int
    let cpuOverDoubleBudget: Int
    let gpuSampleCount: Int
    let gpuFrameP50: TimeInterval
    let gpuFrameP95: TimeInterval
    let gpuFrameMax: TimeInterval
    let gpuOverBudget: Int
    let gpuOverDoubleBudget: Int
}

nonisolated final class SceneFramePerformanceTelemetry: @unchecked Sendable {
    static let debugEvidence = SceneFramePerformanceTelemetry()
    private static let frameBudget = 1.0 / 60.0
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var measurementStart = ProcessInfo.processInfo.systemUptime
    private var lastDriverCallback: TimeInterval?
    private var driverCallbacks = 0
    private var submitted = 0
    private var completed = 0
    private var failed = 0
    private var presented = 0
    private var presentationFrameBudget: TimeInterval = 1.0 / 60.0
    private var lastPresentationByStreamID: [UInt64: TimeInterval] = [:]
    private var presentationIntervals: [TimeInterval] = []
    private var drawableMissed = 0
    private var callbackIntervals: [TimeInterval] = []
    private var stageDurations: [String: [TimeInterval]] = [:]
    private var openStages: [String: TimeInterval] = [:]
    private var frameStageDurations: [String: [TimeInterval]] = [:]
    private var openFrameStageTotals: [String: TimeInterval] = [:]
    private var discontinuityCount = 0
    private var droppedFrameTime: TimeInterval = 0
    private var maximumRawFrameTime: TimeInterval = 0
    private var cpuFrameDurations: [TimeInterval] = []
    private var gpuFrameDurations: [TimeInterval] = []
    private var drawableWaitDurations: [TimeInterval] = []
    private var preEncodeDurations: [TimeInterval] = []
    private var mainFrameDurations: [TimeInterval] = []

    func reset(
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        targetFPS: Int = 60
    ) {
        precondition(targetFPS == 30 || targetFPS == 60)
        withLock {
            generation &+= 1
            measurementStart = uptime
            lastDriverCallback = nil
            driverCallbacks = 0
            submitted = 0
            completed = 0
            failed = 0
            presented = 0
            presentationFrameBudget = 1.0 / Double(targetFPS)
            lastPresentationByStreamID.removeAll(keepingCapacity: true)
            presentationIntervals.removeAll(keepingCapacity: true)
            drawableMissed = 0
            callbackIntervals.removeAll(keepingCapacity: true)
            stageDurations.removeAll(keepingCapacity: true)
            openStages.removeAll(keepingCapacity: true)
            frameStageDurations.removeAll(keepingCapacity: true)
            openFrameStageTotals.removeAll(keepingCapacity: true)
            discontinuityCount = 0
            droppedFrameTime = 0
            maximumRawFrameTime = 0
            cpuFrameDurations.removeAll(keepingCapacity: true)
            gpuFrameDurations.removeAll(keepingCapacity: true)
            drawableWaitDurations.removeAll(keepingCapacity: true)
            preEncodeDurations.removeAll(keepingCapacity: true)
            mainFrameDurations.removeAll(keepingCapacity: true)
        }
    }

    func recordDriverCallback(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        withLock {
            if let lastDriverCallback {
                callbackIntervals.append(max(0, uptime - lastDriverCallback))
            }
            lastDriverCallback = uptime
            driverCallbacks += 1
        }
    }

    func recordCPUFrame(duration: TimeInterval) {
        withLock {
            cpuFrameDurations.append(max(0, duration))
            // Frame boundary for the per-frame stage view: every stage that ran
            // inside this frame has already ended, so fold the running totals
            // and start the next frame clean. Per-call stages therefore become
            // comparable with per-frame stages, which raw percentiles cannot be.
            for (name, total) in openFrameStageTotals {
                frameStageDurations[name, default: []].append(total)
            }
            openFrameStageTotals.removeAll(keepingCapacity: true)
        }
    }

    /// Coarse CPU stage attribution for active profiling runs only; the
    /// telemetry itself exists exclusively in benchmark/evidence mode, so
    /// ordinary playback never pays for these readings beyond a clock read.
    func beginStage(_ name: String) {
        withLock { openStages[name] = ProcessInfo.processInfo.systemUptime }
    }

    func endStage(_ name: String) {
        let now = ProcessInfo.processInfo.systemUptime
        withLock {
            if let start = openStages.removeValue(forKey: name) {
                let elapsed = max(0, now - start)
                stageDurations[name, default: []].append(elapsed)
                openFrameStageTotals[name, default: 0] += elapsed
            }
        }
    }

    func stageSummary() -> [String: (p50: TimeInterval, p95: TimeInterval, count: Int)] {
        withLock {
            stageDurations.mapValues { values in
                (
                    Self.percentile(values, 0.50),
                    Self.percentile(values, 0.95),
                    values.count
                )
            }
        }
    }

    /// Per-frame stage totals. A nested stage that runs several times per frame
    /// contributes its frame sum here, so percentile-over-frames figures are
    /// additive against other per-frame stages.
    func frameStageSummary() -> [String: (p50: TimeInterval, p95: TimeInterval, count: Int)] {
        withLock {
            frameStageDurations.mapValues { values in
                (
                    Self.percentile(values, 0.50),
                    Self.percentile(values, 0.95),
                    values.count
                )
            }
        }
    }

    func recordFrameDelta(raw: TimeInterval, dropped: TimeInterval) {
        guard raw.isFinite, dropped.isFinite, raw >= 0, dropped >= 0 else { return }
        withLock {
            maximumRawFrameTime = max(maximumRawFrameTime, raw)
            droppedFrameTime += dropped
            if dropped > 0 {
                discontinuityCount += 1
            }
        }
    }

    func recordDrawableMiss() {
        withLock { drawableMissed += 1 }
    }

    func recordPreparation(drawableWait: TimeInterval, preEncode: TimeInterval) {
        withLock {
            drawableWaitDurations.append(max(0, drawableWait))
            preEncodeDurations.append(max(0, preEncode))
        }
    }

    func recordMainFrame(duration: TimeInterval) {
        withLock { mainFrameDurations.append(max(0, duration)) }
    }

    func recordCommandBufferUnavailable() {
        withLock { failed += 1 }
    }

    func recordSubmitted(on commandBuffer: MTLCommandBuffer) {
        let token = withLock { () -> UInt64 in
            submitted += 1
            return generation
        }
        commandBuffer.addCompletedHandler { [weak self] buffer in
            self?.recordCompletion(buffer, generation: token)
        }
    }

    func recordWillPresent(_ drawable: CAMetalDrawable, streamID: UInt64) {
        let token = withLock { generation }
        drawable.addPresentedHandler { [weak self] presentedDrawable in
            self?.recordPresented(
                at: presentedDrawable.presentedTime,
                streamID: streamID,
                generation: token
            )
        }
    }

    func recordPresented(at uptime: TimeInterval, streamID: UInt64) {
        let token = withLock { generation }
        recordPresented(at: uptime, streamID: streamID, generation: token)
    }

    func snapshot(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime)
        -> SceneFramePerformanceSnapshot {
        withLock {
            let elapsed = max(uptime - measurementStart, .leastNonzeroMagnitude)
            return SceneFramePerformanceSnapshot(
                elapsed: elapsed,
                driverCallbacks: driverCallbacks,
                submitted: submitted,
                completed: completed,
                failed: failed,
                submittedFPS: Double(submitted) / elapsed,
                completedFPS: Double(completed) / elapsed,
                presented: presented,
                presentationStreamCount: lastPresentationByStreamID.count,
                presentationIntervalCount: presentationIntervals.count,
                presentationIntervalP50: Self.percentile(
                    presentationIntervals, 0.50
                ),
                presentationIntervalP95: Self.percentile(
                    presentationIntervals, 0.95
                ),
                presentationIntervalP99: Self.percentile(
                    presentationIntervals, 0.99
                ),
                presentationIntervalMax: presentationIntervals.max() ?? 0,
                presentationOverOneAndHalfBudget: Self.countOverThreshold(
                    presentationIntervals,
                    threshold: presentationFrameBudget * 1.5
                ),
                callbackIntervalP50: Self.percentile(callbackIntervals, 0.50),
                callbackIntervalP95: Self.percentile(callbackIntervals, 0.95),
                callbackIntervalMax: callbackIntervals.max() ?? 0,
                callbackOverBudget: Self.countOverBudget(callbackIntervals, multiplier: 1),
                callbackOverDoubleBudget: Self.countOverBudget(callbackIntervals, multiplier: 2),
                discontinuityCount: discontinuityCount,
                droppedFrameTime: droppedFrameTime,
                maximumRawFrameTime: maximumRawFrameTime,
                drawableMissed: drawableMissed,
                drawableWaitP95: Self.percentile(drawableWaitDurations, 0.95),
                drawableWaitMax: drawableWaitDurations.max() ?? 0,
                preEncodeP95: Self.percentile(preEncodeDurations, 0.95),
                preEncodeMax: preEncodeDurations.max() ?? 0,
                mainFrameP95: Self.percentile(mainFrameDurations, 0.95),
                mainFrameMax: mainFrameDurations.max() ?? 0,
                cpuFrameP50: Self.percentile(cpuFrameDurations, 0.50),
                cpuFrameP95: Self.percentile(cpuFrameDurations, 0.95),
                cpuFrameMax: cpuFrameDurations.max() ?? 0,
                cpuOverBudget: Self.countOverBudget(cpuFrameDurations, multiplier: 1),
                cpuOverDoubleBudget: Self.countOverBudget(cpuFrameDurations, multiplier: 2),
                gpuSampleCount: gpuFrameDurations.count,
                gpuFrameP50: Self.percentile(gpuFrameDurations, 0.50),
                gpuFrameP95: Self.percentile(gpuFrameDurations, 0.95),
                gpuFrameMax: gpuFrameDurations.max() ?? 0,
                gpuOverBudget: Self.countOverBudget(gpuFrameDurations, multiplier: 1),
                gpuOverDoubleBudget: Self.countOverBudget(gpuFrameDurations, multiplier: 2)
            )
        }
    }

    private func recordCompletion(_ commandBuffer: MTLCommandBuffer, generation token: UInt64) {
        let succeeded = commandBuffer.status == .completed
        let gpuStart = commandBuffer.gpuStartTime
        let gpuEnd = commandBuffer.gpuEndTime
        withLock {
            guard generation == token else { return }
            if succeeded {
                completed += 1
            } else {
                failed += 1
            }
            if gpuStart > 0, gpuEnd >= gpuStart {
                gpuFrameDurations.append(gpuEnd - gpuStart)
            }
        }
    }

    private func recordPresented(
        at uptime: TimeInterval,
        streamID: UInt64,
        generation token: UInt64
    ) {
        guard uptime.isFinite, uptime > 0 else { return }
        withLock {
            guard generation == token else { return }
            presented += 1
            if let previous = lastPresentationByStreamID[streamID],
               uptime > previous {
                presentationIntervals.append(uptime - previous)
            }
            lastPresentationByStreamID[streamID] = max(
                uptime,
                lastPresentationByStreamID[streamID] ?? 0
            )
        }
    }

    private static func percentile(_ values: [TimeInterval], _ quantile: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * quantile).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private static func countOverBudget(_ values: [TimeInterval], multiplier: Double) -> Int {
        let threshold = frameBudget * multiplier
        return countOverThreshold(values, threshold: threshold)
    }

    private static func countOverThreshold(
        _ values: [TimeInterval],
        threshold: TimeInterval
    ) -> Int {
        return values.reduce(into: 0) { count, value in
            if value > threshold { count += 1 }
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
