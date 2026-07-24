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

    nonisolated init(hostTime: TimeInterval) {
        startHostTime = hostTime
        lastHostTime = hostTime
    }

    nonisolated mutating func reset(hostTime: TimeInterval) {
        startHostTime = hostTime
        lastHostTime = hostTime
        nextFrameIndex = 0
    }

    nonisolated mutating func advance(
        hostTime: TimeInterval,
        wallDate: Date
    ) -> SceneFrameTiming {
        let monotonicHostTime = max(hostTime, lastHostTime)
        let frameTime = nextFrameIndex == 0 ? 0 : monotonicHostTime - lastHostTime
        let timing = SceneFrameTiming(
            frameIndex: nextFrameIndex,
            hostTime: monotonicHostTime,
            sceneTime: monotonicHostTime - startHostTime,
            frameTime: frameTime,
            wallDate: wallDate
        )
        lastHostTime = monotonicHostTime
        nextFrameIndex &+= 1
        return timing
    }
}
