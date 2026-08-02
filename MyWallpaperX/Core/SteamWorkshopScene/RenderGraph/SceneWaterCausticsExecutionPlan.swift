import simd

nonisolated struct SceneWaterCausticsExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let blendMode: Int
    let brightness: Float
    let glow: Float
    let scale: Float
    let speed: Float
    let timeOffset: Float
    let distortion: Float
    let chromatic: Float
    let blur: Float
    let colorStart: SIMD3<Float>
    let colorEnd: SIMD3<Float>
    let maskTexturePath: String?
    let patternTexturePath: String
    let glowTexturePath: String
    let noiseTexturePath: String
    let offsetTexturePath: String
}
