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
    /// This launch decision proves graph shape only. The renderer separately
    /// admits native solid geometry and its actual terminal attachment.
    static func supportsTerminalReplay(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability],
        materials: [SceneResolvedMaterialExecutionCapabilityCatalog.MaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?
    ) -> Bool {
        guard admitted.isVisibleExecutionRoot,
              !admitted.isGraphOutputProvider,
              !admitted.requiresGraphOutputProvider,
              case .capturedLayerTexture = admitted.sourceRoute,
              case .none = dependencyOwnership,
              sceneBackgroundRequirement == nil,
              stages.count == 1,
              case let .resolved(product, _, _) = stages[0],
              product.clearFunctions.functions.isEmpty,
              product.graph.renderTargets.isEmpty,
              product.graph.effects.count == 1,
              product.graph.nodes.count == 1,
              let node = product.graph.nodes.first,
              node.kind == .material,
              node.target == product.graph.effects[0].output,
              node.compose == nil,
              materials.count == 1,
              let material = materials.values.first,
              material.attachmentStorage == .color else { return false }
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        return snapshot.allEntriesReady && !snapshot.variants.isEmpty
            && snapshot.variants.allSatisfy { variant in
                variant.frontendProgram.supportsTerminalMaterialReplay
            }
    }
}
