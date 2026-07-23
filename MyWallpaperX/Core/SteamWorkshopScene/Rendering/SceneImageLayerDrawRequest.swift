import Metal
import simd

struct SceneImageLayerMasks {
    let iris: MTLTexture?
    let opacity: MTLTexture?
    let water: MTLTexture?
    let foliage: MTLTexture?
    let foliageUVScale: SIMD2<Float>
    let waterRippleNormal: MTLTexture?
    let shakeEffects: [String: SceneShakeEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]

    var authoredEffectResourcesOnly: SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: nil,
            foliage: nil,
            foliageUVScale: SIMD2(repeating: 1),
            waterRippleNormal: nil,
            shakeEffects: shakeEffects,
            waterWavesEffects: waterWavesEffects
        )
    }

    static let empty = SceneImageLayerMasks(
        iris: nil,
        opacity: nil,
        water: nil,
        foliage: nil,
        foliageUVScale: SIMD2(repeating: 1),
        waterRippleNormal: nil,
        shakeEffects: [:],
        waterWavesEffects: [:]
    )
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let tint: SIMD3<Float>

    init(
        time: Float,
        alpha: Float,
        cursorUV: SIMD2<Float>,
        tint: SIMD3<Float> = SIMD3(repeating: 1)
    ) {
        self.time = time
        self.alpha = alpha
        self.cursorUV = cursorUV
        self.tint = tint
    }
}

struct SceneDependencyEffectInput {
    let texture: MTLTexture
    let blendMode: Int
}

struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    let masks: SceneImageLayerMasks
    let textureFrame: SceneTextureUVTransform
    let mvp: simd_float4x4
    let uniforms: SceneImageLayerUniformValues
    let offscreenTexturePool: SceneOffscreenTexturePool?
    let offscreenSize: CGSize?
    let requiresSourceCopy: Bool
    let finalCompositeAlpha: Float?
    let dependencyEffect: SceneDependencyEffectInput?
    let authoredEffectPlan: SceneAuthoredEffectExecutionPlan?
    let blocksLegacyGaussianBlur: Bool
    var authoredEffectChain: SceneAuthoredEffectExecutionChain? = nil
    var dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0)
    var localContrastStrength: Float? = nil
}
