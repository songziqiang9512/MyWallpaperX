extension SceneDependencyRenderPlan {
    /// Generic carrier for one source-proven Program sampler backed by an
    /// earlier visible image layer's graph-final publication. Shader identity,
    /// effect name and scalar values deliberately do not participate here;
    /// MaterialProgram admission owns those contracts after this compiler has
    /// conserved the exact authored primary reference.
    nonisolated static func visibleImageGraphOutputReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        visibleLayerIDs: Set<Int>
    ) -> Reference? {
        guard layer.contentKind == "image",
              hasNoUtilityLayer(layer),
              layer.visible != false,
              visibleLayerIDs.contains(layer.id),
              layer.childLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              references.count == 1,
              let reference = references.first,
              reference.variant == .primary,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 1,
              layer.dependencyLayerIDs == [reference.providerLayerID],
              let provider = layersByID[reference.providerLayerID],
              provider.contentKind == "image",
              hasNoUtilityLayer(provider),
              provider.visible != false,
              visibleLayerIDs.contains(provider.id),
              provider.childLayerIDs.isEmpty,
              provider.authoredDependencies.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              provider.effects.contains(where: { $0.visible != false }) else {
            return nil
        }
        let effects = visibleEffects.filter { $0.id == reference.slot.effectID }
        guard effects.count == 1, let effect = effects.first,
              effect.passes.count == 1 else { return nil }
        let passes = effect.passes.filter {
            $0.passIndex == reference.slot.passIndex
        }
        guard passes.count == 1, let pass = passes.first,
              pass.textureSlots.indices.contains(reference.slot.slotIndex),
              let path = pass.textureSlots[reference.slot.slotIndex],
              SceneNamedTextureReference.parse(path) == .init(
                  providerLayerID: reference.providerLayerID,
                  variant: .primary
              ), (!pass.userTextureInputs.indices.contains(
                  reference.slot.slotIndex
              ) || pass.userTextureInputs[reference.slot.slotIndex] == nil) else {
            return nil
        }
        return reference
    }

    nonisolated static func supportedImageLayerBlendDeclaration(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> SceneImageLayerBlendDependencyDeclaration? {
        let declarations = visibleEffects.compactMap(
            SceneImageLayerBlendDependencyContract.declaration
        )
        return declarations.count == 1 ? declarations[0] : nil
    }

    /// Generic external-primary carrier for one hidden image source consumed
    /// by a single admitted Program sampler. Effect identity and authored
    /// scalar values deliberately do not select this resource route.
    nonisolated static func materialProgramImageLayerReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Reference? {
        guard layer.contentKind == "image",
              hasNoUtilityLayer(layer),
              layer.childLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              references.count == 1,
              let reference = references.first,
              reference.variant == .primary,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 1,
              layer.dependencyLayerIDs == [reference.providerLayerID],
              let provider = layersByID[reference.providerLayerID],
              provider.contentKind == "image",
              hasNoUtilityLayer(provider),
              provider.visible == false,
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              !provider.effects.contains(where: { $0.visible != false }) else {
            return nil
        }
        let effects = visibleEffects.filter { $0.id == reference.slot.effectID }
        guard effects.count == 1, let effect = effects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == reference.slot.passIndex,
              pass.textureSlots.indices.contains(reference.slot.slotIndex),
              let path = pass.textureSlots[reference.slot.slotIndex],
              SceneNamedTextureReference.parse(path) == .init(
                  providerLayerID: reference.providerLayerID,
                  variant: .primary
              ), (!pass.userTextureInputs.indices.contains(
                  reference.slot.slotIndex
              ) || pass.userTextureInputs[reference.slot.slotIndex] == nil)
        else { return nil }
        return reference
    }

    nonisolated static func hasNoUtilityLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if case nil = layer.utilityLayer { return true }
        return false
    }
}
