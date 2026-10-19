nonisolated struct SceneMdlPuppetAnimation {
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

    /// Authored clip metadata, not a replacement for current deformed bounds.
    struct Bounds: Equatable, Sendable {
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
    }

    /// Source coordinates describe already materialized samples, not another slice to apply.
    struct DerivedSource: Equatable, Sendable {
        let sourceRecordOrdinal: Int
        let firstFrame: Int
        let endFrame: Int
        let control: UInt32
        let rootSelector: Int32
    }

    let id: Int
    let name: String
    let mode: String
    /// Reader identity is independent of the exported ID used by animation layers.
    let recordOrdinal: Int?
    let rawMode: String
    let rawFlags: UInt32
    let derivedSource: DerivedSource?
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
    let bounds: Bounds?
    /// The reader validates this channel; consumers must not mistake it for TRS-only.
    let hasAuxiliaryScalarTrack: Bool

    init(
        id: Int,
        name: String,
        mode: String,
        framesPerSecond: Float,
        frameCount: Int,
        transformsByBone: [[Transform]],
        transformTrackStates: [TransformTrackState]? = nil,
        alphaByBone: [[Float]]? = nil,
        events: [Event] = [],
        bounds: Bounds? = nil,
        hasAuxiliaryScalarTrack: Bool = false,
        recordOrdinal: Int? = nil,
        rawMode: String? = nil,
        rawFlags: UInt32 = 0,
        derivedSource: DerivedSource? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.recordOrdinal = recordOrdinal
        self.rawMode = rawMode ?? mode
        self.rawFlags = rawFlags
        self.derivedSource = derivedSource
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
        self.transformsByBone = transformsByBone
        self.transformTrackStates = transformTrackStates
            ?? Array(repeating: .sampled, count: transformsByBone.count)
        self.alphaByBone = alphaByBone
        self.hasAlphaContribution = alphaByBone?.contains { $0.contains { $0 != 1 } } == true
        self.events = events
        self.bounds = bounds
        self.hasAuxiliaryScalarTrack = hasAuxiliaryScalarTrack
    }

    nonisolated var durationSeconds: Float {
        Float(frameCount) / framesPerSecond
    }
}

struct SceneMdlPuppetAnimationSet {
    let boneCount: Int
    let animations: [SceneMdlPuppetAnimation]
    /// Full ordered source records; only `animations` is addressable by exported ID.
    let records: [SceneMdlPuppetAnimation]

    init(boneCount: Int, animations: [SceneMdlPuppetAnimation],
         records: [SceneMdlPuppetAnimation]? = nil) {
        self.boneCount = boneCount
        self.animations = animations
        self.records = records ?? animations
    }
}
