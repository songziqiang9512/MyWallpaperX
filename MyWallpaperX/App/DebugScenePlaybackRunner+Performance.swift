#if DEBUG
import AppKit
import Foundation

extension DebugScenePlaybackRunner {
    static func applyRequestedPerformanceProfile() -> Bool {
        let flag = "--mwx-debug-scene-performance-fps"
        guard ProcessInfo.processInfo.arguments.contains(flag) else { return true }
        guard let raw = argumentValue(after: flag),
              let framesPerSecond = Int(raw),
              let profile = PlaybackPerformanceProfile(rawValue: framesPerSecond) else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-performance-profile"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
            return false
        }
        runtimeHost.applyPerformanceProfile(profile)
        NSLog(
            "MWX DEBUG SCENE: phase=performance-profile targetFPS=%d",
            profile.maxFPS
        )
        return true
    }

    static func schedulePerformanceMeasurement(
        duration: TimeInterval,
        afterSnapshotDelay: TimeInterval
    ) {
        let targetFPS = runtimeHost.performanceProfile.maxFPS
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
                "MWX DEBUG SCENE: phase=performance targetFPS=%d elapsed=%.3f callbacks=%d submitted=%d completed=%d failed=%d submittedFPS=%.3f completedFPS=%.3f callbackP50MS=%.3f callbackP95MS=%.3f callbackMaxMS=%.3f callbackOver16=%d callbackOver33=%d discontinuities=%d droppedMS=%.3f maxRawFrameMS=%.3f drawableMissed=%d drawableWaitP95MS=%.3f drawableWaitMaxMS=%.3f preEncodeP95MS=%.3f preEncodeMaxMS=%.3f mainFrameP95MS=%.3f mainFrameMaxMS=%.3f cpuP50MS=%.3f cpuP95MS=%.3f cpuMaxMS=%.3f cpuOver16=%d cpuOver33=%d gpuSamples=%d gpuP50MS=%.3f gpuP95MS=%.3f gpuMaxMS=%.3f gpuOver16=%d gpuOver33=%d",
                targetFPS,
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
                value.discontinuityCount,
                value.droppedFrameTime * 1_000,
                value.maximumRawFrameTime * 1_000,
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
            let stages = SceneFramePerformanceTelemetry.debugEvidence.stageSummary()
            let stageLine = stages.keys.sorted().map { name in
                let summary = stages[name] ?? (0, 0, 0)
                return "\(name)=p50:\(String(format: "%.3f", summary.0 * 1_000))ms p95:\(String(format: "%.3f", summary.1 * 1_000))ms n:\(summary.2)"
            }.joined(separator: " ")
            if !stageLine.isEmpty {
                NSLog("MWX DEBUG SCENE: phase=performance-stages %@", stageLine)
            }
        }
    }
}
#endif
