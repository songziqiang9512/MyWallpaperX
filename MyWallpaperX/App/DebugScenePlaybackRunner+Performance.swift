#if DEBUG
import AppKit
import Darwin
import Foundation

extension DebugScenePlaybackRunner {
    private struct PerformanceResourceSnapshot {
        let sampleCount: Int
        let processSampleCount: Int
        let processFootprintSampledPeakBytes: UInt64
        let processCPUTimeMilliseconds: Double
        let gpuAllocatedSampledPeakBytes: UInt64
        let renderTargetPoolSampledPeakBytes: UInt64
    }

    @MainActor
    private final class PerformanceResourceCollector {
        private var isActive = false
        private var sampleCount = 0
        private var processSampleCount = 0
        private var firstProcessCPUTimeNanoseconds: UInt64?
        private var latestProcessCPUTimeNanoseconds: UInt64?
        private var processFootprintSampledPeakBytes: UInt64 = 0
        private var gpuAllocatedSampledPeakBytes: UInt64 = 0
        private var renderTargetPoolSampledPeakBytes: UInt64 = 0

        func start() {
            isActive = true
            recordSample()
            scheduleNextSample()
        }

        func finish() -> PerformanceResourceSnapshot {
            isActive = false
            recordSample()
            let cpuTimeNanoseconds: UInt64
            if let firstProcessCPUTimeNanoseconds,
               let latestProcessCPUTimeNanoseconds,
               latestProcessCPUTimeNanoseconds >= firstProcessCPUTimeNanoseconds {
                cpuTimeNanoseconds = latestProcessCPUTimeNanoseconds
                    - firstProcessCPUTimeNanoseconds
            } else {
                cpuTimeNanoseconds = 0
            }
            return PerformanceResourceSnapshot(
                sampleCount: sampleCount,
                processSampleCount: processSampleCount,
                processFootprintSampledPeakBytes: processFootprintSampledPeakBytes,
                processCPUTimeMilliseconds: Double(cpuTimeNanoseconds) / 1_000_000,
                gpuAllocatedSampledPeakBytes: gpuAllocatedSampledPeakBytes,
                renderTargetPoolSampledPeakBytes: renderTargetPoolSampledPeakBytes
            )
        }

        private func scheduleNextSample() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.isActive else { return }
                self.recordSample()
                self.scheduleNextSample()
            }
        }

        private func recordSample() {
            DebugScenePlaybackRunner.runtimeHost.refreshPerformanceResourceGauges()
            let counters = ScenePerformanceCounterHub.shared.snapshot()
            sampleCount += 1
            gpuAllocatedSampledPeakBytes = max(
                gpuAllocatedSampledPeakBytes,
                counters[.gpuAllocatedBytes] ?? 0
            )
            renderTargetPoolSampledPeakBytes = max(
                renderTargetPoolSampledPeakBytes,
                counters[.renderTargetPoolBytes] ?? 0
            )
            guard let usage = DebugScenePlaybackRunner.currentProcessResourceUsage()
            else { return }
            processSampleCount += 1
            processFootprintSampledPeakBytes = max(
                processFootprintSampledPeakBytes,
                usage.footprintBytes
            )
            if firstProcessCPUTimeNanoseconds == nil {
                firstProcessCPUTimeNanoseconds = usage.cpuTimeNanoseconds
            }
            latestProcessCPUTimeNanoseconds = usage.cpuTimeNanoseconds
        }
    }

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
        let resourceCollector = PerformanceResourceCollector()
        DispatchQueue.main.asyncAfter(deadline: .now() + window.start) {
            SceneFramePerformanceTelemetry.debugEvidence.reset(
                targetFPS: targetFPS
            )
            resourceCollector.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + window.end) {
            let resources = resourceCollector.finish()
            let value = SceneFramePerformanceTelemetry.debugEvidence.snapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=performance targetFPS=%d elapsed=%.3f callbacks=%d submitted=%d completed=%d failed=%d submittedFPS=%.3f completedFPS=%.3f presented=%d presentStreams=%d presentIntervals=%d presentP50MS=%.3f presentP95MS=%.3f presentP99MS=%.3f presentMaxMS=%.3f presentOver1_5Budget=%d callbackP50MS=%.3f callbackP95MS=%.3f callbackMaxMS=%.3f callbackOver16=%d callbackOver33=%d discontinuities=%d droppedMS=%.3f maxRawFrameMS=%.3f drawableMissed=%d drawableWaitP95MS=%.3f drawableWaitMaxMS=%.3f preEncodeP95MS=%.3f preEncodeMaxMS=%.3f mainFrameP95MS=%.3f mainFrameMaxMS=%.3f cpuP50MS=%.3f cpuP95MS=%.3f cpuMaxMS=%.3f cpuOver16=%d cpuOver33=%d gpuSamples=%d gpuP50MS=%.3f gpuP95MS=%.3f gpuMaxMS=%.3f gpuOver16=%d gpuOver33=%d",
                targetFPS,
                value.elapsed,
                value.driverCallbacks,
                value.submitted,
                value.completed,
                value.failed,
                value.submittedFPS,
                value.completedFPS,
                value.presented,
                value.presentationStreamCount,
                value.presentationIntervalCount,
                value.presentationIntervalP50 * 1_000,
                value.presentationIntervalP95 * 1_000,
                value.presentationIntervalP99 * 1_000,
                value.presentationIntervalMax * 1_000,
                value.presentationOverOneAndHalfBudget,
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
            NSLog(
                "MWX DEBUG SCENE: phase=performance-resources samples=%d processSamples=%d processFootprintSampledPeakBytes=%llu processCPUTimeMS=%.3f gpuAllocatedSampledPeakBytes=%llu renderTargetPoolSampledPeakBytes=%llu",
                resources.sampleCount,
                resources.processSampleCount,
                resources.processFootprintSampledPeakBytes,
                resources.processCPUTimeMilliseconds,
                resources.gpuAllocatedSampledPeakBytes,
                resources.renderTargetPoolSampledPeakBytes
            )
        }
    }

    private static func currentProcessResourceUsage() -> (
        footprintBytes: UInt64,
        cpuTimeNanoseconds: UInt64
    )? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        let (cpuTimeNanoseconds, overflow) = usage.ri_user_time
            .addingReportingOverflow(usage.ri_system_time)
        return (
            footprintBytes: usage.ri_phys_footprint,
            cpuTimeNanoseconds: overflow ? UInt64.max : cpuTimeNanoseconds
        )
    }
}
#endif
