import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func analyzeVariantColor(
        cachedAnalysis: SceneResolvedMaterialVariantAnalysisCache.Record?,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        normalBlendModeIdentifiers: Set<String>,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        outputIsRGBA8Unorm: Bool
    ) -> (
        spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?,
        sourceCarriedRGBAFact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact?,
        rgba8UnormAccumulatorSourceSlot: Int?,
        conditionalGeneratedRGBFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?,
        sameAlphaReconstructedRGBFact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?,
        rgbBlendScalarAlphaFact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact?,
        sourceColorTransfer: SceneShaderColorTransfer
    ) {
        let spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?
        let analyzedSourceColorTransfer: SceneShaderColorTransfer
        let sourceCarriedRGBAFact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact?
        let rgba8UnormAccumulatorSourceSlot: Int?
        let conditionalGeneratedRGBFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?
        let sameAlphaReconstructedRGBFact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?
        if let cachedAnalysis {
            spatialWeightedColorBlendFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.spatialWeightedColorBlend)
            analyzedSourceColorTransfer = cachedAnalysis.sourceColorTransfer
            sourceCarriedRGBAFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.sourceCarriedRGBA)
            rgba8UnormAccumulatorSourceSlot =
                cachedAnalysis.rgba8UnormAccumulatorSourceSlot
            conditionalGeneratedRGBFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.conditionalGeneratedRGB)
            sameAlphaReconstructedRGBFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.sameAlphaReconstructedRGB)
        } else {
            spatialWeightedColorBlendFact =
                SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment,
                    normalBlendModeIdentifiers: normalBlendModeIdentifiers
                )
            analyzedSourceColorTransfer =
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment,
                    provenRuntimeLoopBounds: runtimeLoopBounds.fragment
                )
            sourceCarriedRGBAFact =
                SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                    .analyzeSourceCarried(fragmentSource: compilerSources.fragment)
            rgba8UnormAccumulatorSourceSlot = outputIsRGBA8Unorm
                ? SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .rgba8UnormAttachmentSourceSlot(
                        fragmentSource: compilerSources.fragment
                    )
                : nil
            conditionalGeneratedRGBFact =
                SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                )
            sameAlphaReconstructedRGBFact =
                SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                )
        }
        let rgbBlendScalarAlphaFact =
            SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
                fragmentSource: compilerSources.fragment
            )
        let targetAwareSourceColorTransfer: SceneShaderColorTransfer =
            if analyzedSourceColorTransfer == .unresolved,
               let rgba8UnormAccumulatorSourceSlot {
                .independentAlphaSignalPreserving(
                    textureSlot: rgba8UnormAccumulatorSourceSlot
                )
            } else {
                analyzedSourceColorTransfer
            }
        let sourceColorTransfer: SceneShaderColorTransfer =
            spatialWeightedColorBlendFact.map {
                .straightAlphaPreserving(textureSlot: $0.sourceSlot)
            } ?? targetAwareSourceColorTransfer
        return (
            spatialWeightedColorBlendFact,
            sourceCarriedRGBAFact,
            rgba8UnormAccumulatorSourceSlot,
            conditionalGeneratedRGBFact,
            sameAlphaReconstructedRGBFact,
            rgbBlendScalarAlphaFact,
            sourceColorTransfer
        )
    }

    private typealias LaunchColorFact = SceneResolvedMaterialProgramDerivation.ColorTextureFact

    /// Runs frame color derivation for a material fed by the renderer-owned
    /// premultiplied layer capture. Later effectOutput stages, internal graph
    /// targets and dynamic providers retain the frame-time fail-closed gate.
    static func launchProgramFailure(
        template: Template,
        variants: [SceneResolvedMaterialCompiledVariant],
        readinessMask: UInt8,
        formatSlots: Set<Int>,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:]
    ) -> Failure? {
        for variant in variants {
            for binding in variant.frontendProgram.textureBindings
            where readinessMask & (1 << UInt8(binding.slot)) == 0 {
                guard !formatSlots.contains(binding.slot),
                      let sampler = variant.activeSamplers[binding.slot],
                      SceneResolvedMaterialShaderSchema.presenceIndependentDefault(
                          template: template,
                          sampler: sampler,
                          slot: binding.slot
                      ) != nil else {
#if DEBUG
                    if let sampler = variant.activeSamplers[binding.slot] {
                        NSLog(
                            "MWX DEBUG SCENE: phase=launch-program-failure slot=%d material=%@ label=%@ hidden=%d mode=%@ alias=%d",
                            binding.slot,
                            sampler.materialKey ?? "-",
                            sampler.labelKey ?? "-",
                            sampler.isHidden ? 1 : 0,
                            String(describing: sampler.mode),
                            SceneResolvedMaterialShaderSchema.usesGraphInputMaterialAlias(sampler) ? 1 : 0
                        )
                    }
#endif
                    return failure(.textureBindingInvalid, slot: binding.slot)
                }
            }
            let preservedChannelOutput = outputStorage != .color
            if preservedChannelOutput {
                guard variant.frontendProgram.fragmentOutputChannelUse == .redDefined else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["scalar-output-channel-unproven"]
                    )
                }
            } else if variant.frontendProgram.colorTransfer == .unresolved,
                      variant.frontendProgram.colorBoundary?.isValid != true {
                // A prepared ordinary color boundary can resolve a transfer
                // beyond source-shape inference. Keep the same typed texture
                // profiles and resolveColor validation used at frame time.
                return failure(
                    .colorContractUnproven,
                    phase: .color,
                    details: ["shader-color-transfer-unresolved"]
                )
            }
            var sourceProvenOpaqueProfiles: [[LaunchColorFact?]]?
            if !preservedChannelOutput,
               !variant.sourceProvenOpaqueColorSlots.isEmpty {
                switch launchColorProfiles(
                    template: template,
                    variant: variant,
                    readinessMask: readinessMask,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    graphTextureContentFacts: graphTextureContentFacts,
                    preservedChannelsProviderSlots:
                        variant.preservedChannelsProviderInputSlots,
                    assetStates: assetStates,
                    systemProviderStates: systemProviderStates
                ) {
                case .unknownInternalGraph:
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["source-proven-opaque-color-slots"]
                    )
                case .invalid:
                    return failure(.textureBindingInvalid)
                case .profiles(let profiles):
                    guard profiles.allSatisfy({
                        SceneResolvedMaterialProgramDerivation
                            .hasResolvedOpaqueColorSampleContract(
                                colorSlots:
                                    variant.sourceProvenOpaqueColorSlots,
                                textureFacts: $0,
                                colorBoundary: variant.frontendProgram.colorBoundary
                            )
                    }) else {
                        return failure(
                            .colorContractUnproven,
                            phase: .color,
                            details: ["source-proven-opaque-color-slots"]
                        )
                    }
                    sourceProvenOpaqueProfiles = profiles
                }
            }
            if !preservedChannelOutput, variant.frontendProgram.colorBoundary == nil,
               case let .straightAlphaUNorm(slot) =
                variant.frontendProgram.colorTransfer {
                guard implicitFramebufferIdentity?.kind == .layerSource,
                      template.graphRole.effectInput == .layerSource,
                      template.graphRole.effectOutput == .effectOutput,
                      template.graphRole.nodeTarget == .effectOutput,
                      (0 ..< 8).contains(slot) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["straight-alpha-unorm-topology"]
                    )
                }
            }
            guard implicitFramebufferIdentity?.kind == .layerSource else {
                continue
            }
            let profiles: [[LaunchColorFact?]]
            if let sourceProvenOpaqueProfiles {
                profiles = sourceProvenOpaqueProfiles
            } else {
                switch launchColorProfiles(
                    template: template,
                    variant: variant,
                    readinessMask: readinessMask,
                    implicitFramebufferIdentity: implicitFramebufferIdentity,
                    graphTextureContentFacts: graphTextureContentFacts,
                    preservedChannelsProviderSlots:
                        variant.preservedChannelsProviderInputSlots,
                    assetStates: assetStates,
                    systemProviderStates: systemProviderStates
                ) {
                case .unknownInternalGraph:
                    if !preservedChannelOutput, case .straightAlphaUNorm =
                        variant.frontendProgram.colorTransfer {
                        return failure(
                            .colorContractUnproven,
                            phase: .color,
                            details: ["straight-alpha-unorm-internal-graph"]
                        )
                    }
                    continue
                case .invalid:
                    return failure(.textureBindingInvalid)
                case .profiles(let value):
                    profiles = value
                }
            }
            if preservedChannelOutput { continue }
            if let contract = variant.conditionalGeneratedRGBInputContract {
                guard profiles.allSatisfy({
                    SceneResolvedMaterialProgramDerivation
                        .hasResolvedConditionalGeneratedRGBInputContract(
                            contract,
                            textureFacts: $0,
                            premultipliedColorInputSlots:
                                variant.premultipliedColorInputSlots,
                            colorBoundary: variant.frontendProgram.colorBoundary
                        )
                }) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["conditional-generated-rgb-input-contract"]
                    )
                }
            }
            if let contract = variant.sameAlphaReconstructedRGBInputContract {
                guard profiles.allSatisfy({
                    SceneResolvedMaterialProgramDerivation
                        .hasResolvedSameAlphaReconstructedRGBInputContract(
                            contract,
                            textureFacts: $0,
                            colorBoundary: variant.frontendProgram.colorBoundary
                        )
                }) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: [
                            "same-alpha-reconstructed-rgb-input-contract",
                        ]
                    )
                }
            }
            if variant.frontendProgram.colorBoundary == nil,
               case let .straightAlphaUNorm(slot) =
                variant.frontendProgram.colorTransfer {
                guard profiles.allSatisfy({ profile in
                    guard profile.indices.contains(slot),
                          let fact = profile[slot],
                          fact.isGraphReference else { return false }
                    return template.graphRole.bindings.isEmpty
                        || (template.graphRole.bindings.count == 1
                            && template.graphRole.bindings.contains {
                                $0.slot == slot && $0.texture == .layerSource
                            })
                }) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["straight-alpha-unorm-binding"]
                    )
                }
            }
            guard profiles.allSatisfy({
                SceneResolvedMaterialProgramDerivation.resolveColor(
                    transfer: variant.frontendProgram.colorTransfer,
                    textureFacts: $0,
                    conditionalGeneratedRGBInputContract:
                        variant.conditionalGeneratedRGBInputContract,
                    associatedOverOverlaySlot:
                        variant.associatedOverOverlaySlot,
                    premultipliedColorInputSlots:
                        variant.premultipliedColorInputSlots,
                    colorBoundary: variant.frontendProgram.colorBoundary
                ) != nil
            }) else {
                return failure(
                    .colorContractUnproven,
                    phase: .color,
                    details: [
                        "launch-color-projection-unresolved",
                        "transfer-\(SceneResolvedMaterialProgramIdentity.colorTransferToken(variant.frontendProgram.colorTransfer))",
                    ]
                )
            }
        }
        return nil
    }

    private enum LaunchColorProfiles {
        case profiles([[LaunchColorFact?]])
        case unknownInternalGraph
        case invalid
    }

    private static func launchColorProfiles(
        template: Template,
        variant: SceneResolvedMaterialCompiledVariant,
        readinessMask: UInt8,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent],
        preservedChannelsProviderSlots: Set<Int>,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:]
    ) -> LaunchColorProfiles {
        var profiles = [Array<LaunchColorFact?>(repeating: nil, count: 8)]
        for binding in variant.frontendProgram.textureBindings {
            guard profiles.indices.contains(0), (0 ..< 8).contains(binding.slot),
                  let sampler = variant.activeSamplers[binding.slot] else {
                return .invalid
            }
            let reference: Template.TextureReference
            let resolvedPurpose: SceneTextureLoadPurpose?
            switch launchReference(
                template: template,
                sampler: sampler,
                slot: binding.slot,
                readinessMask: readinessMask,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphInputSourceSlotFacts:
                    variant.graphInputSourceSlotFacts,
                assetStates: assetStates,
                systemProviderStates: systemProviderStates
            ) {
            case let .selected(value, purpose):
                reference = value
                resolvedPurpose = purpose
            case .deferred: return .unknownInternalGraph
            case .invalid, .none: return .invalid
            }
            if case let .provider(provider) = reference {
                switch provider {
                case let .system(name):
                    guard let purpose = resolvedPurpose,
                          case .ready? = systemProviderStates[
                              .init(name: name, purpose: purpose)
                          ] else { return .unknownInternalGraph }
                case .namedLayerTarget, .sceneBackground, .sceneEnvironment:
                    break
                }
            }
            if case .userProperty = reference {
                return .unknownInternalGraph
            }
            if case let .graph(identity) = reference,
               identity != implicitFramebufferIdentity,
               graphTextureContentFacts[identity] == nil {
                return .unknownInternalGraph
            }
            guard let fact = launchFact(
                for: reference,
                resolvedPurpose: resolvedPurpose,
                sampler: sampler,
                slot: binding.slot,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                graphTextureContentFacts: graphTextureContentFacts,
                preservedChannelsProviderSlots:
                    preservedChannelsProviderSlots,
                assetStates: assetStates,
                systemProviderStates: systemProviderStates
            ) else { return .invalid }
            for profile in profiles {
                guard profile[binding.slot] == nil else { return .invalid }
            }
            profiles[0][binding.slot] = fact
        }
        return .profiles(profiles)
    }

    private enum LaunchReference {
        case selected(
            Template.TextureReference,
            purpose: SceneTextureLoadPurpose?
        )
        case deferred
        case invalid
        case none
    }

    private static func launchReference(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int,
        readinessMask: UInt8,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:]
    ) -> LaunchReference {
        let ready = readinessMask & (UInt8(1) << UInt8(slot)) != 0
        if ready {
            do {
                switch try launchAuthoredReference(
                    template: template,
                    sampler: sampler,
                    slot: slot,
                    assetStates: assetStates
                ) {
                case let .selected(reference, purpose):
                    return .selected(reference, purpose: purpose)
                case .deferred: return .deferred
                case .none: break
                }
            } catch {
                return .invalid
            }
        }
        let defaultAllowed = sampler.readinessCombo == nil
            || SceneResolvedMaterialShaderSchema.presenceIndependentDefault(
                template: template,
                sampler: sampler,
                slot: slot
            ) != nil
        if defaultAllowed,
           let reference = SceneResolvedMaterialShaderSchema.renderTargetDefault(
               template: template, sampler: sampler, slot: slot,
               inputIdentity: implicitFramebufferIdentity
           ) {
            return .selected(
                reference,
                purpose: SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler)
            )
        }
        if defaultAllowed {
            do {
                switch try launchDefaultReference(
                    sampler: sampler, slot: slot,
                    assetStates: assetStates,
                    systemProviderStates: systemProviderStates
                ) {
                case let .selected(reference, purpose):
                    return .selected(reference, purpose: purpose)
                case .none: break
                case .deferred: return .deferred
                }
            } catch { return .invalid }
        }
        if let fact = graphInputSourceSlotFacts[slot],
           fact.inputIdentity == implicitFramebufferIdentity {
            let reference = Template.TextureReference.graph(
                fact.inputIdentity
            )
            return .selected(
                reference,
                purpose: SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler)
            )
        }
        return .none
    }

    private static func launchFact(
        for reference: Template.TextureReference,
        resolvedPurpose: SceneTextureLoadPurpose?,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent],
        preservedChannelsProviderSlots: Set<Int>,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:]
    ) -> LaunchColorFact? {
        if case let .graph(identity) = reference {
            if graphTextureContentFacts[identity] != nil || identity != implicitFramebufferIdentity {
                guard let content = graphTextureContentFacts[identity] else {
                    return nil
                }
                return .init(
                    isGraphReference: true,
                    isFramebufferInput: true,
                    content: content
                )
            }
            return .init(
                isGraphReference: true,
                isFramebufferInput: true,
                content: .color(.resolved(.premultipliedAlpha))
            )
        }
        if case let .provider(provider) = reference {
            switch provider {
            case .namedLayerTarget:
                return .init(
                    isGraphReference: false,
                    isFramebufferInput: false,
                    content: preservedChannelsProviderSlots.contains(slot)
                        ? .data
                        : .color(.resolved(.premultipliedAlpha))
                )
            case .sceneBackground, .sceneEnvironment:
                // Provider contract only; no readiness or concrete resource is
                // fabricated here. Frame finalization still requires publication.
                return .init(
                    isGraphReference: false,
                    isFramebufferInput: true,
                    content: .color(.resolved(.premultipliedAlpha))
                )
            case let .system(name):
                guard let purpose = resolvedPurpose ?? SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler),
                      case let .ready(publication)? = systemProviderStates[
                          .init(name: name, purpose: purpose)
                      ], publication.requestIdentity == .system(.init(name: name, purpose: purpose)),
                      publication.isComplete, publication.generationIsCurrent,
                      publication.candidate.purpose == purpose else { return nil }
                return .init(
                    isGraphReference: false, isFramebufferInput: false,
                    content: publication.candidate.content
                )
            }
        }
        guard let purpose = resolvedPurpose
                ?? SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: sampler) else { return nil }
        if case let .asset(path) = reference {
            let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
            let content: SceneTextureContent
            switch assetStates[identity] {
            case let .ready(value)?, let .preparedVideo(value)?:
                // A provider contract, like a prepared scene-background input.
                // Runtime finalization still requires a complete decoded frame.
                content = value
            default: return nil
            }
            return .init(
                isGraphReference: false,
                isFramebufferInput: false,
                content: content
            )
        }
        return nil
    }

}
