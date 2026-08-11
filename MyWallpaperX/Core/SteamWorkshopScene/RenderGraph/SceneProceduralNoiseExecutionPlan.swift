import simd

nonisolated struct SceneProceduralNoiseExecutionPlan {
    enum Variant: Int, Sendable {
        case colorPerlinRGB
        case uvCurl
        case uvWorleyMix
        case legacyWorleyColor
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let variant: Variant
    let scale: SIMD2<Float>
    let offset: SIMD2<Float>
    let magnitude: SIMD2<Float>
    let thresholds: SIMD2<Float>
    let colorsMin: SIMD3<Float>
    let colorsMax: SIMD3<Float>
    let opacity: Float
    let exponent: Float
    let fractals: Int
    let fractalScale: Float
    let fractalInfluence: Float
    let gradient: Float
    let seed: Float
    let animationSpeed: Float
    let scrollDirection: Float
    let scrollSpeed: Float
    let thresholdOffset: Float
    let shiftAmount: Float
    let depthFade: Float
    let perspective01: SIMD4<Float>
    let perspective23: SIMD4<Float>
    let dependencyProviderLayerID: Int?
    let dependencySlotIndex: Int?
}
