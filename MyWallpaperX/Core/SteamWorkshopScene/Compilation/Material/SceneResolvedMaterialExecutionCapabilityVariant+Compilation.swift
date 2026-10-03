import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func compile(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        outputIsRGBA8Unorm: Bool,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureFormatFacts: [Graph.TextureIdentity: SceneShaderTextureFormat],
        onBoundedFrontendCompilation: () -> Void
    ) throws -> Variant {
        let readinessMask = variantKey.readinessMask
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, readinessMask & (1 << UInt8($0)) != 0)
        })
        SceneResolvedMaterialVariantCompileProfile.beginVariant()
        let (
            prepared,
            variantAnalysisKey,
            cachedAnalysis,
            compilerSources,
            compatibilityTargetAdmissionPending,
            analysisStart,
            runtimeLoopBounds,
            resolvedIntegerCombos,
            activeSamplerNames,
            sourceActiveSamplers
        ) = try prepareVariantSources(
            template: template,
            variantKey: variantKey,
            readinessMask: readinessMask,
            readiness: readiness,
            implicitFramebufferIdentity: implicitFramebufferIdentity,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm
        )
        let normalBlendModeIdentifiers = Set(
            resolvedIntegerCombos.compactMap { name, value in
                value == 0 ? name : nil
            }
        )
        let activeGraphTextureIdentities = Dictionary(uniqueKeysWithValues:
            activeSamplerNames.compactMap { name -> (Int, Graph.TextureIdentity)? in
                guard name.hasPrefix("g_Texture"),
                      let slot = Int(name.dropFirst("g_Texture".count)),
                      template.textureSlots.indices.contains(slot),
                      let candidate = template.textureSlots[slot]?.candidates.last,
                      case let .graph(identity) = candidate.reference
                else { return nil }
                return (slot, identity)
            })
        let graphTextureSlots = Set(activeGraphTextureIdentities.compactMap {
            $0.value.kind == .framebuffer ? $0.key : nil
        })
        let (
            spatialWeightedColorBlendFact,
            sourceCarriedRGBAFact,
            rgba8UnormAccumulatorSourceSlot,
            conditionalGeneratedRGBFact,
            sameAlphaReconstructedRGBFact,
            rgbBlendScalarAlphaFact,
            sourceColorTransfer
        ) = analyzeVariantColor(
            cachedAnalysis: cachedAnalysis,
            compilerSources: compilerSources,
            normalBlendModeIdentifiers: normalBlendModeIdentifiers,
            runtimeLoopBounds: runtimeLoopBounds,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm
        )
        let (
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
        ) = try deriveVariantProviderFacts(
            template: template,
            variantKey: variantKey,
            sourceActiveSamplers: sourceActiveSamplers,
            sourceCarriedRGBAFact: sourceCarriedRGBAFact,
            sourceColorTransfer: sourceColorTransfer,
            spatialWeightedColorBlendFact: spatialWeightedColorBlendFact,
            conditionalGeneratedRGBFact: conditionalGeneratedRGBFact,
            sameAlphaReconstructedRGBFact: sameAlphaReconstructedRGBFact,
            rgbBlendScalarAlphaFact: rgbBlendScalarAlphaFact,
            compilerSources: compilerSources,
            implicitFramebufferIdentity: implicitFramebufferIdentity,
            activeGraphTextureIdentities: activeGraphTextureIdentities,
            graphTextureFormatFacts: graphTextureFormatFacts,
            activeSamplerNames: activeSamplerNames,
            cachedAnalysis: cachedAnalysis
        )
        let outputSemantics: SceneGenericShaderOutputSemantics = switch outputStorage {
        case .redGreenUnorm: .redGreenUnorm
        case .preservedRGBAUnorm: .preservedRGBAUnorm
        default: .color
        }
        let (
            alphaAttenuationFact,
            colorBlendFact,
            previousBlurredCompositeAnalyzerFact,
            artifactStart,
            artifactResolution
        ) = resolveVariantArtifact(
            template: template,
            variantKey: variantKey,
            prepared: prepared,
            cachedAnalysis: cachedAnalysis,
            compilerSources: compilerSources,
            sourceActiveSamplers: sourceActiveSamplers,
            implicitFramebufferIdentity: implicitFramebufferIdentity,
            sourceGraphInputFacts: sourceGraphInputFacts,
            sourceColorTransfer: sourceColorTransfer,
            activeGraphTextureIdentities: activeGraphTextureIdentities,
            analysisStart: analysisStart,
            activeExternalProviderTextureSlots: activeExternalProviderTextureSlots,
            outputStorage: outputStorage,
            activeTextureSlots: activeTextureSlots,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            activeOpacityMaskSlots: activeOpacityMaskSlots,
            typedStaticDataAuxiliarySlots: typedStaticDataAuxiliarySlots,
            selectedMixedDataSlots: selectedMixedDataSlots,
            sourceCarriedAuxiliaryDataSlots: sourceCarriedAuxiliaryDataSlots,
            premultipliedColorAuxiliarySlots: premultipliedColorAuxiliarySlots,
            spatialWeightedColorBlendFact: spatialWeightedColorBlendFact,
            spatialWeightedColorBlendTypedAuxiliarySlots: spatialWeightedColorBlendTypedAuxiliarySlots,
            spatialWeightedColorBlendExternalColorSlot: spatialWeightedColorBlendExternalColorSlot,
            graphR8TextureSlots: graphR8TextureSlots,
            outputIsRGBA8Unorm: outputIsRGBA8Unorm,
            outputSemantics: outputSemantics,
            runtimeLoopBounds: runtimeLoopBounds
        )
        let (
            frontend,
            routeDecision,
            boundedOutput,
            artifactFailure,
            premultipliedInputSlotsForProfile
        ) = try resolveVariantFrontend(
            template: template,
            sourceActiveSamplers: sourceActiveSamplers,
            spatialWeightedColorBlendExternalColorSlot: spatialWeightedColorBlendExternalColorSlot,
            premultipliedColorAuxiliarySlots: premultipliedColorAuxiliarySlots,
            artifactStart: artifactStart,
            artifactResolution: artifactResolution,
            compatibilityTargetAdmissionPending: compatibilityTargetAdmissionPending,
            onBoundedFrontendCompilation: onBoundedFrontendCompilation,
            compilerSources: compilerSources,
            runtimeLoopBounds: runtimeLoopBounds,
            sourceColorTransfer: sourceColorTransfer
        )
        let (
            sourceProvenOpaqueColorSlots,
            samplers,
            graphInputFacts,
            uniforms,
            preparedUniformBindings,
            associatedOverOverlaySlot
        ) = try finalizeVariantBindings(
            template: template,
            variantKey: variantKey,
            prepared: prepared,
            compilerSources: compilerSources,
            routeDecision: routeDecision,
            compatibilityTargetAdmissionPending: compatibilityTargetAdmissionPending,
            frontend: frontend,
            boundedOutput: boundedOutput,
            artifactFailure: artifactFailure,
            sourceActiveSamplers: sourceActiveSamplers,
            implicitFramebufferIdentity: implicitFramebufferIdentity,
            sourceGraphInputFacts: sourceGraphInputFacts,
            sourceColorTransfer: sourceColorTransfer,
            neutralTextureResolution: neutralTextureResolution
        )
        if cachedAnalysis == nil, let variantAnalysisKey {
            SceneResolvedMaterialVariantAnalysisCache.store(
                record: SceneResolvedMaterialVariantAnalysisCache.Record(
                    canonicalVertex: compilerSources.vertex,
                    canonicalFragment: compilerSources.fragment,
                    activeSamplerNames: Set(activeSamplerNames),
                    resolvedIntegerCombos: resolvedIntegerCombos,
                    sourceActiveSamplers: sourceActiveSamplers,
                    runtimeLoopBounds: runtimeLoopBounds,
                    sourceColorTransfer: sourceColorTransfer,
                    rgba8UnormAccumulatorSourceSlot:
                        rgba8UnormAccumulatorSourceSlot,
                    spatialWeightedColorBlend: spatialWeightedColorBlendFact
                        .map(SceneResolvedMaterialVariantAnalysisCache.mirror),
                    sourceCarriedRGBA: sourceCarriedRGBAFact.map(
                        SceneResolvedMaterialVariantAnalysisCache.mirror
                    ),
                    conditionalGeneratedRGB: conditionalGeneratedRGBFact.map(
                        SceneResolvedMaterialVariantAnalysisCache.mirror
                    ),
                    sameAlphaReconstructedRGB: sameAlphaReconstructedRGBFact
                        .map(SceneResolvedMaterialVariantAnalysisCache.mirror),
                    neutralTextureResolution: neutralTextureResolution.map(
                        SceneResolvedMaterialVariantAnalysisCache.mirror
                    ),
                    alphaAttenuationFact: alphaAttenuationFact.map(
                        SceneResolvedMaterialVariantAnalysisCache.mirror
                    ),
                    colorBlendFact: colorBlendFact.map(
                        SceneResolvedMaterialVariantAnalysisCache.mirror
                    ),
                    previousBlurredCompositeFact:
                        previousBlurredCompositeAnalyzerFact.map(
                            SceneResolvedMaterialVariantAnalysisCache.mirror
                        )
                ),
                keySHA256: variantAnalysisKey
            )
        }
        SceneResolvedMaterialVariantCompileProfile.endVariant()
        return .init(
            readinessMask: readinessMask,
            textureFormats: variantKey.textureFormats,
            preparedShader: prepared,
            resolvedIntegerCombos: resolvedIntegerCombos,
            frontendProgram: frontend,
            routeDecision: routeDecision,
            runtimeLoopBounds: runtimeLoopBounds,
            activeSamplers: samplers,
            graphInputSourceSlotFacts: graphInputFacts,
            preservedAlphaRGBColorSlots: preservedAlphaRGBColorSlots,
            sourceProvenOpaqueColorSlots: sourceProvenOpaqueColorSlots,
            premultipliedColorInputSlots:
                premultipliedInputSlotsForProfile(routeDecision.profile),
            preservedChannelsProviderInputSlots:
                selectedMixedDataSlots.union(
                    sourceCarriedAuxiliaryDataSlots.intersection(
                        activeExternalProviderTextureSlots
                    )
                ),
            associatedOverOverlaySlot: associatedOverOverlaySlot,
            conditionalGeneratedRGBInputContract:
                conditionalGeneratedRGBInputContract,
            sameAlphaReconstructedRGBInputContract:
                sameAlphaReconstructedRGBInputContract,
            activeUniforms: uniforms,
            preparedUniformBindings: preparedUniformBindings,
            neutralTextureResolution: neutralTextureResolution
        )
    }

}
