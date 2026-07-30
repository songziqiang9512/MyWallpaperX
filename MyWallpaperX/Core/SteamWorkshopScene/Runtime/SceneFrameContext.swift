import CoreGraphics
import Foundation

nonisolated struct SceneFrameTiming: Equatable, Sendable {
    let frameIndex: UInt64
    let hostTime: TimeInterval
    let sceneTime: TimeInterval
    let frameTime: TimeInterval
    let wallDate: Date
}

nonisolated struct SceneFrameContext: Equatable, Sendable {
    let timing: SceneFrameTiming
    let dynamicValues: SceneDynamicSnapshot
    let canvasSize: CGSize
    let screenSize: CGSize
    let pointer: SceneSurfacePointerState
    let cameraParallaxPosition: SIMD2<Float>
    /// host-shared 频谱输入。无消费者或采集不可用时为稳定零输入。
    let audioSpectrum: SceneAudioSpectrumSnapshot

    nonisolated var pointerCurrent: SIMD2<Float> { pointer.current }
    nonisolated var pointerPrevious: SIMD2<Float> { pointer.previous }
    nonisolated var frameIndex: UInt64 { timing.frameIndex }
    nonisolated var hostTime: TimeInterval { timing.hostTime }
    nonisolated var sceneTime: TimeInterval { timing.sceneTime }
    nonisolated var frameTime: TimeInterval { timing.frameTime }
    nonisolated var wallDate: Date { timing.wallDate }
}

nonisolated struct SceneClock {
    private var startHostTime: TimeInterval
    private var lastHostTime: TimeInterval
    private var nextFrameIndex: UInt64 = 0
    private var pausedHostTime: TimeInterval?
    private var pausedSceneTime: TimeInterval = 0
    private var anchorsFirstResumedFrame = false

    nonisolated var isPaused: Bool { pausedHostTime != nil }

    nonisolated init(hostTime: TimeInterval) {
        startHostTime = hostTime
        lastHostTime = hostTime
    }

    nonisolated mutating func reset(hostTime: TimeInterval) {
        startHostTime = hostTime
        lastHostTime = hostTime
        nextFrameIndex = 0
        pausedHostTime = nil
        pausedSceneTime = 0
        anchorsFirstResumedFrame = false
    }

    nonisolated mutating func pause(hostTime: TimeInterval) {
        guard pausedHostTime == nil else { return }
        let monotonicHostTime = max(hostTime, lastHostTime)
        pausedHostTime = monotonicHostTime
        pausedSceneTime = monotonicHostTime - startHostTime
        lastHostTime = monotonicHostTime
    }

    nonisolated mutating func resume(hostTime: TimeInterval) {
        guard let pausedHostTime else { return }
        let monotonicHostTime = max(hostTime, pausedHostTime)
        startHostTime += monotonicHostTime - pausedHostTime
        lastHostTime = monotonicHostTime
        self.pausedHostTime = nil
        anchorsFirstResumedFrame = true
    }

    nonisolated func currentSceneTime(hostTime: TimeInterval) -> TimeInterval {
        if pausedHostTime != nil {
            return pausedSceneTime
        }
        if anchorsFirstResumedFrame {
            return lastHostTime - startHostTime
        }
        return max(hostTime, lastHostTime) - startHostTime
    }

    nonisolated mutating func advance(
        hostTime: TimeInterval,
        wallDate: Date
    ) -> SceneFrameTiming {
        if pausedHostTime != nil {
            return SceneFrameTiming(
                frameIndex: nextFrameIndex,
                hostTime: max(hostTime, lastHostTime),
                sceneTime: pausedSceneTime,
                frameTime: 0,
                wallDate: wallDate
            )
        }

        let monotonicHostTime = max(hostTime, lastHostTime)
        if anchorsFirstResumedFrame {
            startHostTime += monotonicHostTime - lastHostTime
        }
        let frameTime = nextFrameIndex == 0 || anchorsFirstResumedFrame
            ? 0
            : monotonicHostTime - lastHostTime
        let timing = SceneFrameTiming(
            frameIndex: nextFrameIndex,
            hostTime: monotonicHostTime,
            sceneTime: monotonicHostTime - startHostTime,
            frameTime: frameTime,
            wallDate: wallDate
        )
        lastHostTime = monotonicHostTime
        anchorsFirstResumedFrame = false
        nextFrameIndex &+= 1
        return timing
    }
}
