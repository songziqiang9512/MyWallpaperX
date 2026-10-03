import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func resolveVariantArtifact(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        prepared: SceneShaderPreparedProgram,
        cachedAnalysis: SceneResolvedMaterialVariantAnalysisCache.Record?,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        sourceGraphInputFacts: [Int: SceneResolvedMaterialGraphInputSourceSlotFact],
        sourceColorTransfer: SceneShaderColorTransfer,
        activeGraphTextureIdentities: [Int: Graph.TextureIdentity],
        analysisStart: Double,
        activeExternalProviderTextureSlots: Set<Int>,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        activeTextureSlots: Set<Int>,
        graphTextureSlots: Set<Int>,
        graphInputTextureSlots: Set<Int>,
        activeOpacityMaskSlots: Set<Int>,
        typedStaticDataAuxiliarySlots: Set<Int>,
        selectedMixedDataSlots: Set<Int>,
        sourceCarriedAuxiliaryDataSlots: Set<Int>,
        premultipliedColorAuxiliarySlots: Set<Int>,
        spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?,
        spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int>,
        spatialWeightedColorBlendExternalColorSlot: Int?,
        graphR8TextureSlots: Set<Int>,
        outputIsRGBA8Unorm: Bool,
        outputSemantics: SceneGenericShaderOutputSemantics,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    ) -> (
        alphaAttenuationFact: SceneAuthoredShaderAlphaAttenuationFact?,
        colorBlendFact: SceneAuthoredShaderGraphInputColorBlendFact?,
        previousBlurredCompositeAnalyzerFact: SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact?,
        artifactStart: Double,
        artifactResolution: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ) {
        // Recomputed per launch on purpose: the eligibility trio reads
        // per-node template facts (graphRole, effectContext, owner
        // eligibility, exact candidate identities) that are outside the
        // variant analysis key, so caching it would leak one node's
        // admission authority to another node sharing the key.
        let alphaAttenuationSourceSlot: Int?
        let colorBlendSourceSlot: Int?
        let previousBlurredCompositeSlots:
            SceneResolvedMaterialPreviousBlurredCompositeEligibility.Slots?
        let alphaAttenuationFact: SceneAuthoredShaderAlphaAttenuationFact?
        let colorBlendFact: SceneAuthoredShaderGraphInputColorBlendFact?
        let previousBlurredCompositeAnalyzerFact:
            SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact?
        if let cachedAnalysis {
            // The cached facts are the source-pure analyzer prefix; the
            // per-node validation segment re-runs every launch.
            alphaAttenuationFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.alphaAttenuationFact)
            colorBlendFact = SceneResolvedMaterialVariantAnalysisCache.rebuild(
                cachedAnalysis.colorBlendFact
            )
            previousBlurredCompositeAnalyzerFact =
                SceneResolvedMaterialVariantAnalysisCache.rebuild(
                    cachedAnalysis.previousBlurredCompositeFact
                )
        } else {
            alphaAttenuationFact = SceneAuthoredShaderAlphaAttenuationAnalyzer
                .analyze(fragmentSource: prepared.fragment.source)
            colorBlendFact = SceneAuthoredShaderGraphInputColorBlendAnalyzer
                .analyze(fragmentSource: prepared.fragment.source)
            previousBlurredCompositeAnalyzerFact =
                SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                )
        }
        if let fact = alphaAttenuationFact,
            SceneResolvedMaterialAlphaAttenuationEligibility.validated(
                fact: fact,
                samplers: sourceActiveSamplers,
                template: template,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphInputSourceSlotFacts: sourceGraphInputFacts
            ) {
            alphaAttenuationSourceSlot = fact.sourceSlot
        } else {
            alphaAttenuationSourceSlot = nil
        }
        if let fact = colorBlendFact,
            SceneResolvedMaterialColorBlendEligibility.transfer(
                sourceColorTransfer, matches: fact
            ), SceneResolvedMaterialColorBlendEligibility.validated(
                fact: fact,
                samplers: sourceActiveSamplers,
                template: template,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphInputSourceSlotFacts: sourceGraphInputFacts
            ) {
            colorBlendSourceSlot = fact.sourceSlot
        } else {
            colorBlendSourceSlot = nil
        }
        if let fact = previousBlurredCompositeAnalyzerFact,
            template.previousBlurredCompositeGenericOwnerEligible,
            let slots = SceneResolvedMaterialPreviousBlurredCompositeEligibility
                .validated(
                    shape: fact,
                    prepared: prepared,
                    samplers: sourceActiveSamplers,
                    template: template,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    activeGraphTextureIdentities: activeGraphTextureIdentities
                ) {
            previousBlurredCompositeSlots = slots
        } else {
            previousBlurredCompositeSlots = nil
        }
        SceneResolvedMaterialVariantCompileProfile.add(
            analysis: (CACurrentMediaTime() - analysisStart) * 1000
        )
        let artifactStart = CACurrentMediaTime()
        let artifactResolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: compilerSources.vertex,
            fragmentSource: compilerSources.fragment,
            alphaAttenuationSourceSlot: alphaAttenuationSourceSlot,
            colorBlendSourceSlot: colorBlendSourceSlot,
            previousBlurredCompositeBlurredSlot: previousBlurredCompositeSlots?.blurred,
            previousBlurredCompositePreviousSlot: previousBlurredCompositeSlots?.previous,
            previousBlurredCompositeMaskSlot: previousBlurredCompositeSlots?.mask,
            hasExternalProviderTexture:
                !activeExternalProviderTextureSlots.isEmpty,
            producesScalarRedOutput: outputStorage == .scalarRedUnorm
                || outputStorage == .scalarRedFloat16,
            producesRedGreenUnormOutput: outputStorage == .redGreenUnorm,
            hasOnlyScalarDataInputs:
                SceneResolvedMaterialShaderSchema.hasOnlyScalarDataInputs(
                    sourceActiveSamplers,
                    activeSlots: activeTextureSlots,
                    resolvedFormats: variantKey.resolvedTextureFormats
                ),
            isSourceIndependentPremultipliedOutput:
                outputStorage == .color
                    && sourceActiveSamplers[0] == nil
                    && graphTextureSlots.isEmpty
                    && graphInputTextureSlots.isEmpty,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            activeTextureSlots: activeTextureSlots,
            activeOpacityMaskSlots: activeOpacityMaskSlots,
            typedStaticDataAuxiliarySlots: typedStaticDataAuxiliarySlots,
            preservedChannelsExternalProviderTextureSlots:
                selectedMixedDataSlots.union(
                    sourceCarriedAuxiliaryDataSlots.intersection(
                        activeExternalProviderTextureSlots
                    )
                ),
            premultipliedColorAuxiliarySlots:
                premultipliedColorAuxiliarySlots,
            spatialWeightedColorBlendSourceSlot:
                spatialWeightedColorBlendFact?.sourceSlot,
            spatialWeightedColorBlendActiveSlots:
                spatialWeightedColorBlendFact?.activeSlots ?? [],
            spatialWeightedColorBlendTypedAuxiliarySlots:
                spatialWeightedColorBlendTypedAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot:
                spatialWeightedColorBlendExternalColorSlot,
            r8TextureSlots: graphR8TextureSlots,
            hasDefaultedOpacityMaskSampler:
                SceneResolvedMaterialShaderSchema.hasOnlyDefaultedOpacityMaskAuxiliary(
                    sourceActiveSamplers,
                    graphInputSlots: graphInputTextureSlots
                ),
            hasOnlyTypedOpacityMaskAuxiliary:
                SceneResolvedMaterialShaderSchema.hasOnlyTypedOpacityMaskAuxiliary(
                    sourceActiveSamplers,
                    graphInputSlots: graphInputTextureSlots
                ),
            hasOnlyGraphInputSampler:
                !sourceActiveSamplers.isEmpty
                    && Set(sourceActiveSamplers.keys) == graphInputTextureSlots,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm,
            sourceColorTransfer: sourceColorTransfer,
            outputSemantics: outputSemantics,
            runtimeLoopBounds: runtimeLoopBounds
        )
        return (
            alphaAttenuationFact,
            colorBlendFact,
            previousBlurredCompositeAnalyzerFact,
            artifactStart,
            artifactResolution
        )
    }
}
