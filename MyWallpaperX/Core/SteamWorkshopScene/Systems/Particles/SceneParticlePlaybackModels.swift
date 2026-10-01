import Foundation

nonisolated enum SceneParticlePlaybackIntent: Int32, Equatable, Sendable {
    case playing = 0, paused = 1, stopped = 2
}

nonisolated struct SceneParticlePlaybackSnapshot: Equatable, Sendable {
    var intent: SceneParticlePlaybackIntent = .playing
    var revision: UInt64 = 0
}

nonisolated enum SceneParticlePlaybackAction: Int32, Equatable, Sendable {
    case play = 0, pause = 1, stop = 2
}

nonisolated struct SceneParticlePlaybackTransition: Equatable, Sendable {
    let layerID: Int
    let action: SceneParticlePlaybackAction
    let revision: UInt64
}

nonisolated struct SceneParticlePlaybackObservation: Equatable, Sendable {
    let liveAny: Bool
    let emissionPending: Bool
    let rearmHasWork: Bool
    let intent: SceneParticlePlaybackIntent
    let revision: UInt64
}
