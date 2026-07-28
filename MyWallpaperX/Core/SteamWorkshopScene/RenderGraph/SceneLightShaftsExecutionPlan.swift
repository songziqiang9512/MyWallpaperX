import simd

nonisolated struct SceneLightShaftsExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    let feather: SIMD2<Float>
    let scale: SIMD2<Float>
    let smoothness: Float
    let speed: Float
    let intensity: Float
    let exponent: Float
    let noiseTexturePath: String
    let gradientTexturePath: String
}
