import Foundation

/// Immutable texture-animation state published to SceneScript before owner
/// callbacks.  It contains control metadata only; the prepared TEX and its
/// provider stay with the existing resource/render owners.
nonisolated struct SceneTextureAnimationSnapshot: Equatable, Sendable {
    let layerID: Int
    let frameCount: Int
    let duration: TimeInterval
    let rate: Double
    let currentFrame: Double
    let isPlaying: Bool
    let sharedRate: Double
    let sharedCurrentFrame: Double
    let sharedIsPlaying: Bool
}

/// Typed command emitted by one SceneScript owner and committed only after
/// every surface submits.  The existing playback runtime applies it for the
/// following frame.
nonisolated struct SceneTextureAnimationCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case play
        case pause
        case stop
        case setFrame(Double)
        case setRate(Double)
        case join
    }

    let layerID: Int
    let action: Action
}
