import CoreGraphics
import Foundation

nonisolated struct SceneScriptMaterialFunctionMutation: Equatable, Hashable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let functionName: String
}

nonisolated struct SceneFrameTiming: Equatable, Sendable {
    let frameIndex: UInt64
    let hostTime: TimeInterval
    let sceneTime: TimeInterval
    let rawFrameTime: TimeInterval
    let simulationFrameTime: TimeInterval
    let droppedFrameTime: TimeInterval
    let wallDate: Date

    nonisolated var frameTime: TimeInterval { rawFrameTime }
    nonisolated var isDiscontinuous: Bool { droppedFrameTime > 0 }
}

nonisolated struct SceneFrameContext: Equatable, Sendable {
    let timing: SceneFrameTiming
    let dynamicValues: SceneDynamicSnapshot
    let canvasSize: CGSize
    let screenSize: CGSize
    let pointer: SceneSurfacePointerState
    let cameraParallaxPosition: SIMD2<Float>
    let cameraParallaxMouseInfluence: Float
    let allowsMouseParallax: Bool
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    /// host-shared 频谱输入。无消费者或采集不可用时为稳定零输入。
    let audioSpectrum: SceneAudioSpectrumSnapshot

    nonisolated init(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        canvasSize: CGSize,
        screenSize: CGSize,
        pointer: SceneSurfacePointerState,
        cameraParallaxPosition: SIMD2<Float>,
        cameraParallaxMouseInfluence: Float = 1,
        allowsMouseParallax: Bool = true,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = [],
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) {
        self.timing = timing
        self.dynamicValues = dynamicValues
        self.canvasSize = canvasSize
        self.screenSize = screenSize
        self.pointer = pointer
        self.cameraParallaxPosition = cameraParallaxPosition
        self.cameraParallaxMouseInfluence = cameraParallaxMouseInfluence
        self.allowsMouseParallax = allowsMouseParallax
        self.materialFunctionMutations = materialFunctionMutations
        self.audioSpectrum = audioSpectrum
    }

    nonisolated var pointerCurrent: SIMD2<Float> { pointer.current }
    nonisolated var pointerPrevious: SIMD2<Float> { pointer.previous }
    nonisolated var frameIndex: UInt64 { timing.frameIndex }
    nonisolated var hostTime: TimeInterval { timing.hostTime }
    nonisolated var sceneTime: TimeInterval { timing.sceneTime }
    nonisolated var frameTime: TimeInterval { timing.frameTime }
    nonisolated var rawFrameTime: TimeInterval { timing.rawFrameTime }
    nonisolated var simulationFrameTime: TimeInterval { timing.simulationFrameTime }
    nonisolated var droppedFrameTime: TimeInterval { timing.droppedFrameTime }
    nonisolated var isDiscontinuous: Bool { timing.isDiscontinuous }
    nonisolated var wallDate: Date { timing.wallDate }
}

nonisolated struct SceneClock {
    nonisolated static let maximumSimulationFrameTime: TimeInterval = 0.25

    /// Explicit clock snapshot for restoring an unconsumed timing operation.
    /// Once the host consumes a simulation cadence, surface/GPU failures do
    /// not restore this state or replay that cadence's callbacks and animation.
    nonisolated struct State: Equatable, Sendable {
        fileprivate let startHostTime: TimeInterval
        fileprivate let lastHostTime: TimeInterval
        fileprivate let nextFrameIndex: UInt64
        fileprivate let pausedHostTime: TimeInterval?
        fileprivate let pausedSceneTime: TimeInterval
        fileprivate let anchorsFirstResumedFrame: Bool
        fileprivate let rate: Double
        fileprivate let lastFrameSceneTime: TimeInterval

        fileprivate init(
            startHostTime: TimeInterval,
            lastHostTime: TimeInterval,
            nextFrameIndex: UInt64,
            pausedHostTime: TimeInterval?,
            pausedSceneTime: TimeInterval,
            anchorsFirstResumedFrame: Bool,
            rate: Double,
            lastFrameSceneTime: TimeInterval
        ) {
            self.startHostTime = startHostTime
            self.lastHostTime = lastHostTime
            self.nextFrameIndex = nextFrameIndex
            self.pausedHostTime = pausedHostTime
            self.pausedSceneTime = pausedSceneTime
            self.anchorsFirstResumedFrame = anchorsFirstResumedFrame
            self.rate = rate
            self.lastFrameSceneTime = lastFrameSceneTime
        }
    }

    private var startHostTime: TimeInterval
    private var lastHostTime: TimeInterval
    private var nextFrameIndex: UInt64 = 0
    private var pausedHostTime: TimeInterval?
    private var pausedSceneTime: TimeInterval = 0
    private var anchorsFirstResumedFrame = false
    private var rate = 1.0
    private var lastFrameSceneTime: TimeInterval = 0

    nonisolated var isPaused: Bool { pausedHostTime != nil }

    nonisolated func snapshot() -> State {
        State(
            startHostTime: startHostTime,
            lastHostTime: lastHostTime,
            nextFrameIndex: nextFrameIndex,
            pausedHostTime: pausedHostTime,
            pausedSceneTime: pausedSceneTime,
            anchorsFirstResumedFrame: anchorsFirstResumedFrame,
            rate: rate,
            lastFrameSceneTime: lastFrameSceneTime
        )
    }

    nonisolated mutating func restore(_ state: State) {
        startHostTime = state.startHostTime
        lastHostTime = state.lastHostTime
        nextFrameIndex = state.nextFrameIndex
        pausedHostTime = state.pausedHostTime
        pausedSceneTime = state.pausedSceneTime
        anchorsFirstResumedFrame = state.anchorsFirstResumedFrame
        rate = state.rate
        lastFrameSceneTime = state.lastFrameSceneTime
    }

    nonisolated init(hostTime: TimeInterval) {
        let normalizedHostTime = hostTime.isFinite ? hostTime : 0
        startHostTime = normalizedHostTime
        lastHostTime = normalizedHostTime
    }

    nonisolated mutating func reset(hostTime: TimeInterval) {
        let normalizedHostTime = hostTime.isFinite ? hostTime : 0
        startHostTime = normalizedHostTime
        lastHostTime = normalizedHostTime
        nextFrameIndex = 0
        pausedHostTime = nil
        pausedSceneTime = 0
        anchorsFirstResumedFrame = false
        lastFrameSceneTime = 0
    }

    nonisolated mutating func setPlaybackRate(_ newRate: Double, hostTime: TimeInterval) {
        guard newRate != rate else { return }
        let anchor = pausedHostTime ?? (anchorsFirstResumedFrame ? lastHostTime : monotonicHostTime(hostTime))
        startHostTime = anchor - currentSceneTime(hostTime: anchor) / newRate
        rate = newRate
    }

    nonisolated mutating func pause(hostTime: TimeInterval) {
        guard pausedHostTime == nil else { return }
        let monotonicHostTime = self.monotonicHostTime(hostTime)
        pausedHostTime = monotonicHostTime
        pausedSceneTime = (monotonicHostTime - startHostTime) * rate
        lastHostTime = monotonicHostTime
    }

    nonisolated mutating func resume(hostTime: TimeInterval) {
        guard let pausedHostTime else { return }
        let monotonicHostTime = hostTime.isFinite
            ? max(hostTime, pausedHostTime)
            : pausedHostTime
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
            return (lastHostTime - startHostTime) * rate
        }
        return (monotonicHostTime(hostTime) - startHostTime) * rate
    }

    nonisolated mutating func advance(
        hostTime: TimeInterval,
        wallDate: Date
    ) -> SceneFrameTiming {
        if pausedHostTime != nil {
            return SceneFrameTiming(
                frameIndex: nextFrameIndex,
                hostTime: monotonicHostTime(hostTime),
                sceneTime: pausedSceneTime,
                rawFrameTime: 0,
                simulationFrameTime: 0,
                droppedFrameTime: 0,
                wallDate: wallDate
            )
        }

        let monotonicHostTime = self.monotonicHostTime(hostTime)
        if anchorsFirstResumedFrame {
            startHostTime += monotonicHostTime - lastHostTime
        }
        let sceneTime = (monotonicHostTime - startHostTime) * rate
        let rawFrameTime = nextFrameIndex == 0 || anchorsFirstResumedFrame
            ? 0
            : max(0, sceneTime - lastFrameSceneTime)
        let simulationFrameTime = min(
            rawFrameTime,
            Self.maximumSimulationFrameTime
        )
        let timing = SceneFrameTiming(
            frameIndex: nextFrameIndex,
            hostTime: monotonicHostTime,
            sceneTime: sceneTime,
            rawFrameTime: rawFrameTime,
            simulationFrameTime: simulationFrameTime,
            droppedFrameTime: rawFrameTime - simulationFrameTime,
            wallDate: wallDate
        )
        lastHostTime = monotonicHostTime
        lastFrameSceneTime = sceneTime
        anchorsFirstResumedFrame = false
        nextFrameIndex &+= 1
        return timing
    }

    nonisolated private func monotonicHostTime(_ hostTime: TimeInterval) -> TimeInterval {
        guard hostTime.isFinite else { return lastHostTime }
        return max(hostTime, lastHostTime)
    }
}
