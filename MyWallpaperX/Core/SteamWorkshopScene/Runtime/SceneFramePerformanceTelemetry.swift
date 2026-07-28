import Foundation
@preconcurrency import Metal

nonisolated struct SceneFramePerformanceSnapshot: Sendable {
    let elapsed: TimeInterval
    let driverCallbacks: Int
    let submitted: Int
    let completed: Int
    let failed: Int
    let submittedFPS: Double
    let completedFPS: Double
    let callbackIntervalP50: TimeInterval
    let callbackIntervalP95: TimeInterval
    let callbackIntervalMax: TimeInterval
    let callbackOverBudget: Int
    let callbackOverDoubleBudget: Int
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
    private var drawableMissed = 0
    private var callbackIntervals: [TimeInterval] = []
    private var cpuFrameDurations: [TimeInterval] = []
    private var gpuFrameDurations: [TimeInterval] = []
    private var drawableWaitDurations: [TimeInterval] = []
    private var preEncodeDurations: [TimeInterval] = []
    private var mainFrameDurations: [TimeInterval] = []

    func reset(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        withLock {
            generation &+= 1
            measurementStart = uptime
            lastDriverCallback = nil
            driverCallbacks = 0
            submitted = 0
            completed = 0
            failed = 0
            drawableMissed = 0
            callbackIntervals.removeAll(keepingCapacity: true)
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
                callbackIntervalP50: Self.percentile(callbackIntervals, 0.50),
                callbackIntervalP95: Self.percentile(callbackIntervals, 0.95),
                callbackIntervalMax: callbackIntervals.max() ?? 0,
                callbackOverBudget: Self.countOverBudget(callbackIntervals, multiplier: 1),
                callbackOverDoubleBudget: Self.countOverBudget(callbackIntervals, multiplier: 2),
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

    private static func percentile(_ values: [TimeInterval], _ quantile: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * quantile).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    private static func countOverBudget(_ values: [TimeInterval], multiplier: Double) -> Int {
        let threshold = frameBudget * multiplier
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
