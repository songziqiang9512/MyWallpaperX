import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func deriveVariantProviderFacts(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        sourceCarriedRGBAFact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact?,
        sourceColorTransfer: SceneShaderColorTransfer,
        spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?,
        conditionalGeneratedRGBFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?,
        sameAlphaReconstructedRGBFact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?,
        rgbBlendScalarAlphaFact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact?,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        activeGraphTextureIdentities: [Int: Graph.TextureIdentity],
        graphTextureFormatFacts: [Graph.TextureIdentity: SceneShaderTextureFormat],
        activeSamplerNames: Set<String>,
        cachedAnalysis: SceneResolvedMaterialVariantAnalysisCache.Record?
    ) throws -> (
        sourceCarriedAuxiliaryDataSlots: Set<Int>,
        spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int>,
        selectedMixedDataSlots: Set<Int>,
        activeExternalProviderTextureSlots: Set<Int>,
        premultipliedColorAuxiliarySlots: Set<Int>,
        spatialWeightedColorBlendExternalColorSlot: Int?,
        preservedAlphaRGBColorSlots: Set<Int>,
        conditionalGeneratedRGBInputContract: SceneResolvedMaterialProgramDerivation.ConditionalGeneratedRGBInputContract?,
        sameAlphaReconstructedRGBInputContract: SceneResolvedMaterialProgramDerivation.SameAlphaReconstructedRGBInputContract?,
        sourceGraphInputFacts: [Int: SceneResolvedMaterialGraphInputSourceSlotFact],
        graphInputTextureSlots: Set<Int>,
        typedStaticDataAuxiliarySlots: Set<Int>,
        graphR8TextureSlots: Set<Int>,
        activeTextureSlots: Set<Int>,
        activeOpacityMaskSlots: Set<Int>,
        neutralTextureResolution: SceneAuthoredShaderNeutralTextureResolutionFact?
    ) {
        let sourceCarriedAuxiliaryDataSlots =
            sourceCarriedRGBAFact?.colorTransfer == sourceColorTransfer
            ? sourceCarriedRGBAFact?.auxiliaryDataSlots ?? [] : []
        let spatialWeightedColorBlendTypedAuxiliarySlots = Set(
            sourceActiveSamplers.compactMap { slot, sampler in
                sampler.sourceProvenPurpose == nil ? nil : slot
            }
        )
        let mixedProviderFacts = mixedProviderSlotFacts(
            in: template,
            samplers: sourceActiveSamplers
        )
        let mixedProviderSlots = Set(mixedProviderFacts.keys)
        let selectedMixedDataSlots = Set(mixedProviderFacts.compactMap {
            slot, _ in variantKey.selectedTexturePurposes[slot]
                == .preservedChannels ? slot : nil
        })
        let selectedMixedPremultipliedSlots = Set(
            mixedProviderFacts.compactMap { slot, _ in
                variantKey.selectedTexturePurposes[slot]
                    == .premultipliedColor ? slot : nil
            }
        )
        guard selectedMixedDataSlots.union(selectedMixedPremultipliedSlots)
                == mixedProviderSlots else {
            throw failure(
                .textureVariantKeyIdentityInvariant,
                phase: .invariant,
                details: ["mixed-provider-purpose-profile"]
            )
        }
        let activeSceneBackgroundTextureSlots = Set(
            sourceActiveSamplers.compactMap { slot, sampler in
                SceneResolvedMaterialTextureResolver.sceneBackgroundDefault(
                    template: template,
                    sampler: sampler,
                    slot: slot
                ) == nil ? nil : slot
            }
        )
        let activeExternalProviderTextureSlots = externalProviderTextureSlots(
            in: template,
            activeTextureSlots: Set(sourceActiveSamplers.keys)
        ).union(activeSceneBackgroundTextureSlots)
        let staticallyTerminalNamedLayerProviderTextureSlots =
            terminalNamedLayerProviderTextureSlots(
                in: template,
                activeTextureSlots: Set(sourceActiveSamplers.keys)
            )
            .subtracting(mixedProviderSlots)
            .subtracting(sourceCarriedAuxiliaryDataSlots)
        let activeTerminalNamedLayerProviderTextureSlots =
            staticallyTerminalNamedLayerProviderTextureSlots.union(
                selectedMixedPremultipliedSlots
            )
        let premultipliedColorAuxiliarySlots =
            premultipliedAuxiliaryColorSlots(
                template: template,
                samplers: sourceActiveSamplers,
                externalSlots: activeExternalProviderTextureSlots,
                terminalNamedSlots: activeTerminalNamedLayerProviderTextureSlots,
                sceneBackgroundSlots: activeSceneBackgroundTextureSlots,
                graphSlots: Set(activeGraphTextureIdentities.keys),
                conditionalFact: conditionalGeneratedRGBFact
            )
        let spatialWeightedColorBlendExternalColorSlot: Int?
        if let fact = spatialWeightedColorBlendFact,
           activeExternalProviderTextureSlots == [fact.straightColorSlot],
           activeTerminalNamedLayerProviderTextureSlots == [fact.straightColorSlot] {
            spatialWeightedColorBlendExternalColorSlot = fact.straightColorSlot
        } else {
            spatialWeightedColorBlendExternalColorSlot = nil
        }
        let preservedAlphaRGBColorSlots: Set<Int>
        if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
            fragmentSource: compilerSources.fragment
        ) {
            preservedAlphaRGBColorSlots = Set(fact.colorSampleCallCounts.keys)
        } else if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
            fragmentSource: compilerSources.fragment
        ) {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else if let fact = sameAlphaReconstructedRGBFact {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else if let fact = rgbBlendScalarAlphaFact {
            preservedAlphaRGBColorSlots = [fact.sourceSlot]
        } else {
            preservedAlphaRGBColorSlots = []
        }
        let conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?
        if let fact = conditionalGeneratedRGBFact,
           sourceColorTransfer == .straightAlphaPreserving(
            textureSlot: fact.alphaCarrierSlot
           ) {
            conditionalGeneratedRGBInputContract = .init(
                alphaCarrierSlot: fact.alphaCarrierSlot,
                generatedOpaqueColorSlots: fact.generatedOpaqueColorSlots,
                scalarRedSlots: fact.scalarRedSlots,
                scalarGreenSlots: fact.scalarGreenSlots,
                scalarBlueSlots: fact.scalarBlueSlots,
                scalarAlphaSlots: fact.scalarAlphaSlots
            )
        } else {
            conditionalGeneratedRGBInputContract = nil
        }
        let sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?
        if let fact = sameAlphaReconstructedRGBFact,
           sourceColorTransfer == (fact.preservesSnapshotAlpha
            ? .straightAlphaPreserving(textureSlot: fact.sourceSlot)
            : .straightAlpha(textureSlot: fact.sourceSlot)) {
            sameAlphaReconstructedRGBInputContract = .init(
                sourceSlot: fact.sourceSlot,
                dataSlots: fact.auxiliarySlots
            )
        } else {
            sameAlphaReconstructedRGBInputContract = nil
        }
        let sourceGraphInputFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: template,
                samplers: sourceActiveSamplers,
                inputIdentity: implicitFramebufferIdentity,
                sourceColorTransfer: sourceColorTransfer
            )
        var graphInputTextureSlots = Set(activeGraphTextureIdentities.keys)
        graphInputTextureSlots.formUnion(template.graphRole.bindings.compactMap {
            sourceActiveSamplers[$0.slot] == nil ? nil : $0.slot
        })
        graphInputTextureSlots.formUnion(sourceGraphInputFacts.keys)
        let typedStaticDataAuxiliarySlots = typedStaticDataAuxiliarySlots(
            template: template,
            samplers: sourceActiveSamplers,
            graphInputSlots: graphInputTextureSlots
        ).subtracting(mixedProviderSlots)
        let graphR8TextureSlots = Set(activeGraphTextureIdentities.compactMap {
            graphTextureFormatFacts[$0.value] == .r8 ? $0.key : nil
        })
        let activeTextureSlots: Set<Int> = Set(activeSamplerNames.compactMap { name -> Int? in
            guard name.hasPrefix("g_Texture"),
                  let slot = Int(name.dropFirst("g_Texture".count)) else {
                return nil
            }
            return slot
        })
        let activeOpacityMaskSlots = Set(sourceActiveSamplers.compactMap {
            slot, sampler in sampler.mode == .opacityMask ? slot : nil
        })
        let neutralTextureResolution: SceneAuthoredShaderNeutralTextureResolutionFact?
        if let cachedAnalysis {
            neutralTextureResolution = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.neutralTextureResolution)
        } else {
            neutralTextureResolution =
                SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                    vertexSource: compilerSources.vertex,
                    fragmentSource: compilerSources.fragment,
                    activeSamplerSlots: activeTextureSlots
                )
        }
        return (
            sourceCarriedAuxiliaryDataSlots,
            spatialWeightedColorBlendTypedAuxiliarySlots,
            selectedMixedDataSlots,
            activeExternalProviderTextureSlots,
            premultipliedColorAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot,
            preservedAlphaRGBColorSlots,
            conditionalGeneratedRGBInputContract,
            sameAlphaReconstructedRGBInputContract,
            sourceGraphInputFacts,
            graphInputTextureSlots,
            typedStaticDataAuxiliarySlots,
            graphR8TextureSlots,
            activeTextureSlots,
            activeOpacityMaskSlots,
            neutralTextureResolution
        )
    }
}
