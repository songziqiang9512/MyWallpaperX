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
    case sourceProvenRedGreenUnormScalarSplat =
        "source-proven-red-green-unorm-scalar-splat"
    case sourceProvenPreservedRGBAStateTransform =
        "source-proven-preserved-rgba-state-transform"
    case sourceProvenIndependentPremultipliedOutput =
        "source-proven-independent-premultiplied-output"
    case sourceProvenGraphInputIndependentSignalProducer =
        "source-proven-graph-input-independent-signal-producer"
    case sourceProvenGraphTargetIndependentSignalAccumulator =
        "source-proven-graph-target-independent-signal-accumulator"
    case sourceProvenGraphTargetIndependentSignalUNormAccumulator =
        "source-proven-graph-target-independent-signal-unorm-accumulator"
    case sourceProvenGraphInputIndependentSignalCompositing =
        "source-proven-graph-input-independent-signal-compositing"
    case sourceProvenGraphTargetPassthrough =
        "source-proven-graph-target-passthrough"
    case sourceProvenGraphInputSameSlotColorReplacement =
        "source-proven-graph-input-same-slot-color-replacement"
    case sourceProvenNormalizedSampleSum =
        "source-proven-normalized-sample-sum"
    case sourceProvenGraphTargetOpaqueLoopSampleAverage =
        "source-proven-graph-target-opaque-loop-sample-average"
    case sourceProvenGraphTargetOpaqueStaticSampleAverage =
        "source-proven-graph-target-opaque-static-sample-average"
    case sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage =
        "source-proven-graph-target-opaque-alpha-weighted-loop-average"
    case sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB =
        "source-proven-graph-input-conditional-opaque-alpha-weighted-rgb"
    case sourceProvenGraphInputAlphaWeightedSampleAverage =
        "source-proven-graph-input-alpha-weighted-sample-average"
    case sourceProvenGraphInputPreservedAlphaRGBFilter =
        "source-proven-graph-input-preserved-alpha-rgb-filter"
    case sourceProvenGraphInputTypedDataRGBFilter =
        "source-proven-graph-input-typed-data-rgb-filter"
    case sourceProvenGraphInputSameAlphaReconstructedRGBDataFilter =
        "source-proven-graph-input-same-alpha-reconstructed-rgb-data-filter"
    case sourceProvenUnitPreviousBlurredComposite =
        "source-proven-unit-previous-blurred-composite"
    case sourceProvenUnitPreviousBlurredCompositeUnowned =
        "source-proven-unit-previous-blurred-composite-unowned"
    case sourceProvenGraphInputAlphaAttenuation =
        "source-proven-graph-input-alpha-attenuation"
    case sourceProvenGraphInputColorBlend =
        "source-proven-graph-input-color-blend"
    case sourceProvenGraphInputSpatialWeightedColorBlend =
        "source-proven-graph-input-spatial-weighted-color-blend"
    case providerBackedGraphInputSpatialWeightedColorBlend =
        "provider-backed-graph-input-spatial-weighted-color-blend"
    case sourceProvenGraphInputOverlayAlphaBlend =
        "source-proven-graph-input-overlay-alpha-blend"
    case sourceProvenGraphInputConditionalStraightUnion =
        "source-proven-graph-input-conditional-straight-union"
    case sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha =
        "source-proven-graph-input-conditional-generated-rgb-preserved-alpha"
    case sourceProvenGraphInputSingleSamplerAlphaMutation =
        "source-proven-graph-input-single-sampler-alpha-mutation"
    case sourceProvenGraphInputStraightRGBScalarAlpha =
        "source-proven-graph-input-straight-rgb-scalar-alpha"
    case sourceProvenGraphInputRGBBlendScalarAlpha =
        "source-proven-graph-input-rgb-blend-scalar-alpha"
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
    case sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary =
        "source-proven-graph-input-stage-uniform-straight-alpha-preserving-static-auxiliary"
    case sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary =
        "source-proven-graph-input-stage-uniform-straight-alpha-preserving-no-auxiliary"
    case sourceProvenGraphInputStageUniformPassthrough =
        "source-proven-graph-input-stage-uniform-passthrough"

    init(
        fragmentSource: String = "",
        colorTransfer: SceneShaderColorTransfer,
        alphaAttenuationSourceSlot: Int?,
        colorBlendSourceSlot: Int?,
        overlayAlphaBlendSourceSlot: Int? = nil,
        overlayAlphaBlendAuxiliarySlot: Int? = nil,
        conditionalStraightUnionSourceSlot: Int?,
        singleSamplerAlphaMutationSourceSlot: Int?,
        sameSlotChannelReconstructionSourceSlot: Int?,
        auxiliaryRGBMixSourceSlot: Int?,
        normalizedSampleSumSourceSlot: Int?,
        independentSignalAccumulatorSourceSlot: Int? = nil,
        independentSignalUNormAccumulatorSourceSlot: Int? = nil,
        alphaWeightedSampleAverageSourceSlot: Int?,
        preservedAlphaRGBFilterSourceSlot: Int?,
        preservedAlphaRGBFilterTextureSlots: Set<Int>,
        typedDataRGBFilterSourceSlot: Int? = nil,
        typedDataRGBFilterAuxiliarySlots: Set<Int> = [],
        sameAlphaReconstructedRGBFilterSourceSlot: Int? = nil,
        sameAlphaReconstructedRGBFilterAuxiliarySlots: Set<Int> = [],
        straightRGBScalarAlphaSourceSlot: Int? = nil,
        straightRGBScalarAlphaAuxiliarySlots: Set<Int> = [],
        straightRGBScalarAlphaMaskSlot: Int? = nil,
        activeTextureSlots: Set<Int> = [],
        activeOpacityMaskSlots: Set<Int> = [],
        typedStaticDataAuxiliarySlots: Set<Int> = [],
        spatialWeightedColorBlendSourceSlot: Int? = nil,
        spatialWeightedColorBlendActiveSlots: Set<Int> = [],
        spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int> = [],
        spatialWeightedColorBlendExternalColorSlot: Int? = nil,
        unitCompositeBlurredSlot: Int?,
        unitCompositePreviousSlot: Int?,
        unitCompositeMaskSlot: Int? = nil,
        unitCompositeSourceBlurredSlot: Int? = nil,
        unitCompositeSourcePreviousSlot: Int? = nil,
        unitCompositeSourceMaskSlot: Int? = nil,
        hasExternalProviderTexture: Bool,
        producesScalarRedOutput: Bool,
        producesRedGreenUnormOutput: Bool = false,
        producesPreservedRGBAOutput: Bool = false,
        hasDefiniteWholeOutput: Bool = false,
        isScalarSplatOutput: Bool = false,
        hasOnlyScalarDataInputs: Bool = false,
        isSourceIndependentPremultipliedOutput: Bool,
        graphTextureSlots: Set<Int>,
        graphInputTextureSlots: Set<Int>,
        r8TextureSlots: Set<Int>,
        hasDefaultedOpacityMaskSampler: Bool,
        hasOnlyTypedOpacityMaskAuxiliary: Bool = false,
        hasOnlyGraphInputSampler: Bool = false,
        outputIsRGBA8Unorm: Bool = false,
        hasStageScopedUniformBindings: Bool,
        hasStereoAudioSpectrumArrays: Bool
    ) {
        let conditionalGeneratedRGBFact =
            SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let opaqueLoopSampleAverageFact =
            SceneAuthoredShaderOpaqueLoopSampleAverageAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let opaqueStaticSampleAverageFact =
            SceneAuthoredShaderOpaqueStaticSampleAverageAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let opaqueAlphaWeightedLoopAverageFact =
            SceneAuthoredShaderOpaqueAlphaWeightedLoopAverageAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let conditionalOpaqueAlphaWeightedRGBFact =
            SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer.analyze(
                fragmentSource: fragmentSource
            )
        let sameSlotColorReplacementSourceSlot =
            SceneAuthoredShaderSameSlotMixAnalyzer.aliasReplacementSourceSlot(
                fragmentSource: fragmentSource
            )
        let rgbBlendScalarAlphaFact =
            SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
                fragmentSource: fragmentSource
            )
        let scalarAlphaColorSourceSlot: Int? = {
            switch colorTransfer {
            case let .straightAlpha(sourceSlot),
                 let .straightAlphaUNorm(sourceSlot):
                sourceSlot
            default:
                nil
            }
        }()
        if producesPreservedRGBAOutput,
           hasDefiniteWholeOutput,
           !hasExternalProviderTexture,
           graphTextureSlots.count == 1,
           graphInputTextureSlots == graphTextureSlots,
           hasOnlyGraphInputSampler || hasOnlyTypedOpacityMaskAuxiliary {
            self = .sourceProvenPreservedRGBAStateTransform
        } else if producesRedGreenUnormOutput,
           isScalarSplatOutput,
           hasOnlyScalarDataInputs,
           !hasExternalProviderTexture,
           graphTextureSlots.isEmpty,
           graphInputTextureSlots.isEmpty {
            self = .sourceProvenRedGreenUnormScalarSplat
        } else if colorTransfer == .premultipliedAlpha,
           isSourceIndependentPremultipliedOutput,
           !hasExternalProviderTexture,
           !producesScalarRedOutput,
           graphTextureSlots.isEmpty,
           graphInputTextureSlots.isEmpty {
            self = .sourceProvenIndependentPremultipliedOutput
        } else if case let .independentAlphaSignal(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputIndependentSignalProducer
        } else if case let .independentAlphaSignalPreserving(sourceSlot) =
                    colorTransfer,
                  independentSignalAccumulatorSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots == Set([sourceSlot]),
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphTargetIndependentSignalAccumulator
        } else if case let .independentAlphaSignalPreserving(sourceSlot) =
                    colorTransfer,
                  independentSignalUNormAccumulatorSourceSlot == sourceSlot,
                  outputIsRGBA8Unorm,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots == Set([sourceSlot]),
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphTargetIndependentSignalUNormAccumulator
        } else if case let .independentAlphaSignalCompositing(
                    signalSlot, colorSlot
                  ) = colorTransfer,
                  signalSlot != colorSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.contains(signalSlot),
                  graphTextureSlots.isSubset(of: Set([signalSlot, colorSlot])),
                  graphInputTextureSlots == Set([signalSlot, colorSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputIndependentSignalCompositing
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
        } else if let fact = opaqueLoopSampleAverageFact,
                  colorTransfer == .opaque,
                  (3 ... 33).contains(fact.sampleCount),
                  activeTextureSlots == Set([fact.sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesRedGreenUnormOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots == Set([fact.sourceSlot]),
                  graphInputTextureSlots == Set([fact.sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphTargetOpaqueLoopSampleAverage
        } else if let fact = opaqueStaticSampleAverageFact,
                  colorTransfer == .opaque,
                  (2 ... 16).contains(fact.sampleCount),
                  activeTextureSlots == Set([fact.sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesRedGreenUnormOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots == Set([fact.sourceSlot]),
                  graphInputTextureSlots == Set([fact.sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphTargetOpaqueStaticSampleAverage
        } else if let fact = opaqueAlphaWeightedLoopAverageFact,
                  colorTransfer == .opaque,
                  (1 ... 16).contains(fact.sampleCount),
                  activeTextureSlots == Set([fact.sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesRedGreenUnormOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots == Set([fact.sourceSlot]),
                  graphInputTextureSlots == Set([fact.sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage
        } else if let fact = conditionalOpaqueAlphaWeightedRGBFact,
                  colorTransfer == .opaqueFromStraightColor(
                    textureSlot: fact.sourceSlot
                  ),
                  activeTextureSlots == Set([fact.sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesRedGreenUnormOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([fact.sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB
        } else if let fact = conditionalGeneratedRGBFact,
                  case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  fact.alphaCarrierSlot == sourceSlot,
                  !fact.sampleCallCounts.isEmpty,
                  Set(fact.sampleCallCounts.keys) == activeTextureSlots,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
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
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  preservedAlphaRGBFilterSourceSlot == sourceSlot,
                  !preservedAlphaRGBFilterTextureSlots.isEmpty,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots == preservedAlphaRGBFilterTextureSlots {
            self = .sourceProvenGraphInputPreservedAlphaRGBFilter
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  spatialWeightedColorBlendSourceSlot == sourceSlot,
                  let externalColorSlot =
                    spatialWeightedColorBlendExternalColorSlot,
                  externalColorSlot != sourceSlot,
                  spatialWeightedColorBlendActiveSlots.count >= 3,
                  spatialWeightedColorBlendTypedAuxiliarySlots
                    == spatialWeightedColorBlendActiveSlots.subtracting([sourceSlot]),
                  hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .providerBackedGraphInputSpatialWeightedColorBlend
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  spatialWeightedColorBlendSourceSlot == sourceSlot,
                  spatialWeightedColorBlendActiveSlots.count >= 3,
                  spatialWeightedColorBlendTypedAuxiliarySlots
                    == spatialWeightedColorBlendActiveSlots.subtracting([sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputSpatialWeightedColorBlend
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  sameAlphaReconstructedRGBFilterSourceSlot == sourceSlot,
                  !sameAlphaReconstructedRGBFilterAuxiliarySlots.isEmpty,
                  sameAlphaReconstructedRGBFilterAuxiliarySlots
                    == typedStaticDataAuxiliarySlots,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isSubset(of: Set([sourceSlot])),
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputSameAlphaReconstructedRGBDataFilter
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  typedDataRGBFilterSourceSlot == sourceSlot,
                  !typedDataRGBFilterAuxiliarySlots.isEmpty,
                  typedDataRGBFilterAuxiliarySlots
                    == typedStaticDataAuxiliarySlots,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isSubset(of: Set([sourceSlot])),
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputTypedDataRGBFilter
        } else if case let .straightAlphaPreserving(transferBlurred) = colorTransfer,
                  let sourceBlurred = unitCompositeSourceBlurredSlot
                    ?? unitCompositeBlurredSlot,
                  let sourcePrevious = unitCompositeSourcePreviousSlot
                    ?? unitCompositePreviousSlot,
                  transferBlurred == sourceBlurred,
                  sourceBlurred != sourcePrevious {
            let ownerEligible = unitCompositeBlurredSlot == sourceBlurred
                && unitCompositePreviousSlot == sourcePrevious
                && unitCompositeMaskSlot == unitCompositeSourceMaskSlot
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
                  sameSlotColorReplacementSourceSlot == sourceSlot,
                  activeTextureSlots == Set([sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  !producesRedGreenUnormOutput,
                  !producesPreservedRGBAOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputSameSlotColorReplacement
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
                  overlayAlphaBlendSourceSlot == sourceSlot,
                  let overlaySlot = overlayAlphaBlendAuxiliarySlot,
                  overlaySlot != sourceSlot,
                  typedStaticDataAuxiliarySlots == Set([overlaySlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputOverlayAlphaBlend
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  singleSamplerAlphaMutationSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler {
            self = .sourceProvenGraphInputSingleSamplerAlphaMutation
        } else if let sourceSlot = scalarAlphaColorSourceSlot,
                  rgbBlendScalarAlphaFact?.sourceSlot == sourceSlot,
                  rgbBlendScalarAlphaFact?.auxiliarySlots
                    == typedStaticDataAuxiliarySlots,
                  activeOpacityMaskSlots == (
                    rgbBlendScalarAlphaFact?.maskSlot.map { Set([$0]) } ?? []
                  ),
                  activeTextureSlots
                    == typedStaticDataAuxiliarySlots.union([sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputRGBBlendScalarAlpha
        } else if let sourceSlot = scalarAlphaColorSourceSlot,
                  straightRGBScalarAlphaSourceSlot == sourceSlot,
                  straightRGBScalarAlphaAuxiliarySlots
                    == typedStaticDataAuxiliarySlots,
                  activeOpacityMaskSlots == (
                    straightRGBScalarAlphaMaskSlot.map { Set([$0]) } ?? []
                  ),
                  activeTextureSlots
                    == straightRGBScalarAlphaAuxiliarySlots.union([sourceSlot]),
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputStraightRGBScalarAlpha
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasOnlyGraphInputSampler,
                  hasStageScopedUniformBindings,
                  hasStereoAudioSpectrumArrays {
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
                  !typedStaticDataAuxiliarySlots.isEmpty,
                  activeTextureSlots
                    == typedStaticDataAuxiliarySlots.union([sourceSlot]),
                  activeOpacityMaskSlots.isEmpty,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasStageScopedUniformBindings {
            self =
                .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary
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
             .sourceProvenGraphInputStraightAlpha,
             .sourceProvenGraphInputStraightAlphaPreserving:
            .preferGeneric
        case .sourceProvenScalarColorInterpolation,
             .sourceProvenOpaqueScalarOutput,
             .sourceProvenStraightAlphaR8Signal,
             .sourceProvenRedGreenUnormScalarSplat,
             .sourceProvenPreservedRGBAStateTransform,
             .sourceProvenIndependentPremultipliedOutput,
             .sourceProvenGraphInputIndependentSignalProducer,
             .sourceProvenGraphTargetIndependentSignalAccumulator,
             .sourceProvenGraphTargetIndependentSignalUNormAccumulator,
             .sourceProvenGraphInputIndependentSignalCompositing,
             .sourceProvenGraphTargetPassthrough,
             .sourceProvenGraphInputSameSlotColorReplacement,
             .sourceProvenNormalizedSampleSum,
             .sourceProvenGraphTargetOpaqueLoopSampleAverage,
             .sourceProvenGraphTargetOpaqueStaticSampleAverage,
             .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage,
             .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB,
             .sourceProvenGraphInputAlphaWeightedSampleAverage,
             .sourceProvenGraphInputPreservedAlphaRGBFilter,
             .sourceProvenGraphInputTypedDataRGBFilter,
             .sourceProvenGraphInputSameAlphaReconstructedRGBDataFilter,
             .sourceProvenUnitPreviousBlurredComposite,
             .sourceProvenGraphInputAlphaAttenuation,
             .sourceProvenGraphInputColorBlend,
             .sourceProvenGraphInputSpatialWeightedColorBlend,
             .providerBackedGraphInputSpatialWeightedColorBlend,
             .sourceProvenGraphInputOverlayAlphaBlend,
             .sourceProvenGraphInputConditionalStraightUnion,
             .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha,
             .sourceProvenGraphInputSingleSamplerAlphaMutation,
             .sourceProvenGraphInputStraightRGBScalarAlpha,
             .sourceProvenGraphInputRGBBlendScalarAlpha,
             .sourceProvenGraphInputSameSlotChannelReconstruction,
             .sourceProvenGraphInputAuxiliaryRGBBlendAlphaPreserving,
             .sourceProvenGraphInputAudioStageUniformStraightAlphaNoAuxiliary,
             .sourceProvenGraphInputStageUniformStraightAlphaPreserving,
             .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary,
             .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary,
             .sourceProvenGraphInputStageUniformPassthrough:
            .genericOnly
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .observeOnly
        }
    }

    /// New owner migrations are controlled only by the exact profile map;
    /// the legacy process-wide switch must not revoke their product owner.
    var ignoresLegacyProcessRoute: Bool {
        self == .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
            || self == .sourceProvenGraphTargetOpaqueLoopSampleAverage
            || self == .sourceProvenGraphTargetOpaqueStaticSampleAverage
            || self == .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage
            || self == .sourceProvenGraphInputSameSlotColorReplacement
            || self == .providerBackedGraphInputSpatialWeightedColorBlend
            || self
                == .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB
    }

    /// Shared profiles normally roll back through the bounded frontend. The
    /// preserved-alpha RGB filters and the unit previous/blurred composite
    /// have no complete, visually safe secondary owner: disabling their
    /// generic owner must reject that effect back to the safe previous-current
    /// boundary. A source-proven composite that lacks the surrounding graph
    /// owner token remains quarantined behind the verified incumbent.
    var validatedRollbackOwner: SceneGenericShaderFallbackOwner {
        switch self {
        case .sourceProvenGraphInputPreservedAlphaRGBFilter,
             .sourceProvenGraphInputTypedDataRGBFilter,
             .sourceProvenGraphInputStraightRGBScalarAlpha,
             .sourceProvenGraphInputRGBBlendScalarAlpha,
             .sourceProvenUnitPreviousBlurredComposite:
            .none
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .programFirstIncumbent
        default:
            .boundedFrontend
        }
    }

    /// This exact source-derived profile has a complete shared Swift frontend
    /// owner. Falling back between shared compiler backends never revives a
    /// retained dedicated product renderer.
    func permitsBoundedFrontendAfterArtifactFailure(
        routeState: SceneGenericShaderRouteState
    ) -> Bool {
        guard validatedRollbackOwner == .boundedFrontend else { return false }
            return routeState != .genericOnly
            || self
                == .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
            || self == .sourceProvenGraphInputOverlayAlphaBlend
            || self
                == .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB
    }

    func artifactFallbackOutcome(
        routeState: SceneGenericShaderRouteState
    ) -> String {
        guard routeState == .genericOnly else { return "fallback" }
        return permitsBoundedFrontendAfterArtifactFailure(routeState: routeState)
            ? "shared-backend-fallback" : "rejected"
    }
}
