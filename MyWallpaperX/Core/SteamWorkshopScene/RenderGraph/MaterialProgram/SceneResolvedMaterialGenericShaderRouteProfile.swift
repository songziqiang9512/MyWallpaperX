/// Product authority for one source-proven shader capability. These profiles
/// are structural host facts; they never contain effect, sample, path, or hash
/// identities.
nonisolated enum SceneGenericShaderRouteState: String {
    case preferGeneric = "prefer-generic"
    case genericOnly = "generic-only"
    case observeOnly = "observe-only"
    case disableGeneric = "disable-generic"

    static func resolve(
        _ rawValue: String?,
        defaultState: SceneGenericShaderRouteState
    ) -> SceneGenericShaderRouteState? {
        guard let rawValue else { return defaultState }
        guard let requested = Self(rawValue: rawValue) else { return nil }
        switch requested {
        case .preferGeneric:
            // A migrated profile cannot silently regain a second product
            // owner. `disable-generic` is its explicit rollback switch.
            return defaultState == .genericOnly ? .genericOnly : .preferGeneric
        case .genericOnly:
            // Do not let an environment toggle broaden generic-only
            // authority to profiles that have not passed their owner gate.
            return defaultState == .genericOnly ? .genericOnly : nil
        case .observeOnly, .disableGeneric:
            return requested
        }
    }
}

nonisolated enum SceneGenericShaderFallbackOwner: String {
    case boundedFrontend = "bounded-frontend"
    case programFirstIncumbent = "program-first-incumbent"
    case none
}

nonisolated enum SceneGenericShaderCapabilityProfile: String {
    case ordinaryShader = "ordinary-shader"
    case providerBackedScalarColorInterpolation =
        "provider-backed-scalar-color-interpolation"
    case sourceProvenScalarColorInterpolation =
        "source-proven-scalar-color-interpolation"
    case sourceProvenOpaqueScalarOutput =
        "source-proven-opaque-scalar-output"
    case sourceProvenStraightAlphaR8Signal =
        "source-proven-straight-alpha-r8-signal"
    case sourceProvenIndependentPremultipliedOutput =
        "source-proven-independent-premultiplied-output"
    case sourceProvenGraphTargetPassthrough =
        "source-proven-graph-target-passthrough"
    case sourceProvenNormalizedSampleSum =
        "source-proven-normalized-sample-sum"
    case sourceProvenGraphInputAlphaWeightedSampleAverage =
        "source-proven-graph-input-alpha-weighted-sample-average"
    case sourceProvenUnitPreviousBlurredComposite =
        "source-proven-unit-previous-blurred-composite"
    case sourceProvenUnitPreviousBlurredCompositeUnowned =
        "source-proven-unit-previous-blurred-composite-unowned"
    case sourceProvenGraphInputAlphaAttenuation =
        "source-proven-graph-input-alpha-attenuation"
    case sourceProvenGraphInputColorBlend =
        "source-proven-graph-input-color-blend"
    case sourceProvenGraphInputConditionalStraightUnion =
        "source-proven-graph-input-conditional-straight-union"
    case sourceProvenGraphInputSingleSamplerAlphaMutation =
        "source-proven-graph-input-single-sampler-alpha-mutation"
    case sourceProvenGraphInputSameSlotChannelReconstruction =
        "source-proven-graph-input-same-slot-channel-reconstruction"
    case sourceProvenGraphInputAuxiliaryRGBBlendAlphaPreserving =
        "source-proven-graph-input-auxiliary-rgb-blend-alpha-preserving"
    case sourceProvenGraphInputStraightAlpha =
        "source-proven-graph-input-straight-alpha"
    case sourceProvenGraphInputAudioStageUniformStraightAlphaNoAuxiliary =
        "source-proven-graph-input-audio-stage-uniform-straight-alpha-no-auxiliary"
    case sourceProvenGraphInputStraightAlphaPreserving =
        "source-proven-graph-input-straight-alpha-preserving"
    case sourceProvenGraphInputStageUniformStraightAlphaPreserving =
        "source-proven-graph-input-stage-uniform-straight-alpha-preserving"
    case sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary =
        "source-proven-graph-input-stage-uniform-straight-alpha-preserving-no-auxiliary"
    case sourceProvenGraphInputStageUniformPassthrough =
        "source-proven-graph-input-stage-uniform-passthrough"

    init(
        colorTransfer: SceneShaderColorTransfer,
        alphaAttenuationSourceSlot: Int?,
        colorBlendSourceSlot: Int?,
        conditionalStraightUnionSourceSlot: Int?,
        singleSamplerAlphaMutationSourceSlot: Int?,
        sameSlotChannelReconstructionSourceSlot: Int?,
        auxiliaryRGBMixSourceSlot: Int?,
        normalizedSampleSumSourceSlot: Int?,
        alphaWeightedSampleAverageSourceSlot: Int?,
        unitCompositeBlurredSlot: Int?,
        unitCompositePreviousSlot: Int?,
        unitCompositeSourceBlurredSlot: Int? = nil,
        unitCompositeSourcePreviousSlot: Int? = nil,
        hasExternalProviderTexture: Bool,
        producesScalarRedOutput: Bool,
        isSourceIndependentPremultipliedOutput: Bool,
        graphTextureSlots: Set<Int>,
        graphInputTextureSlots: Set<Int>,
        r8TextureSlots: Set<Int>,
        hasDefaultedOpacityMaskSampler: Bool,
        hasOnlyGraphInputSampler: Bool = false,
        hasStageScopedUniformBindings: Bool,
        hasStereoAudioSpectrumArrays: Bool,
        hasLocalizedMutableFragmentVarying: Bool
    ) {
        if colorTransfer == .premultipliedAlpha,
           isSourceIndependentPremultipliedOutput,
           !hasExternalProviderTexture,
           !producesScalarRedOutput,
           graphTextureSlots.isEmpty,
           graphInputTextureSlots.isEmpty {
            self = .sourceProvenIndependentPremultipliedOutput
        } else if let colorBlendSourceSlot,
           !hasExternalProviderTexture,
           !producesScalarRedOutput,
           graphInputTextureSlots.contains(colorBlendSourceSlot) {
            self = .sourceProvenGraphInputColorBlend
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  conditionalStraightUnionSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputConditionalStraightUnion
        } else if colorTransfer == .opaque, producesScalarRedOutput {
            self = .sourceProvenOpaqueScalarOutput
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !producesScalarRedOutput,
                  r8TextureSlots.contains(where: { $0 != sourceSlot }) {
            self = .sourceProvenStraightAlphaR8Signal
        } else if case let .passthrough(sourceSlot) = colorTransfer,
                  normalizedSampleSumSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput {
            self = .sourceProvenNormalizedSampleSum
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  alphaWeightedSampleAverageSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputAlphaWeightedSampleAverage
        } else if case let .straightAlphaPreserving(transferBlurred) = colorTransfer,
                  let sourceBlurred = unitCompositeSourceBlurredSlot
                    ?? unitCompositeBlurredSlot,
                  let sourcePrevious = unitCompositeSourcePreviousSlot
                    ?? unitCompositePreviousSlot,
                  transferBlurred == sourceBlurred,
                  sourceBlurred != sourcePrevious {
            let ownerEligible = unitCompositeBlurredSlot == sourceBlurred
                && unitCompositePreviousSlot == sourcePrevious
                && !hasExternalProviderTexture
                && !producesScalarRedOutput
                && graphTextureSlots == Set([sourceBlurred])
                && graphInputTextureSlots == Set([sourceBlurred, sourcePrevious])
            self = ownerEligible
                ? .sourceProvenUnitPreviousBlurredComposite
                : .sourceProvenUnitPreviousBlurredCompositeUnowned
        } else if case let .passthrough(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphTargetPassthrough
        } else if case let .passthrough(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot),
                  hasStageScopedUniformBindings {
            self = .sourceProvenGraphInputStageUniformPassthrough
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  alphaAttenuationSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputAlphaAttenuation
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  singleSamplerAlphaMutationSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputSingleSamplerAlphaMutation
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler,
                  hasStageScopedUniformBindings,
                  hasStereoAudioSpectrumArrays,
                  hasLocalizedMutableFragmentVarying {
            self = .sourceProvenGraphInputAudioStageUniformStraightAlphaNoAuxiliary
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputStraightAlpha
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  sameSlotChannelReconstructionSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputSameSlotChannelReconstruction
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  auxiliaryRGBMixSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputAuxiliaryRGBBlendAlphaPreserving
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler,
                  hasStageScopedUniformBindings {
            self = .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasDefaultedOpacityMaskSampler,
                  hasStageScopedUniformBindings {
            self = .sourceProvenGraphInputStageUniformStraightAlphaPreserving
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputStraightAlphaPreserving
        } else if case .interpolatedColor = colorTransfer,
                  hasExternalProviderTexture {
            self = .providerBackedScalarColorInterpolation
        } else if case .interpolatedColor = colorTransfer {
            self = .sourceProvenScalarColorInterpolation
        } else {
            self = .ordinaryShader
        }
    }

    var defaultRouteState: SceneGenericShaderRouteState {
        switch self {
        case .ordinaryShader,
             .providerBackedScalarColorInterpolation,
             .sourceProvenGraphInputAlphaWeightedSampleAverage,
             .sourceProvenGraphInputStraightAlpha,
             .sourceProvenGraphInputStraightAlphaPreserving:
            .preferGeneric
        case .sourceProvenScalarColorInterpolation,
             .sourceProvenOpaqueScalarOutput,
             .sourceProvenStraightAlphaR8Signal,
             .sourceProvenIndependentPremultipliedOutput,
             .sourceProvenGraphTargetPassthrough,
             .sourceProvenNormalizedSampleSum,
             .sourceProvenUnitPreviousBlurredComposite,
             .sourceProvenGraphInputAlphaAttenuation,
             .sourceProvenGraphInputColorBlend,
             .sourceProvenGraphInputConditionalStraightUnion,
             .sourceProvenGraphInputSingleSamplerAlphaMutation,
             .sourceProvenGraphInputSameSlotChannelReconstruction,
             .sourceProvenGraphInputAuxiliaryRGBBlendAlphaPreserving,
             .sourceProvenGraphInputAudioStageUniformStraightAlphaNoAuxiliary,
             .sourceProvenGraphInputStageUniformStraightAlphaPreserving,
             .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary,
             .sourceProvenGraphInputStageUniformPassthrough:
            .genericOnly
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .observeOnly
        }
    }

    /// Shared profiles normally roll back through the bounded frontend. The
    /// unit previous/blurred composite has no visually safe secondary owner:
    /// disabling its generic owner must reject that effect back to the safe
    /// previous-current boundary. A source-proven composite that lacks the
    /// surrounding graph owner token remains quarantined behind the verified
    /// incumbent.
    var validatedRollbackOwner: SceneGenericShaderFallbackOwner {
        switch self {
        case .sourceProvenUnitPreviousBlurredComposite:
            .none
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .programFirstIncumbent
        default:
            .boundedFrontend
        }
    }
}
