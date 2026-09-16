#if DEBUG
import AppKit
import Darwin
import Foundation

extension DebugScenePlaybackRunner {
    private struct PerformanceResourceSnapshot {
        let sampleCount: Int
        let processSampleCount: Int
        let processFootprintSampledPeakBytes: UInt64
        let processCPUTimeMilliseconds: Double?
        let processCPUTimeStatus: String
        let gpuAllocatedSampledPeakBytes: UInt64
        let renderTargetPoolSampledPeakBytes: UInt64
        let gpuCensus: [ScenePerformanceMetric: UInt64]
    }

    @MainActor
    private final class PerformanceResourceCollector {
        /// Census metrics read from the always-on hub. The collector diffs the
        /// hub across the measurement window so the emitted figures describe
        /// this window only, not process lifetime.
        private static let gpuCensusMetrics: [ScenePerformanceMetric] = [
            .mainPassRenderPasses, .depthRenderPasses, .offscreenRenderPasses,
            .resolvedMaterialRenderPasses, .graphResourceSourceCaptures,
            .graphResourceInitializations, .offscreenEffectCaptures,
            .textureCopyPasses, .framebufferCaptures, .framebufferCaptureBytes,
            .graphOutputPublicationCopies, .textureCopyBytes, .unmeasuredCopyPasses,
        ]

        private var isActive = false
        private var sampleTimer: DispatchSourceTimer?
        private var sampleCount = 0
        private var processSampleCount = 0
        private var firstProcessCPUTimeMachTicks: UInt64?
        private var latestProcessCPUTimeMachTicks: UInt64?
        private var processCPUTimeFailure: DebugSceneProcessCPUTime.Failure?
        private var processFootprintSampledPeakBytes: UInt64 = 0
        private var gpuAllocatedSampledPeakBytes: UInt64 = 0
        private var renderTargetPoolSampledPeakBytes: UInt64 = 0
        private var gpuCensusBaseline: [ScenePerformanceMetric: UInt64] = [:]

        func start() {
            isActive = true
            gpuCensusBaseline = ScenePerformanceCounterHub.shared.snapshot()
            recordSample()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(
                deadline: .now() + .seconds(1),
                repeating: .seconds(1),
                leeway: .milliseconds(50)
            )
            timer.setEventHandler { [weak self] in
                guard let self, self.isActive else { return }
                self.recordSample()
            }
            sampleTimer = timer
            timer.resume()
        }

        func finish() -> PerformanceResourceSnapshot {
            isActive = false
            sampleTimer?.cancel()
            sampleTimer = nil
            recordSample()
            let cpuTime = measuredProcessCPUTime()
            return PerformanceResourceSnapshot(
                sampleCount: sampleCount,
                processSampleCount: processSampleCount,
                processFootprintSampledPeakBytes: processFootprintSampledPeakBytes,
                processCPUTimeMilliseconds: cpuTime.milliseconds,
                processCPUTimeStatus: cpuTime.status,
                gpuAllocatedSampledPeakBytes: gpuAllocatedSampledPeakBytes,
                renderTargetPoolSampledPeakBytes: renderTargetPoolSampledPeakBytes,
                gpuCensus: gpuCensusDeltas()
            )
        }

        /// Window-scoped census: current hub totals minus the window-start
        /// snapshot. A counter that regressed (reset elsewhere) reports zero
        /// rather than a wrapped value.
        private func gpuCensusDeltas() -> [ScenePerformanceMetric: UInt64] {
            let now = ScenePerformanceCounterHub.shared.snapshot()
            return Self.gpuCensusMetrics.reduce(into: [:]) { result, metric in
                let current = now[metric] ?? 0
                let baseline = gpuCensusBaseline[metric] ?? 0
                result[metric] = current >= baseline ? current - baseline : 0
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
            switch DebugScenePlaybackRunner.currentProcessResourceUsage() {
            case let .success(usage):
                processSampleCount += 1
                processFootprintSampledPeakBytes = max(
                    processFootprintSampledPeakBytes,
                    usage.footprintBytes
                )
                if firstProcessCPUTimeMachTicks == nil {
                    firstProcessCPUTimeMachTicks = usage.cpuTimeMachTicks
                }
                latestProcessCPUTimeMachTicks = usage.cpuTimeMachTicks
            case let .failure(failure):
                if processCPUTimeFailure == nil {
                    processCPUTimeFailure = failure
                }
            }
        }

        private func measuredProcessCPUTime() -> (
            milliseconds: Double?,
            status: String
        ) {
            if let processCPUTimeFailure {
                return (nil, processCPUTimeFailure.rawValue)
            }
            guard let firstProcessCPUTimeMachTicks,
                  let latestProcessCPUTimeMachTicks else {
                let failure = DebugSceneProcessCPUTime.Failure.processSampleUnavailable
                return (nil, failure.rawValue)
            }
            let timebase: DebugSceneProcessCPUTime.Timebase
            switch DebugSceneProcessCPUTime.currentTimebase() {
            case let .success(value):
                timebase = value
            case let .failure(failure):
                return (nil, failure.rawValue)
            }
            switch DebugSceneProcessCPUTime.elapsedMilliseconds(
                firstMachTicks: firstProcessCPUTimeMachTicks,
                latestMachTicks: latestProcessCPUTimeMachTicks,
                timebase: timebase
            ) {
            case let .success(milliseconds):
                return (milliseconds, "available")
            case let .failure(failure):
                return (nil, failure.rawValue)
            }
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
        let candidates: [(start: TimeInterval, end: TimeInterval)]
        if ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-performance-warmup"
        ) {
            guard let warmup = argumentValue(
                after: "--mwx-debug-scene-performance-warmup"
            ).flatMap(TimeInterval.init),
                  warmup.isFinite,
                  warmup >= 0,
                  latestEnd - warmup >= 1 else {
                NSLog(
                    "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-performance-warmup"
                )
                return
            }
            candidates = [(start: warmup, end: latestEnd)]
        } else {
            candidates = [
                (start: afterSnapshotDelay + 0.75, end: latestEnd),
                (start: 2.0, end: min(latestEnd, afterSnapshotDelay - 0.5)),
            ].filter { $0.end - $0.start >= 1 }
        }
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
                "MWX DEBUG SCENE: phase=performance targetFPS=%d warmupSeconds=%.3f elapsed=%.3f callbacks=%d submitted=%d completed=%d failed=%d submittedFPS=%.3f completedFPS=%.3f presented=%d presentStreams=%d presentIntervals=%d presentP50MS=%.3f presentP95MS=%.3f presentP99MS=%.3f presentMaxMS=%.3f presentOver1_5Budget=%d callbackP50MS=%.3f callbackP95MS=%.3f callbackMaxMS=%.3f callbackOver16=%d callbackOver33=%d discontinuities=%d droppedMS=%.3f maxRawFrameMS=%.3f drawableMissed=%d drawableWaitP95MS=%.3f drawableWaitMaxMS=%.3f preEncodeP95MS=%.3f preEncodeMaxMS=%.3f mainFrameP95MS=%.3f mainFrameMaxMS=%.3f cpuP50MS=%.3f cpuP95MS=%.3f cpuMaxMS=%.3f cpuOver16=%d cpuOver33=%d gpuSamples=%d gpuP50MS=%.3f gpuP95MS=%.3f gpuMaxMS=%.3f gpuOver16=%d gpuOver33=%d",
                targetFPS,
                window.start,
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
            // Per-frame view: nested stages that run several times per frame are
            // summed per frame, so these figures are additive against the
            // per-frame stages. Raw stageSummary percentiles are not.
            let frameStages =
                SceneFramePerformanceTelemetry.debugEvidence.frameStageSummary()
            let frameStageLine = frameStages.keys.sorted().map { name in
                let summary = frameStages[name] ?? (0, 0, 0)
                return "\(name)=p50:\(String(format: "%.3f", summary.0 * 1_000))ms p95:\(String(format: "%.3f", summary.1 * 1_000))ms n:\(summary.2)"
            }.joined(separator: " ")
            if !frameStageLine.isEmpty {
                NSLog(
                    "MWX DEBUG SCENE: phase=performance-stages-frames %@",
                    frameStageLine
                )
            }
            let processCPUTime = resources.processCPUTimeMilliseconds.map {
                String(format: "%.3f", $0)
            } ?? "unavailable"
            NSLog(
                "MWX DEBUG SCENE: phase=performance-resources samples=%d processSamples=%d processFootprintSampledPeakBytes=%llu processCPUTimeMS=%@ processCPUTimeStatus=%@ gpuAllocatedSampledPeakBytes=%llu renderTargetPoolSampledPeakBytes=%llu",
                resources.sampleCount,
                resources.processSampleCount,
                resources.processFootprintSampledPeakBytes,
                processCPUTime as NSString,
                resources.processCPUTimeStatus as NSString,
                resources.gpuAllocatedSampledPeakBytes,
                resources.renderTargetPoolSampledPeakBytes
            )
            // GPU operation census for this window. Counts of encoded work only:
            // pass splits and whole-texture copies that AS3 can aim at, then
            // judge by the GPU number above. Never a per-pass duration.
            let census = resources.gpuCensus
            func censusCount(_ metric: ScenePerformanceMetric) -> UInt64 {
                census[metric] ?? 0
            }
            NSLog(
                "MWX DEBUG SCENE: phase=performance-gpu frames=%d mainPassRenders=%llu depthRenders=%llu offscreenRenders=%llu resolvedMaterialRenders=%llu graphResourceSourceCaptures=%llu graphResourceInitializations=%llu offscreenEffectCaptures=%llu textureCopyPasses=%llu framebufferCaptures=%llu framebufferCaptureBytes=%llu graphOutputPublicationCopies=%llu textureCopyBytes=%llu unmeasuredCopyPasses=%llu",
                value.submitted,
                censusCount(.mainPassRenderPasses),
                censusCount(.depthRenderPasses),
                censusCount(.offscreenRenderPasses),
                censusCount(.resolvedMaterialRenderPasses),
                censusCount(.graphResourceSourceCaptures),
                censusCount(.graphResourceInitializations),
                censusCount(.offscreenEffectCaptures),
                censusCount(.textureCopyPasses),
                censusCount(.framebufferCaptures),
                censusCount(.framebufferCaptureBytes),
                censusCount(.graphOutputPublicationCopies),
                censusCount(.textureCopyBytes),
                censusCount(.unmeasuredCopyPasses)
            )
        }
    }

    private static func currentProcessResourceUsage() -> (
        Result<(
            footprintBytes: UInt64,
            cpuTimeMachTicks: UInt64
        ), DebugSceneProcessCPUTime.Failure>
    ) {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return .failure(.resourceUsageUnavailable) }
        return DebugSceneProcessCPUTime.combinedMachTicks(
            userMachTicks: usage.ri_user_time,
            systemMachTicks: usage.ri_system_time
        ).map { cpuTimeMachTicks in
            (
                footprintBytes: usage.ri_phys_footprint,
                cpuTimeMachTicks: cpuTimeMachTicks
            )
        }
    }
}
#endif
