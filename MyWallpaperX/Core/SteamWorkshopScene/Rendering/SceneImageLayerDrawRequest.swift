import Metal
import simd

struct SceneImageLayerMasks {
    static let empty = SceneImageLayerMasks()

    func blocksLayerSourcePassthrough(
        forVisibleEffects effects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> Bool {
        let visibleEffects = effects.filter { $0.visible != false }
        guard !visibleEffects.isEmpty else { return false }
        let hasCoverageMutatingPulse = visibleEffects.contains { effect in
            Self.normalized(effect.file) == "effects/pulse/effect.json"
                && !Self.pulsePreservesSourceCoverage(effect)
        }
        let hasAuthoredStandardBlurMask = visibleEffects.contains {
            Self.standardBlurHasAuthoredMask($0)
        }
        let hasEffectOutsideLocalDisplacementContract = visibleEffects.contains { effect in
            Self.isAuthoredLocalDisplacementDefinition(effect.file)
                && !Self.effectUsesOnlyLocalDisplacementInputs(effect)
        }
        return hasCoverageMutatingPulse
            || hasAuthoredStandardBlurMask
            || hasEffectOutsideLocalDisplacementContract
    }

    private static func standardBlurHasAuthoredMask(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        // Preserve the prior masked-Blur passthrough boundary after removing
        // its renderer-specific texture registry. This reads authored resource
        // shape only; MaterialProgram remains the sole resource/output owner.
        guard normalized(effect.file) == "effects/blur/effect.json",
              effect.passes.count == 4,
              let combine = effect.passes.first(where: { $0.passIndex == 3 }),
              combine.textureSlots.indices.contains(1),
              let mask = combine.textureSlots[1] else { return false }
        return !normalized(mask).isEmpty
    }

    private static func pulsePreservesSourceCoverage(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        // Stock Pulse only preserves source coverage when its alpha branch is off.
        guard normalized(effect.file) == "effects/pulse/effect.json",
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              (2 ... 3).contains(pass.textureSlots.count),
              pass.textureSlots[0] == nil,
              pass.textureSlots[1].map(Self.normalized) == "util/noise",
              pass.texturePaths.map(Self.normalized)
                == pass.textureSlots.compactMap({ $0 }).map(Self.normalized),
              let combos = normalizedPulseCombos(pass.combos),
              (0 ... 3).contains(combos["AUDIOPROCESSING", default: 0]),
              (0 ... SceneBlendModeShaderSource.maximumMode).contains(
                  combos["BLENDMODE", default: 9]
              ),
              [0, 1].contains(combos["PULSECOLOR", default: 1]),
              combos["PULSEALPHA", default: 0] == 0 else {
            return false
        }
        return true
    }

    private static func effectUsesOnlyLocalDisplacementInputs(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        // A proven local-displacement mask belongs to the skipped effect and
        // cannot independently change source coverage. Unknown topology,
        // combos, or resource purpose must still block source passthrough.
        guard normalized(effect.file) == "effects/waterwaves/effect.json",
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              (1 ... 2).contains(pass.textureSlots.count),
              pass.textureSlots[0] == nil,
              pass.textureSlots.count == 1 || pass.textureSlots[1] != nil,
              pass.texturePaths.map(Self.normalized)
                == pass.textureSlots.compactMap({ $0 }).map(Self.normalized),
              normalizedLocalDisplacementCombos(pass.combos) != nil else {
            return false
        }
        return true
    }

    private static func normalizedLocalDisplacementCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        let allowed = Set(["TIMEOFFSET", "PERSPECTIVE", "DUALWAVES"])
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey),
                  result[normalizedKey] == nil,
                  value == 0 else {
                return nil
            }
            result[normalizedKey] = value
        }
        return result
    }

    private static func isAuthoredLocalDisplacementDefinition(
        _ rawPath: String
    ) -> Bool {
        // Preserve the old stock/relocated resource-provenance boundary after
        // removing its renderer-specific asset family. Relocated definitions
        // remain unproven for source-coverage passthrough; this predicate never
        // selects an execution algorithm or output owner.
        let path = normalized(rawPath)
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return components.count >= 3
            && components.joined(separator: "/") == path
            && components.first == "effects"
            && components[components.count - 2] == "waterwaves"
            && components.last == "effect.json"
            && components.dropFirst().dropLast(2).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func normalizedPulseCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        let allowed = Set([
            "AUDIOPROCESSING", "BLENDMODE", "PULSEALPHA", "PULSECOLOR",
        ])
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey), result[normalizedKey] == nil else {
                return nil
            }
            result[normalizedKey] = value
        }
        return result
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
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

    var namedReference: SceneNamedTextureReference {
        .init(providerLayerID: providerLayerID, variant: variant)
    }

    var reservedMaterialResource: SceneFrameTextureResource? {
        SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: namedReference,
            frameEpoch: frameEpoch,
            texture: texture
        )
    }

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
    var blocksStaticLayerSourcePassthrough: Bool = false
    var dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0)
    var audioSpectrum: SceneAudioSpectrumSnapshot = .silent
    var authoredShaderFrameInputs: SceneAuthoredShaderFrameInputs? = nil

    func resolvedBaseTextureSample() -> SceneBaseImageTextureSample? {
        guard let baseTextureCandidate else {
            return .init(textureFrame: textureFrame, sampling: .linearClamp)
        }
        guard layer.contentKind == "image"
            || (layer.contentKind == "solid"
                && baseTextureCandidate.identity
                    == .provider(.mediaThumbnailCurrent)) else { return nil }
        return SceneBaseImageTextureCandidateResolver.sample(
            candidate: baseTextureCandidate,
            sourceTexture: texture
        )
    }

    func resolvedBaseTextureFrame() -> SceneTextureUVTransform? {
        resolvedBaseTextureSample()?.textureFrame
    }
}
