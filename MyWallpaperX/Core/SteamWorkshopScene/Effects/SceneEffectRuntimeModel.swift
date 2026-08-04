import simd

struct SceneLayerEffectInputs {
    let flags: SceneEffectFlags
    let params0: SIMD4<Float>
    let params1: SIMD4<Float>
    let params2: SIMD4<Float>
    let params3: SIMD4<Float>
    let params4: SIMD4<Float>

    static let neutral = Self(
        flags: [], params0: .zero, params1: .zero, params2: .zero,
        params3: .zero, params4: .zero
    )
}

struct SceneBloomPlan {
    let threshold: Float
    let gamma: Float
    let radius: Float
    let intensity: Float
    let tint: SIMD3<Float>
}

struct SceneEffectRuntimePlan {
    let inputs: SceneLayerEffectInputs
    let gaussianBlur: SceneGaussianBlurPlan?
    let standardBlur: SceneStandardBlurPlan?
    let bloom: SceneBloomPlan?
    let gradientColor: SceneGradientColorPlan?
    let waterRippleNormal: SceneWaterRippleNormalPlan?
    let perspectiveOpacity: ScenePerspectiveOpacityPlan?
    let offscreenPassCount: Int
    let skipsUnsupportedComposite: Bool

    static let neutral = Self(
        inputs: .neutral,
        gaussianBlur: nil,
        standardBlur: nil,
        bloom: nil,
        gradientColor: nil,
        waterRippleNormal: nil,
        perspectiveOpacity: nil,
        offscreenPassCount: 0,
        skipsUnsupportedComposite: false
    )
}
