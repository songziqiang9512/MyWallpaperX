import Metal
import simd

struct SceneImageLayerMasks {
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

    static let empty = SceneImageLayerMasks(
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

    func hasCoverageOrOpacityTexture(
        forVisibleEffects effects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> Bool {
        let effectIDs = Set(
            effects.lazy.filter { $0.visible != false }.map(\.id)
        )
        guard !effectIDs.isEmpty else { return false }
        func hasValue<Value>(
            _ values: [String: Value],
            _ predicate: (Value) -> Bool
        ) -> Bool {
            effectIDs.contains { id in
                values[id].map(predicate) ?? false
            }
        }
        return hasValue(opacityEffects) { $0.mask != nil }
            || hasValue(tintEffects) { $0.mask != nil }
            || hasValue(pulseEffects) { $0.mask != nil }
            || hasValue(foliageSwayEffects) { $0.maskBinding != nil }
            || hasValue(shakeEffects) { $0.maskBinding != nil }
            || hasValue(waterRippleEffects) { $0.maskBinding != nil }
            || hasValue(standardBlurEffects) { $0.maskCandidate != nil }
            || hasValue(waterWavesEffects) { $0.mask != nil }
            || hasValue(waterCausticsEffects) { $0.mask != nil }
            || hasValue(cursorRippleEffects) { $0.mask != nil }
            || hasValue(godraysEffects) { $0.mask != nil }
            || hasValue(shineEffects) { $0.mask != nil }
            || (xRay.map {
                effectIDs.contains($0.effectID) && $0.opacityMask != nil
            } ?? false)
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
    let consumerLayerID: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let slot: SceneEffectPassSlot
    let blendMode: Int
    let frameEpoch: UInt64
    let texture: MTLTexture

    var slotIndex: Int { slot.slotIndex }

    init(
        consumerLayerID: Int,
        providerLayerID: Int,
        variant: SceneNamedTextureReference.Variant,
        slot: SceneEffectPassSlot,
        blendMode: Int,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) {
        self.consumerLayerID = consumerLayerID
        self.providerLayerID = providerLayerID
        self.variant = variant
        self.slot = slot
        self.blendMode = blendMode
        self.frameEpoch = frameEpoch
        self.texture = texture
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
    var requiresDependencyEffect: Bool = false
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
