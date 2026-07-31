/// Strict native plan for a verified texture-animation SceneScript profile.
nonisolated struct SceneTextureAnimationPlaybackPlan: Equatable, Sendable {
    let layerID: Int
    let sourceSHA256: String
    let initialDelay: Float
    let minimumDelay: Float
    let maximumDelay: Float
}
