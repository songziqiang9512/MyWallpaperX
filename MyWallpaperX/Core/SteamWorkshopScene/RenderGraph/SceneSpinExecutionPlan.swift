import simd

nonisolated struct SceneSpinExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let center: SIMD2<Float>
    let size: Float
    let feather: Float
    let speed: Float
    let ratio: Float
    let angle: Float
    let phase: Float
}
