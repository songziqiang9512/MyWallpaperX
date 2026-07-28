import Foundation

nonisolated struct SceneClippingMaskExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let providerLayerID: Int
    let blendMode: Int
    let profile: SceneClippingMaskProfile
}
