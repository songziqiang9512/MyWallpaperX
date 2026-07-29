import simd

nonisolated struct SceneFisheyeZeroDistortionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let center: SIMD2<Float>
    let size: Float
}
