import Foundation

nonisolated struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let shaderProfile: SceneBlendShaderProfile
    let blendMode: Int
    let multiply: Float
    let assetTexturePath: String
    let userPropertyKey: String?

    nonisolated var executedUserPropertyKeys: Set<String> {
        Set([userPropertyKey].compactMap { $0 })
    }
}
