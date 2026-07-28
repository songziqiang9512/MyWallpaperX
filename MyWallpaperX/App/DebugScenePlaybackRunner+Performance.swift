#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static func schedulePerformanceMeasurement(
        duration: TimeInterval,
        afterSnapshotDelay: TimeInterval
    ) {
        let latestEnd = duration - 1.5
        let candidates = [
            (start: afterSnapshotDelay + 0.75, end: latestEnd),
            (start: 2.0, end: min(latestEnd, afterSnapshotDelay - 0.5)),
        ].filter { $0.end - $0.start >= 1 }
        guard let window = candidates.max(by: {
            ($0.end - $0.start) < ($1.end - $1.start)
        }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + window.start) {
            SceneFramePerformanceTelemetry.debugEvidence.reset()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + window.end) {
            let value = SceneFramePerformanceTelemetry.debugEvidence.snapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=performance elapsed=%.3f callbacks=%d submitted=%d completed=%d failed=%d submittedFPS=%.3f completedFPS=%.3f callbackP50MS=%.3f callbackP95MS=%.3f callbackMaxMS=%.3f callbackOver16=%d callbackOver33=%d drawableMissed=%d drawableWaitP95MS=%.3f drawableWaitMaxMS=%.3f preEncodeP95MS=%.3f preEncodeMaxMS=%.3f mainFrameP95MS=%.3f mainFrameMaxMS=%.3f cpuP50MS=%.3f cpuP95MS=%.3f cpuMaxMS=%.3f cpuOver16=%d cpuOver33=%d gpuSamples=%d gpuP50MS=%.3f gpuP95MS=%.3f gpuMaxMS=%.3f gpuOver16=%d gpuOver33=%d",
                value.elapsed,
                value.driverCallbacks,
                value.submitted,
                value.completed,
                value.failed,
                value.submittedFPS,
                value.completedFPS,
                value.callbackIntervalP50 * 1_000,
                value.callbackIntervalP95 * 1_000,
                value.callbackIntervalMax * 1_000,
                value.callbackOverBudget,
                value.callbackOverDoubleBudget,
                value.drawableMissed,
                value.drawableWaitP95 * 1_000,
                value.drawableWaitMax * 1_000,
                value.preEncodeP95 * 1_000,
                value.preEncodeMax * 1_000,
                value.mainFrameP95 * 1_000,
                value.mainFrameMax * 1_000,
                value.cpuFrameP50 * 1_000,
                value.cpuFrameP95 * 1_000,
                value.cpuFrameMax * 1_000,
                value.cpuOverBudget,
                value.cpuOverDoubleBudget,
                value.gpuSampleCount,
                value.gpuFrameP50 * 1_000,
                value.gpuFrameP95 * 1_000,
                value.gpuFrameMax * 1_000,
                value.gpuOverBudget,
                value.gpuOverDoubleBudget
            )
        }
    }
}
#endif
