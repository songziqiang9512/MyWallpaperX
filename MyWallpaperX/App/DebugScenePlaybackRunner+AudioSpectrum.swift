#if DEBUG
import Foundation

private enum DebugSceneAudioSpectrumFixtureState {
    static let queue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.debug-scene-audio-spectrum"
    )
    static let observationQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.debug-scene-audio-observation"
    )
    static let analyzer = SystemAudioSceneSpectrumAnalyzer()
    nonisolated static let sampleRate: Float = 48_000
    nonisolated static let publicationRate: Float = 30
    nonisolated static let samplesPerFrame = Int(sampleRate / publicationRate)
}

extension DebugScenePlaybackRunner {
    static func scheduleAudioSpectrumLivePropertyObservations() {
        scheduleAudioSpectrumObservation(
            phase: "before-live-property",
            startDelay: 1.25
        )
        scheduleAudioSpectrumObservation(
            phase: "after-live-property",
            startDelay: 2.75
        )
    }

    private nonisolated static func scheduleAudioSpectrumObservation(
        phase: String,
        startDelay: TimeInterval
    ) {
        DebugSceneAudioSpectrumFixtureState.observationQueue.asyncAfter(
            deadline: .now() + startDelay
        ) {
            collectAudioSpectrumObservation(
                phase: phase,
                peaks: [],
                generations: []
            )
        }
    }

    private nonisolated static func collectAudioSpectrumObservation(
        phase: String,
        peaks: [Float],
        generations: [UInt64]
    ) {
        let snapshot = SceneAudioSpectrumInbox.shared.latest()
        let nextPeaks = peaks + [audioSpectrumPeak(snapshot)]
        let nextGenerations = generations + [snapshot.generation]
        guard nextPeaks.count < 12 else {
            let demand = SceneAudioSpectrumInbox.shared.captureDemand
            let meanPeak = nextPeaks.reduce(0, +) / Float(nextPeaks.count)
            NSLog(
                "MWX DEBUG SCENE AUDIO: phase=%@ samples=%d nonSilent=%d "
                    + "meanPeak=%.6f maxPeak=%.6f generation=%llu...%llu "
                    + "scopeEpoch=%llu includeCurrentProcess=%@",
                phase,
                nextPeaks.count,
                nextPeaks.filter { $0 > 0 }.count,
                meanPeak,
                nextPeaks.max() ?? 0,
                nextGenerations.first ?? 0,
                nextGenerations.last ?? 0,
                demand.scopeEpoch,
                demand.includesCurrentProcessOutput ? "true" : "false"
            )
            return
        }
        DebugSceneAudioSpectrumFixtureState.observationQueue.asyncAfter(
            deadline: .now() + 0.05
        ) {
            collectAudioSpectrumObservation(
                phase: phase,
                peaks: nextPeaks,
                generations: nextGenerations
            )
        }
    }

    private nonisolated static func audioSpectrumPeak(
        _ snapshot: SceneAudioSpectrumSnapshot
    ) -> Float {
        [
            snapshot.left.max() ?? 0,
            snapshot.right.max() ?? 0,
            snapshot.left32.max() ?? 0,
            snapshot.right32.max() ?? 0,
            snapshot.left64.max() ?? 0,
            snapshot.right64.max() ?? 0,
        ].max() ?? 0
    }

    static func scheduleRequestedAudioSpectrumFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--mwx-debug-scene-audio-silence-fixture") {
            SceneAudioSpectrumInbox.shared.clearSnapshot()
            NSLog("MWX DEBUG SCENE AUDIO: mode=silence")
            return
        }
        guard arguments.contains("--mwx-debug-scene-audio-spectrum-fixture") else {
            return
        }
        NSLog("MWX DEBUG SCENE AUDIO: mode=pcm")
        scheduleAudioSpectrumFixtureFrame(
            0,
            previousLeft: nil,
            startUptime: DispatchTime.now().uptimeNanoseconds
        )
    }

    private static func scheduleAudioSpectrumFixtureFrame(
        _ frame: Int,
        previousLeft: [Float]?,
        startUptime: UInt64
    ) {
        let interval = 1 / Double(DebugSceneAudioSpectrumFixtureState.publicationRate)
        let elapsed = Double(frame) * interval
        guard elapsed < requestedDuration - interval else { return }
        let intervalNanoseconds = UInt64((interval * 1_000_000_000).rounded())
        let targetUptime = startUptime
            + UInt64(frame) * intervalNanoseconds
        DebugSceneAudioSpectrumFixtureState.queue.asyncAfter(
            deadline: DispatchTime(uptimeNanoseconds: targetUptime)
        ) {
            guard let analyzer = DebugSceneAudioSpectrumFixtureState.analyzer else {
                SceneAudioSpectrumInbox.shared.clearSnapshot()
                return
            }
            let levels = analyzer.analyze(
                signedChannels: [
                    fixturePCM(frame: frame, channelPhase: 0),
                    fixturePCM(frame: frame, channelPhase: 0.19),
                ],
                sampleRate: DebugSceneAudioSpectrumFixtureState.sampleRate
            )
            SceneAudioSpectrumInbox.shared.publish(
                left: levels.left,
                right: levels.right,
                left32: levels.left32,
                right32: levels.right32,
                left64: levels.left64,
                right64: levels.right64
            )
            if frame.isMultiple(of: 30) {
                let shapeDelta = meanAbsoluteDelta(
                    levels.left,
                    previousLeft
                )
                NSLog(
                    "MWX DEBUG SCENE AUDIO: frame=%d leftRange=%.3f...%.3f "
                        + "shapeDelta=%.4f rightPeak=%.3f",
                    frame,
                    levels.left.min() ?? 0,
                    levels.left.max() ?? 0,
                    shapeDelta,
                    levels.right64.max() ?? 0
                )
            }
            Task { @MainActor in
                scheduleAudioSpectrumFixtureFrame(
                    frame + 1,
                    previousLeft: levels.left,
                    startUptime: startUptime
                )
            }
        }
    }

    private nonisolated static func meanAbsoluteDelta(
        _ current: [Float],
        _ previous: [Float]?
    ) -> Float {
        guard let previous else { return 0 }
        let count = min(current.count, previous.count)
        guard count > 0 else { return 0 }
        var total: Float = 0
        for index in 0 ..< count {
            total += abs(current[index] - previous[index])
        }
        return total / Float(count)
    }

    /// 确定性 PCM 只负责提供可复现的宽频输入；它不直接构造频谱。隔离样本因此会
    /// 经过与系统音频相同的滚动窗、FFT、官方 64-band identity、响应与包络，再由
    /// shared inbox 交给作者 shader。两个宽频能量团以不同连续相位缓慢穿过频段，
    /// 让验证能区分“真实形态变化”和“冻结频谱只被 Scroll 平移”；所有变化仍来自
    /// PCM，零输入模式保持严格静止。
    private nonisolated static func fixturePCM(
        frame: Int,
        channelPhase: Float
    ) -> [Float] {
        let state = DebugSceneAudioSpectrumFixtureState.self
        let startSample = frame * state.samplesPerFrame
        let elapsed = Float(frame) / state.publicationRate
        let overallEnvelope = 0.68
            + 0.12 * sin((elapsed * 0.27 + channelPhase * 0.07) * 2 * .pi)
            + 0.06 * sin((elapsed * 0.61 + channelPhase * 0.13) * 2 * .pi)
        let toneCount = 24
        return (0 ..< state.samplesPerFrame).map { localSample in
            let sample = startSample + localSample
            let time = Float(sample) / state.sampleRate
            var mixed: Float = 0
            for index in 0 ..< toneCount {
                let position = (Float(index) + 0.5) / Float(toneCount)
                // 二次分布在 sqrt-like 官方 band identity 上近似均匀落点；这里只
                // 生成测试 PCM，不参与产品频带映射。
                let frequency = 55 + 14_445 * position * position
                let firstCenter = 0.23
                    + 0.14 * sin((elapsed * 0.19 + channelPhase * 0.09) * 2 * .pi)
                let secondCenter = 0.71
                    + 0.18 * sin((elapsed * 0.13 + 0.31
                        - channelPhase * 0.06) * 2 * .pi)
                let firstDistance = (position - firstCenter) / 0.14
                let secondDistance = (position - secondCenter) / 0.18
                let firstCluster = exp(-firstDistance * firstDistance)
                let secondCluster = exp(-secondDistance * secondDistance)
                let firstPulse = 0.5 + 0.5 * sin(
                    (elapsed * 0.43 + position * 0.72 + channelPhase * 0.16) * 2 * .pi
                )
                let secondPulse = 0.5 + 0.5 * sin(
                    (elapsed * 0.31 - position * 0.54 + 0.27
                        + channelPhase * 0.21) * 2 * .pi
                )
                let spectralEnvelope = min(0.95, max(0.002,
                    firstCluster * (0.12 + 0.78 * firstPulse * firstPulse)
                        + secondCluster * (0.09 + 0.64 * secondPulse * secondPulse)
                ))
                let phase = Float(index) * 0.371 + channelPhase * 2 * .pi
                mixed += sin(2 * .pi * frequency * time + phase) * spectralEnvelope
            }
            return max(-0.95, min(0.95, mixed * overallEnvelope * 0.062))
        }
    }
}
#endif
