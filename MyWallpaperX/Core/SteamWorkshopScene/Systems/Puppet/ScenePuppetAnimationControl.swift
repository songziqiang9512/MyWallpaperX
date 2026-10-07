import Foundation

/// Authored order is part of identity; an optional editor ID alone is not unique.
nonisolated struct ScenePuppetAnimationIdentity: Hashable, Sendable {
    let layerID: Int
    let animationLayerIndex: Int
    let animationLayerID: Int?
}

nonisolated enum ScenePuppetAnimationEndedFailure: String, Error, Equatable, Sendable {
    case unsupportedMode
    case multipleLoopsCrossed
    case sequenceOverflow
}

/// A committed mirror for SceneScript. It has no independent playback clock.
nonisolated struct ScenePuppetAnimationSnapshot: Equatable, Sendable {
    let identity: ScenePuppetAnimationIdentity
    let animationID: Int
    let name: String
    let framesPerSecond: Double
    let frameCount: Int
    let duration: Double
    let currentFrame: Double
    let isPlaying: Bool
    let rate: Double
    let blend: Double
    let visible: Bool
    let endedSequence: UInt64
    let supportsEndedCallbacks: Bool
    let endedFailure: ScenePuppetAnimationEndedFailure?
}

nonisolated struct ScenePuppetAnimationCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case play
        case pause
        case stop
        case setFrame(Double)
        case setRate(Double)
        case setBlend(Double)
        case setVisible(Bool)
    }

    let identity: ScenePuppetAnimationIdentity
    let action: Action
    let callbackEpoch: UInt64
    let ordinal: UInt32
}
