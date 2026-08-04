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
    let foliageSwayEffects: [String: SceneFoliageSwayEffectTextures]
    let waterRippleEffects: [String: SceneWaterRippleEffectTextures]
    let depthParallaxEffects: [String: SceneDepthParallaxEffectTextures]
    let blendEffects: [String: SceneBlendEffectTextures]
    let shakeEffects: [String: SceneShakeEffectTextures]
    let filmGrainEffects: [String: SceneFilmGrainEffectTextures]
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let waterFlowEffects: [String: SceneWaterFlowEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let waterCausticsEffects: [String: SceneWaterCausticsEffectTextures]
    let cursorRippleEffects: [String: SceneCursorRippleEffectTextures]
    let opacityEffects: [String: SceneOpacityEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let tintEffects: [String: SceneTintEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let shineEffects: [String: SceneShineEffectTextures]
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
            foliageSwayEffects: foliageSwayEffects,
            waterRippleEffects: waterRippleEffects,
            depthParallaxEffects: depthParallaxEffects,
            blendEffects: blendEffects,
            shakeEffects: shakeEffects,
            filmGrainEffects: filmGrainEffects,
            standardBlurEffects: standardBlurEffects,
            waterFlowEffects: waterFlowEffects,
            waterWavesEffects: waterWavesEffects,
            waterCausticsEffects: waterCausticsEffects,
            cursorRippleEffects: cursorRippleEffects,
            opacityEffects: opacityEffects,
            pulseEffects: pulseEffects,
            tintEffects: tintEffects,
            godraysEffects: godraysEffects,
            shineEffects: shineEffects,
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
        foliageSwayEffects: [:],
        waterRippleEffects: [:],
        depthParallaxEffects: [:],
        blendEffects: [:],
        shakeEffects: [:],
        filmGrainEffects: [:],
        standardBlurEffects: [:],
        waterFlowEffects: [:],
        waterWavesEffects: [:],
        waterCausticsEffects: [:],
        cursorRippleEffects: [:],
        opacityEffects: [:],
        pulseEffects: [:],
        tintEffects: [:],
        godraysEffects: [:],
        shineEffects: [:],
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
            foliageSwayEffects: [:],
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: [:],
            shakeEffects: [:],
            filmGrainEffects: [:],
            standardBlurEffects: [:],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            waterCausticsEffects: [:],
            cursorRippleEffects: [:],
            opacityEffects: [:],
            pulseEffects: [:],
            tintEffects: [:],
            godraysEffects: [:],
            shineEffects: [:],
            xRay: xRay
        )
    }
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let previousCursorUV: SIMD2<Float>
    let cursorIsInside: Bool
    let previousCursorIsInside: Bool
    let primaryButtonIsDown: Bool
    let frameTime: Float
    let tint: SIMD3<Float>

    init(
        time: Float,
        alpha: Float,
        cursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>? = nil,
        cursorIsInside: Bool = true,
        previousCursorIsInside: Bool? = nil,
        primaryButtonIsDown: Bool = false,
        frameTime: Float = 0,
        tint: SIMD3<Float> = SIMD3(repeating: 1)
    ) {
        self.time = time
        self.alpha = alpha
        self.cursorUV = cursorUV
        self.previousCursorUV = previousCursorUV ?? cursorUV
        self.cursorIsInside = cursorIsInside
        self.previousCursorIsInside = previousCursorIsInside ?? cursorIsInside
        self.primaryButtonIsDown = primaryButtonIsDown
        self.frameTime = frameTime
        self.tint = tint
    }
}

struct SceneDependencyEffectInput {
    let texture: MTLTexture
    let blendMode: Int
    let slotIndex: Int

    init(texture: MTLTexture, blendMode: Int, slotIndex: Int = 1) {
        self.texture = texture
        self.blendMode = blendMode
        self.slotIndex = slotIndex
    }
}

struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    var baseTextureCandidate: SceneTextureCandidate? = nil
    let masks: SceneImageLayerMasks
    let textureFrame: SceneTextureUVTransform
    let mvp: simd_float4x4
    let uniforms: SceneImageLayerUniformValues
    let offscreenTexturePool: SceneOffscreenTexturePool?
    var resolvedMaterialFrameTargetPlan: SceneResolvedMaterialFrameTargetPlan? = nil
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

    func resolvedBaseTextureFrame() -> SceneTextureUVTransform? {
        guard let baseTextureCandidate else {
            return textureFrame
        }
        guard layer.contentKind == "image" else { return nil }
        return SceneBaseImageTextureCandidateResolver.textureFrame(
            candidate: baseTextureCandidate,
            sourceTexture: texture
        )
    }
}
