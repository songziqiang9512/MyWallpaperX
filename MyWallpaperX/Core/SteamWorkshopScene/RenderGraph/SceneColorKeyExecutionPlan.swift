import simd

nonisolated struct SceneColorKeyExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let keyAlpha: Float
    let fuzziness: Float
    let tolerance: Float
    let keyColor: SIMD3<Float>
    let invert: Bool
    let flatten: Bool
}
