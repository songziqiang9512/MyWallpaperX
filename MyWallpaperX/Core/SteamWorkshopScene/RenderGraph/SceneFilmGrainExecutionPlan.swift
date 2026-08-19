import Foundation

nonisolated struct SceneFilmGrainExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let scale: Float
    let strength: Float
    let exponent: Float
    let blendMode: Int
    let greyscale: Bool
    let noiseTexturePath: String
}
