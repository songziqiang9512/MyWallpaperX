import Metal
import simd

struct SceneImageLayerMasks {
    let iris: MTLTexture?
    let opacity: MTLTexture?
    let water: MTLTexture?
    let waterUVScale: SIMD2<Float>
    let foliage: MTLTexture?
    let foliageUVScale: SIMD2<Float>
    let waterRippleNormal: MTLTexture?
    let shakeEffects: [String: SceneShakeEffectTextures]
    let filmGrainEffects: [String: SceneFilmGrainEffectTextures]
    let waterFlowEffects: [String: SceneWaterFlowEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let opacityEffects: [String: SceneOpacityEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let tintEffects: [String: SceneTintEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let xRay: SceneXRayEffectTextures?

    var authoredEffectResourcesOnly: SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: water,
            waterUVScale: waterUVScale,
            foliage: foliage,
            foliageUVScale: foliageUVScale,
            waterRippleNormal: waterRippleNormal,
            shakeEffects: shakeEffects,
            filmGrainEffects: filmGrainEffects,
            waterFlowEffects: waterFlowEffects,
            waterWavesEffects: waterWavesEffects,
            opacityEffects: opacityEffects,
            pulseEffects: pulseEffects,
            tintEffects: tintEffects,
            godraysEffects: godraysEffects,
            xRay: xRay
        )
    }

    static let empty = SceneImageLayerMasks(
        iris: nil,
        opacity: nil,
        water: nil,
        waterUVScale: SIMD2(repeating: 1),
        foliage: nil,
        foliageUVScale: SIMD2(repeating: 1),
        waterRippleNormal: nil,
        shakeEffects: [:],
        filmGrainEffects: [:],
        waterFlowEffects: [:],
        waterWavesEffects: [:],
        opacityEffects: [:],
        pulseEffects: [:],
        tintEffects: [:],
        godraysEffects: [:],
        xRay: nil
    )

    static func xRayOnly(_ xRay: SceneXRayEffectTextures?) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: nil,
            waterUVScale: SIMD2(repeating: 1),
            foliage: nil,
            foliageUVScale: SIMD2(repeating: 1),
            waterRippleNormal: nil,
            shakeEffects: [:],
            filmGrainEffects: [:],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            opacityEffects: [:],
            pulseEffects: [:],
            tintEffects: [:],
            godraysEffects: [:],
            xRay: xRay
        )
    }
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let cursorIsInside: Bool
    let primaryButtonIsDown: Bool
    let tint: SIMD3<Float>

    init(
        time: Float,
        alpha: Float,
        cursorUV: SIMD2<Float>,
        cursorIsInside: Bool = true,
        primaryButtonIsDown: Bool = false,
        tint: SIMD3<Float> = SIMD3(repeating: 1)
    ) {
        self.time = time
        self.alpha = alpha
        self.cursorUV = cursorUV
        self.cursorIsInside = cursorIsInside
        self.primaryButtonIsDown = primaryButtonIsDown
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
    var audioSpectrum: SceneAudioSpectrumSnapshot = .silent
    var localContrastStrength: Float? = nil
    var authoredShaderFrameInputs: SceneAuthoredShaderFrameInputs? = nil

    var resolvedOffscreenSize: CGSize? {
        let desired = offscreenSize ?? CGSize(
            width: CGFloat(texture.width),
            height: CGFloat(texture.height)
        )
        return authoredEffectChain?.authoredShaderOffscreenSize(for: desired) ?? offscreenSize
    }
}
