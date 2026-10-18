#if DEBUG
import Foundation
import AudioToolbox

private enum DebugSceneAudioSpectrumFixtureState {
    nonisolated static let queue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.debug-scene-audio-spectrum"
    )
    nonisolated static let observationQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.debug-scene-audio-observation"
    )
    static let captureService: SystemAudioSpectrumService = {
        let service = SystemAudioSpectrumService(barCount: 16, onSceneLevels: {
            left, right, left32, right32, left64, right64, _ in
            SceneAudioSpectrumInbox.shared.publish(left: left, right: right,
                left32: left32, right32: right32, left64: left64, right64: right64)
        })
        service.debugEnableRecoveryTesting() // Suppress real device creation only.
        service.setConsumers(overlayEnabled: false, webEnabled: false, sceneEnabled: true)
        return service
    }()
    nonisolated static let isSilence = ProcessInfo.processInfo.arguments.contains(
        "--mwx-debug-scene-audio-silence-fixture"
    )
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
        let silence = DebugSceneAudioSpectrumFixtureState.isSilence
        guard silence || arguments.contains("--mwx-debug-scene-audio-spectrum-fixture") else {
            return
        }
        var toneFrequency: Float?
        if !silence, arguments.contains("--mwx-debug-scene-audio-tone-hz") {
            guard let raw = argumentValue(after: "--mwx-debug-scene-audio-tone-hz"),
                  let frequency = Float(raw), frequency.isFinite,
                  frequency > 0, frequency < DebugSceneAudioSpectrumFixtureState.sampleRate / 2 else {
                NSLog("MWX DEBUG SCENE AUDIO: rejected invalid tone frequency")
                return
            }
            toneFrequency = frequency
        }
        NSLog("MWX DEBUG SCENE AUDIO: mode=%@ toneHz=%.3f source=capture-service callbackFrames=128",
              silence ? "silence" : "pcm", toneFrequency ?? 0)
        scheduleAudioSpectrumFixtureFrame(
            0,
            toneFrequency: toneFrequency,
            previousLeft: nil,
            startUptime: DispatchTime.now().uptimeNanoseconds
        )
    }

    private static func scheduleAudioSpectrumFixtureFrame(
        _ frame: Int,
        toneFrequency: Float?,
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
            let state = DebugSceneAudioSpectrumFixtureState.self
            DebugAudioSpectrumPCMFixture.feed(state.captureService, frame: frame,
                                               toneFrequency: toneFrequency, silence: state.isSilence)
            let levels = SceneAudioSpectrumInbox.shared.latest()
            if frame.isMultiple(of: 30) {
                let upperHalfStart = levels.left.count / 2
                let shapeDelta = meanAbsoluteDelta(
                    levels.left,
                    previousLeft
                )
                let upperShapeDelta = meanAbsoluteDelta(
                    levels.left,
                    previousLeft,
                    from: upperHalfStart
                )
                NSLog(
                    "MWX DEBUG SCENE AUDIO: frame=%d leftRange=%.3f...%.3f "
                        + "shapeDelta=%.4f upperPeak=%.3f upperShapeDelta=%.4f "
                        + "rightPeak=%.3f left16First=%.6f left64LowSum=%.6f",
                    frame,
                    levels.left.min() ?? 0,
                    levels.left.max() ?? 0,
                    shapeDelta,
                    levels.left.dropFirst(upperHalfStart).max() ?? 0,
                    upperShapeDelta,
                    levels.right64.max() ?? 0,
                    levels.left.first ?? 0,
                    levels.left64.prefix(3).reduce(0, +)
                )
            }
            Task { @MainActor in
                scheduleAudioSpectrumFixtureFrame(
                    frame + 1,
                    toneFrequency: toneFrequency,
                    previousLeft: levels.left,
                    startUptime: startUptime
                )
            }
        }
    }

    private nonisolated static func meanAbsoluteDelta(
        _ current: [Float],
        _ previous: [Float]?,
        from startIndex: Int = 0
    ) -> Float {
        guard let previous else { return 0 }
        let count = min(current.count, previous.count)
        let lowerBound = min(max(0, startIndex), count)
        guard lowerBound < count else { return 0 }
        var total: Float = 0
        for index in lowerBound ..< count {
            total += abs(current[index] - previous[index])
        }
        return total / Float(count - lowerBound)
    }

    /// 确定性 PCM 只负责提供可复现的宽频输入；它不直接构造频谱。隔离样本因此会
    /// 经过实际采集服务的小块回调、连续PCM交接、FFT、频带、响应与包络，再由
    /// shared inbox 交给作者 shader。两个宽频能量团以不同连续相位缓慢穿过频段，
    /// 让验证能区分“真实形态变化”和“冻结频谱只被 Scroll 平移”；所有变化仍来自
    /// PCM，零输入模式保持严格静止。

}
#endif
