import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    final class MaterialCapability {
        let key: MaterialKey
        let template: Template
        let variants: SceneResolvedMaterialVariantCache
        let attachmentStorage: SceneResolvedMaterialAttachmentKind
        let targetFormat: SceneGraphRenderTargetPlan.TextureFormat

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
        }
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability {
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
              !admitted.requiresGraphOutputProvider,
              case .capturedLayerTexture = admitted.sourceRoute,
              sceneBackgroundRequirement == nil,
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
        for stage in stages {
            let product = stage.product
            guard product.clearFunctions.functions.isEmpty,
                  product.graph.renderTargets.isEmpty,
                  product.graph.effects.count == 1,
                  product.graph.nodes.count == 1,
                  let node = product.graph.nodes.first,
                  node.kind == .material,
                  node.target == product.graph.effects[0].output,
                  node.compose == nil else { return (false, false, false) }
        }
        guard materials.values.allSatisfy({ $0.attachmentStorage == .color }) else {
            return (false, false, false)
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
            if case .resolved = $0 { return true }; return false
        } && lastMaterial.flatMap { replay[$0]?.terminal } == true
        return (intermediates, replay.values.allSatisfy(\.terminal),
                replay.values.allSatisfy(\.placement))
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
              !admitted.requiresGraphOutputProvider,
              admitted.sourceRoute == .capturedMainTargetTexture,
              admitted.terminalReplayBlendMode == 0,
              dependencyOwnership == .none, sceneBackgroundRequirement == nil,
              stages.count == 1, materials.count == 1,
              case let .resolved(product, _, _) = stages[0],
              product.clearFunctions.functions.isEmpty,
              product.graph.renderTargets.isEmpty,
              product.graph.effects.count == 1,
              product.graph.nodes.count == 1,
              let node = product.graph.nodes.first,
              node.kind == .material, node.compose == nil,
              node.target == product.graph.effects[0].output,
              let material = materials.values.first,
              material.attachmentStorage == .color,
              material.template.graphRole.effectInput == .layerSource,
              material.variants.capturedMainTargetSourceSlot(
                  node: node, effect: product.graph.effects[0]) == 0 else { return false }
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        return snapshot.allEntriesReady && !snapshot.variants.isEmpty
            && snapshot.variants.allSatisfy {
                $0.frontendProgram.supportsTerminalMaterialReplay
                    && $0.frontendProgram.attachmentReadVariant != nil
            }
    }
}
