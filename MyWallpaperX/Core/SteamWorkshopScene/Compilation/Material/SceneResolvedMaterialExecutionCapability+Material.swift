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
    static func solidEffectSizingCapabilities(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability],
        materials: [SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?
    ) -> (intermediates: Bool, terminal: Bool) {
        guard admitted.isVisibleExecutionRoot,
              !admitted.isGraphOutputProvider,
              !admitted.requiresGraphOutputProvider,
              case .capturedLayerTexture = admitted.sourceRoute,
              sceneBackgroundRequirement == nil,
              !stages.isEmpty, !materials.isEmpty else { return (false, false) }
        // An admitted raster dependency is a frozen read-only input, just
        // like a static texture. Its publication keeps its own real extent.
        // Special geometry and aggregate ownership retain their existing route.
        switch dependencyOwnership {
        case .none:
            break
        case let .externalPrimary(binding):
            guard binding.kind != .geometryLayer, binding.blendMode == 0 else {
                return (false, false)
            }
        case .graphInternal, .externalAggregate:
            return (false, false)
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
                  node.compose == nil else { return (false, false) }
        }
        guard materials.values.allSatisfy({ $0.attachmentStorage == .color }) else {
            return (false, false)
        }
        func supportsReplay(_ material: SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability) -> Bool {
            let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
            return snapshot.allEntriesReady && !snapshot.variants.isEmpty
                && snapshot.variants.allSatisfy {
                    $0.frontendProgram.supportsTerminalMaterialReplay
                }
        }
        // Advanced blending retains its existing source-sized eligibility.
        // Only normal source-over can replay an earlier surviving material.
        let lastEffect = stages.last?.product.graph.effects.first?.key
        let lastMaterial = materials.values.first { $0.key.effect == lastEffect }
        let intermediates = materials.count == stages.count && stages.allSatisfy {
            if case .resolved = $0 { return true }; return false
        } && lastMaterial.map(supportsReplay) == true
        return (intermediates, materials.values.allSatisfy(supportsReplay))
    }
}
