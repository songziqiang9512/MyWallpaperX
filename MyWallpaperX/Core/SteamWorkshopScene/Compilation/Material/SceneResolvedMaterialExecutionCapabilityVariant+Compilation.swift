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
        graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent],
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
        // Exact producer content covers explicit bindings and the existing
        // previous/default alias. A single color channel is not a data proof.
        let graphInputContents = Dictionary(uniqueKeysWithValues:
            sourceActiveSamplers.keys.compactMap { slot -> (Int, SceneTextureContent)? in
                guard readinessMask & (1 << UInt8(slot)) != 0,
                      let identity = activeGraphTextureIdentities[slot]
                        ?? sourceGraphInputFacts[slot]?.inputIdentity,
                      let content = graphTextureContentFacts[identity] else { return nil }
                return (slot, content)
            })
        let graphDataTextureSlots = Set(graphInputContents.compactMap {
            $0.value.isColorContent ? nil : $0.key
        })
        let signalPassthroughContent: SceneTextureContent?
        if case let .passthrough(slot) = sourceColorTransfer,
           graphInputContents[slot] == .color(.resolved(.independentAlphaSignal)) {
            signalPassthroughContent = graphInputContents[slot]
        } else {
            signalPassthroughContent = nil
        }
        let outputSemantics: SceneGenericShaderOutputSemantics = switch outputStorage {
        case .redGreenUnorm: .redGreenUnorm
        case .preservedRGBAUnorm: .preservedRGBAUnorm
        default: .color
        }
        // Authored color math has one boundary in both compilers. Actual
        // straight/PMA representation is a frame-owned input mask, so a local
        // graph failure can retain its previous publication without compiling
        // a new shader or guessing the representation from the profile.
        let colorBoundary = ordinaryColorBoundary(
            sourceTransfer: sourceColorTransfer,
            outputStorage: outputStorage,
            template: template,
            samplers: sourceActiveSamplers,
            selectedPurposes: variantKey.selectedTexturePurposes,
            graphColorSlots: graphInputTextureSlots.union(graphTextureSlots),
            providerColorSlots: premultipliedColorAuxiliarySlots.union(
                SceneResolvedMaterialTextureResolver.sceneBackgroundColorSlots(
                    template: template, samplers: sourceActiveSamplers
                )
            ),
            dataSlots: graphDataTextureSlots.union(typedStaticDataAuxiliarySlots)
                .union(sourceCarriedAuxiliaryDataSlots)
                .union(selectedMixedDataSlots),
            conditionalContract: conditionalGeneratedRGBInputContract
        )
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
            colorBoundary: colorBoundary,
            activeGraphTextureIdentities: activeGraphTextureIdentities,
            analysisStart: analysisStart,
            activeExternalProviderTextureSlots: activeExternalProviderTextureSlots,
            outputStorage: outputStorage,
            activeTextureSlots: activeTextureSlots,
            graphTextureSlots: graphTextureSlots,
            graphInputTextureSlots: graphInputTextureSlots,
            graphDataTextureSlots: graphDataTextureSlots,
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
            premultipliedColorInputSlots
        ) = try resolveVariantFrontend(
            template: template,
            sourceActiveSamplers: sourceActiveSamplers,
            spatialWeightedColorBlendExternalColorSlot: spatialWeightedColorBlendExternalColorSlot,
            premultipliedColorAuxiliarySlots: premultipliedColorAuxiliarySlots,
            mixedProviderSlots: Set(
                mixedProviderSlotFacts(
                    in: template,
                    samplers: sourceActiveSamplers
                ).keys
            ),
            outputSemantics: outputSemantics,
            artifactStart: artifactStart,
            artifactResolution: artifactResolution,
            compatibilityTargetAdmissionPending: compatibilityTargetAdmissionPending,
            onBoundedFrontendCompilation: onBoundedFrontendCompilation,
            compilerSources: compilerSources,
            runtimeLoopBounds: runtimeLoopBounds,
            sourceColorTransfer: sourceColorTransfer,
            colorBoundary: colorBoundary
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
            preparedOutputContent: preparedOutputContent(
                storage: outputStorage, frontend: frontend,
                signalPassthroughContent: signalPassthroughContent
            ),
            routeDecision: routeDecision,
            runtimeLoopBounds: runtimeLoopBounds,
            activeSamplers: samplers,
            graphInputSourceSlotFacts: graphInputFacts,
            preservedAlphaRGBColorSlots: preservedAlphaRGBColorSlots,
            sourceProvenOpaqueColorSlots: sourceProvenOpaqueColorSlots,
            premultipliedColorInputSlots: premultipliedColorInputSlots,
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

    private static func preparedOutputContent(
        storage: SceneResolvedMaterialProgram.OutputStorage,
        frontend: SceneAuthoredShaderProgram,
        signalPassthroughContent: SceneTextureContent?
    ) -> SceneTextureContent? {
        switch storage {
        case .scalarRedUnorm: return .scalarRedUnorm
        case .redGreenUnorm: return .redGreenUnorm
        case .scalarRedFloat16: return .scalarRedFloat16
        case .redGreenFloat16: return .redGreenFloat16
        case .preservedRGBAUnorm: return .data
        case .color: break
        }
        if frontend.colorBoundary?.signalPassthroughSlot != nil {
            return signalPassthroughContent
        }
        if let boundary = frontend.colorBoundary,
           let representation = SceneShaderColorRepresentation(
                rawValue: boundary.outputRepresentation.rawValue) {
            return .color(.resolved(representation))
        }
        if frontend.colorTransfer == .opaque { return .color(.resolved(.opaque)) }
        if case .passthrough = frontend.colorTransfer { return signalPassthroughContent }
        return nil
    }

    private static func ordinaryColorBoundary(
        sourceTransfer: SceneShaderColorTransfer,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        selectedPurposes: [SceneTextureLoadPurpose?],
        graphColorSlots: Set<Int>,
        providerColorSlots: Set<Int>,
        dataSlots: Set<Int>,
        conditionalContract: SceneResolvedMaterialProgramDerivation
            .ConditionalGeneratedRGBInputContract?
    ) -> SceneShaderColorBoundary? {
        guard outputStorage == .color else { return nil }
        switch sourceTransfer {
        case .premultipliedAlpha: return nil
        case let .independentAlphaSignal(slot):
            return .init(colorInputSlots: [slot], outputRepresentation: .independentAlphaSignal)
        case .independentAlphaSignalPreserving:
            return .init(colorInputSlots: [], outputRepresentation: .independentAlphaSignal)
        case let .independentAlphaSignalCompositing(_, color):
            return .init(colorInputSlots: [color], outputRepresentation: .premultipliedAlpha)
        case let .independentAlphaSignalUnderlayCompositing(_, color, underlay):
            return .init(colorInputSlots: [color, underlay], outputRepresentation: .premultipliedAlpha)
        default: break
        }
        var colorSlots = graphColorSlots.union(providerColorSlots)
        for (slot, sampler) in samplers {
            let references = (template.textureSlots.indices.contains(slot)
                ? template.textureSlots[slot]?.candidates.map(\.reference) : nil) ?? []
            let purposes = references.compactMap { sampler.purpose(for: $0) }
            if purposes.contains(.straightAlbedo) || purposes.contains(.premultipliedColor)
                || sampler.sourceProvenPurpose == .straightAlbedo
                || sampler.sourceProvenPurpose == .premultipliedColor {
                colorSlots.insert(slot)
            }
        }
        colorSlots.subtract(dataSlots)
        colorSlots = Set(colorSlots.filter { slot in
            guard let sampler = samplers[slot] else { return false }
            // A color channel remains color when read alone. Only the typed
            // data roles above exempt a sample from representation conversion.
            return sampler.mode == .regular || providerColorSlots.contains(slot)
                || selectedPurposes[slot] == .premultipliedColor
        })
        if let contract = conditionalContract {
            colorSlots.subtract(contract.scalarRedSlots)
            colorSlots.subtract(contract.scalarGreenSlots)
            colorSlots.subtract(contract.scalarBlueSlots)
            colorSlots.subtract(contract.scalarAlphaSlots)
        }
        let output: SceneShaderColorBoundary.OutputRepresentation
        switch sourceTransfer {
        case .opaque, .opaqueFromStraightColor: output = .opaque
        default:
            output = .straightAlpha
        }
        let signalSlot: Int?
        if case let .passthrough(slot) = sourceTransfer, colorSlots.contains(slot) {
            signalSlot = slot
        } else {
            signalSlot = nil
        }
        return .init(colorInputSlots: colorSlots, outputRepresentation: output,
                     signalPassthroughSlot: signalSlot)
    }

}
