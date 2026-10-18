struct SceneMdlPuppetAnimation {
    enum TransformTrackState: UInt32 {
        case sampled = 0
        case referenceCandidate = 1
    }

    struct Event: Equatable, Sendable {
        let name: String
        let frame: Int
        /// Preserves the recorded field without assigning it a time unit.
        let recordedTime: Float
    }

    struct Transform: Equatable, Sendable {
        let translation: SIMD3<Float>
        let rotation: SIMD3<Float>
        let scale: SIMD3<Float>
    }

    let id: Int
    let name: String
    let mode: String
    let framesPerSecond: Float
    let frameCount: Int
    let transformsByBone: [[Transform]]
    /// Original dense-track state; reference candidates still retain every TRS sample.
    let transformTrackStates: [TransformTrackState]
    /// Exported per-bone alpha samples use the same frame schedule as TRS.
    /// Absence means opaque; exported values are consumed directly.
    let alphaByBone: [[Float]]?
    /// Immutable classification; the evaluator still validates track shape and values.
    let hasAlphaContribution: Bool
    let events: [Event]

    init(
        id: Int,
        name: String,
        mode: String,
        framesPerSecond: Float,
        frameCount: Int,
        transformsByBone: [[Transform]],
        transformTrackStates: [TransformTrackState]? = nil,
        alphaByBone: [[Float]]? = nil,
        events: [Event] = []
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
        self.transformsByBone = transformsByBone
        self.transformTrackStates = transformTrackStates
            ?? Array(repeating: .sampled, count: transformsByBone.count)
        self.alphaByBone = alphaByBone
        self.hasAlphaContribution = alphaByBone?.contains { $0.contains { $0 != 1 } } == true
        self.events = events
    }

    nonisolated var durationSeconds: Float {
        Float(frameCount) / framesPerSecond
    }
}

struct SceneMdlPuppetAnimationSet {
    let boneCount: Int
    let animations: [SceneMdlPuppetAnimation]
}
