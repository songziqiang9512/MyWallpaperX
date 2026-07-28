import simd

nonisolated struct SceneShineExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let firstHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity

    let threshold: Float
    let noiseAmount: Float
    let noiseScale: Float
    let noiseSpeed: Float
    let maskTexturePath: String?
    let noiseTexturePath: String

    let edgeCount: Int
    let sampleCount: Int
    let direction: Float
    let rotationSpeed: Float
    let rayLength: Float
    let rayIntensity: Float
    let rayColor: SIMD3<Float>

    let kernelRadius: Int
    let blurScaleX: SIMD2<Float>
    let blurScaleY: SIMD2<Float>
    let blendMode: Int
}
