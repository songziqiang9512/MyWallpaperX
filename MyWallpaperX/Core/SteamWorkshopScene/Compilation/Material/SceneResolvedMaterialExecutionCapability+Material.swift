import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    final class MaterialCapability {
        let key: MaterialKey
        let template: Template
        let variants: SceneResolvedMaterialVariantCache
        let attachmentStorage: SceneResolvedMaterialAttachmentKind
        let targetFormat: SceneGraphRenderTargetPlan.TextureFormat
        private let outputStorage: SceneResolvedMaterialProgram.OutputStorage
        let effectLocalFailureSlots: (
            optionalTexture: Set<Int>,
            sceneEnvironment: Set<Int>,
            systemProvider: Set<Int>
        )

        init(
            key: MaterialKey,
            template: Template,
            variants: SceneResolvedMaterialVariantCache,
            attachmentStorage: SceneResolvedMaterialAttachmentKind,
            targetFormat: SceneGraphRenderTargetPlan.TextureFormat
        ) {
            self.key = key
            self.template = template
            self.variants = variants
            self.attachmentStorage = attachmentStorage
            self.targetFormat = targetFormat
            outputStorage = switch attachmentStorage {
            case .color: .color
            case .scalarRedUnorm: .scalarRedUnorm
            case .redGreenUnorm: .redGreenUnorm
            case .scalarRedFloat16: .scalarRedFloat16
            case .redGreenFloat16: .redGreenFloat16
            case .preservedRGBAUnorm: .preservedRGBAUnorm
            }
            effectLocalFailureSlots = (
                Set((0 ..< 8).filter { variants.provesEffectLocalOptionalTextureFailure(slot: $0) }),
                Set((0 ..< 8).filter { variants.provesEffectLocalSceneEnvironmentTextureFailure(slot: $0) }),
                Set((0 ..< 8).filter { variants.provesEffectLocalSystemProviderTextureFailure(slot: $0) })
            )
        }

        func bindFrame(
            _ input: SceneResolvedMaterialFinalizationInput
        ) -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure> {
            return SceneResolvedMaterialProgramFinalizer.finalize(
                input, variantCache: variants, outputStorage: outputStorage
            )
        }
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability {
    private static func terminalColorNode(
        in stage: SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability
    ) -> SceneAuthoredEffectRenderPlan.Node? {
        let product = stage.product
        guard product.clearFunctions.functions.isEmpty,
              product.graph.renderTargets.isEmpty, product.graph.effects.count == 1,
              product.graph.nodes.count == 1, let node = product.graph.nodes.first,
              node.kind == .material, node.target == product.graph.effects[0].output,
              node.compose == nil else { return nil }
        return node
    }

    /// Proves a simple color chain whose intermediates follow its real source.
    /// Every possible terminal has the same proven placement contract;
    /// the graph executor preserves inputs across trailing passthroughs.
    static func simpleColorChainCapabilities(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability],
        materials: [SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?
    ) -> (intermediates: Bool, terminal: Bool, placement: Bool) {
        guard admitted.isVisibleExecutionRoot,
              !admitted.isGraphOutputProvider,
              case .capturedLayerTexture = admitted.sourceRoute,
              !stages.isEmpty, !materials.isEmpty else { return (false, false, false) }
        // An admitted raster dependency is a frozen read-only input, just
        // like a static texture. Its publication keeps its own real extent.
        // Special geometry and aggregate ownership retain their existing route.
        switch dependencyOwnership {
        case .none:
            break
        case let .externalPrimary(binding):
            guard binding.kind != .geometryLayer, binding.blendMode == 0 else {
                return (false, false, false)
            }
        case .graphInternal, .externalAggregate:
            return (false, false, false)
        }
        guard stages.allSatisfy({ terminalColorNode(in: $0) != nil }),
              materials.values.allSatisfy({ $0.attachmentStorage == .color }) else {
            return (false, false, false)
        }
        if let background = sceneBackgroundRequirement {
            guard case .none = dependencyOwnership, !background.capturesTextSourcePrefixRGB else {
                return (false, false, false)
            }
            // The graph can sample the existing main attachment into its
            // local pair. A proved placement tail owns any attachment read.
            let canSizeWork = stages.allSatisfy { stage in
                switch stage.execution {
                case .resolved: true
                case .initiallyInactivePassthrough: stage.supportsEffectEntryPassthrough
                case .visualFailurePassthrough: false
                }
            }
            return (canSizeWork, false, false)
        }
        let replay = materials.mapValues { material in
            let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
            guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
                return (terminal: false, placement: false)
            }
            return (terminal: snapshot.variants.allSatisfy {
                $0.frontendProgram.supportsTerminalMaterialReplay
            }, placement: snapshot.variants.allSatisfy {
                $0.frontendProgram.supportsPlacementSpaceTerminalReplay
            })
        }
        // Source sizing and terminal replay are separate capabilities; the
        // pass role supplies normal or admitted additive final blending.
        let lastEffect = stages.last?.product.graph.effects.first?.key
        let lastMaterial = materials.keys.first { $0.effect == lastEffect }
        let intermediates = materials.count == stages.count && stages.allSatisfy {
            if case .resolved = $0.execution { return true }; return false
        } && lastMaterial.flatMap { replay[$0]?.terminal } == true
        return (intermediates, replay.values.allSatisfy(\.terminal),
                replay.values.allSatisfy(\.placement))
    }

    static func placementTail(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability],
        materials: [SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement: SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?,
        usesSourceSizedEffects: Bool
    ) -> SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey? {
        guard admitted.isVisibleExecutionRoot, !admitted.isGraphOutputProvider, dependencyOwnership == .none,
              stages.count > 1, let stage = stages.last, case .resolved = stage.execution,
              let node = terminalColorNode(in: stage) else { return nil }
        if let background = sceneBackgroundRequirement {
            guard usesSourceSizedEffects, admitted.sourceRoute == .capturedLayerTexture,
                  admitted.terminalReplayBlendMode == 0,
                  background.bindingCount == 1, background.effect == node.effect,
                  background.nodeIndex == node.nodeIndex else { return nil }
        } else {
            guard admitted.isTransparentCompositionRoot, admitted.sourceRoute == .capturedMainTargetTexture,
                  admitted.terminalReplayBlendMode == 0 || admitted.terminalReplayBlendMode == 31
            else { return nil }
        }
        let key = SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey(
            effect: node.effect, nodeIndex: node.nodeIndex)
        guard let material = materials[key], material.attachmentStorage == .color,
              material.template.graphRole.effectInput == .effectOutput
        else { return nil }
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty, snapshot.variants.allSatisfy({ variant in
            guard variant.frontendProgram.supportsPlacementSpaceTerminalReplay else { return false }
            guard let background = sceneBackgroundRequirement else { return true }
            let read = variant.frontendProgram.attachmentReadVariant
            return read?.usesSceneProjection == true && read?.sourceSlot == background.slot
        }) else { return nil }
        return key
    }

    /// One source-preserving material may read the current attachment instead
    /// of resampling a captured background. Earlier active stages cannot be
    /// replaced by the original background, so this cohort has one stage.
    static func backgroundAttachmentReplaySupported(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability],
        materials: [SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement: SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?
    ) -> Bool {
        guard admitted.isVisibleExecutionRoot, !admitted.isGraphOutputProvider,
              admitted.sourceRoute == .capturedMainTargetTexture,
              admitted.terminalReplayBlendMode == 0,
              dependencyOwnership == .none, sceneBackgroundRequirement == nil,
              stages.count == 1, materials.count == 1,
              case .resolved = stages[0].execution,
              let node = terminalColorNode(in: stages[0]),
              let material = materials.values.first,
              material.attachmentStorage == .color,
              material.template.graphRole.effectInput == .layerSource,
              material.variants.capturedMainTargetSourceSlot(
                  node: node, effect: stages[0].product.graph.effects[0]) == 0 else { return false }
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        return snapshot.allEntriesReady && !snapshot.variants.isEmpty
            && snapshot.variants.allSatisfy {
                $0.frontendProgram.supportsTerminalMaterialReplay
                    && $0.frontendProgram.attachmentReadVariant != nil
            }
    }
}
