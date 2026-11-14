import Foundation

nonisolated struct ScenePuppetAnimationIdentity: Hashable, Sendable {
    enum Instance: Hashable, Sendable {
        case authored(index: Int, id: Int?)
        case created(epoch: UInt64, ordinal: UInt32)
    }

    let layerID: Int
    let instance: Instance

    init(layerID: Int, animationLayerIndex: Int, animationLayerID: Int?) {
        self.layerID = layerID
        instance = .authored(index: animationLayerIndex, id: animationLayerID)
    }

    init(layerID: Int, creationEpoch: UInt64, creationOrdinal: UInt32) {
        self.layerID = layerID
        instance = .created(epoch: creationEpoch, ordinal: creationOrdinal)
    }

    var animationLayerIndex: Int? {
        if case let .authored(index, _) = instance { return index }
        return nil
    }

    var animationLayerID: Int? {
        if case let .authored(_, id) = instance { return id }
        return nil
    }
}

nonisolated struct ScenePuppetSingleAnimationSourceMetadata: Equatable, Sendable {
    let animationID: Int
    let name: String
    let framesPerSecond: Double
    let frameCount: Int
    var duration: Double { Double(frameCount) / framesPerSecond }
}

nonisolated enum ScenePuppetAnimationEndedFailure: String, Error, Equatable, Sendable {
    case unsupportedMode
    case multipleLoopsCrossed
    case sequenceOverflow
}

/// One natural forward crossing, issued once by the launch playback owner.
/// Identity plus sequence stays stable when a cadence is published again.
nonisolated struct ScenePuppetAnimationEventOccurrence: Equatable, Sendable {
    let identity: ScenePuppetAnimationIdentity
    let sequence: UInt64
    let name: String
    let frame: Int
}

nonisolated enum ScenePuppetAnimationEventFailure: String, Error, Equatable, Sendable {
    case unsupportedMode
    case invalidEvent
    case nonFinitePhase
    case multipleLoopsCrossed
    case eventBudgetExceeded
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
    /// The existing rate/blend control domain, shared by typed value inputs.
    static func acceptsScalarControl(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && Float(value).isFinite
    }

    enum Action: Equatable, Sendable {
        case play
        case pause
        case stop
        case setFrame(Double)
        case setRate(Double)
        case setBlend(Double)
        case setVisible(Bool)
        case createSingle(animationID: Int)
    }

    let identity: ScenePuppetAnimationIdentity
    let action: Action
    let callbackEpoch: UInt64
    let ordinal: UInt32
}
