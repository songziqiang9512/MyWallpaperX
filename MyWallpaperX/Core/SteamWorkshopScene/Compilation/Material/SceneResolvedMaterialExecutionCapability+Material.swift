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
    /// Direct terminal replay remains single-stage: trailing passthroughs can
    /// overwrite an earlier material's input member before the compositor runs.
    static func supportsSourceSizedSolidEffects(
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
              !stages.isEmpty,
              materials.count == stages.count else { return false }
        for stage in stages {
            guard case let .resolved(product, _, _) = stage,
                  product.clearFunctions.functions.isEmpty,
                  product.graph.renderTargets.isEmpty,
                  product.graph.effects.count == 1,
                  product.graph.nodes.count == 1,
                  let node = product.graph.nodes.first,
                  node.kind == .material,
                  node.target == product.graph.effects[0].output,
                  node.compose == nil else { return false }
        }
        guard materials.values.allSatisfy({ $0.attachmentStorage == .color }),
              let lastEffect = stages.last?.product.graph.effects.first?.key,
              let material = materials.values.first(where: {
                  $0.key.effect == lastEffect
              }) else { return false }
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        return snapshot.allEntriesReady && !snapshot.variants.isEmpty
            && snapshot.variants.allSatisfy { variant in
                variant.frontendProgram.supportsTerminalMaterialReplay
            }
    }
}
