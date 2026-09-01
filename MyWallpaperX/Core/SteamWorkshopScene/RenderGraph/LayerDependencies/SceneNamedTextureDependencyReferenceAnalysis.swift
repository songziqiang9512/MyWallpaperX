import Foundation

/// Loss-preserving named-texture references shared by dependency planning and
/// owner admission. A layer participating on either side of one of these
/// references already belongs to the graph target/publication lifecycle.
nonisolated enum SceneNamedTextureDependencyReferenceAnalysis {
    nonisolated struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    nonisolated static func references(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [Reference] {
        references(in: layers) { slotIndex, pass in
            !hasUserTexture(slotIndex: slotIndex, pass: pass)
        }
    }

    /// A typed system or user-property texture may explicitly publish
    /// `absent`, allowing the frame selector to continue to a lower authored
    /// named target. These references are only admission candidates: they
    /// acquire capture/publication authority after an exact MaterialProgram
    /// variant proves the mixed slot.
    nonisolated static func potentialOptionalNamedFallbackReferences(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [Reference] {
        references(in: layers) { slotIndex, pass in
            hasOptionalUserTexture(slotIndex: slotIndex, pass: pass)
        }
    }

    private nonisolated static func references(
        in layers: [SceneRenderDescriptor.Layer],
        acceptsSlot: (
            Int,
            SceneRenderDescriptor.EffectDescriptor.PassDescriptor
        ) -> Bool
    ) -> [Reference] {
        layers.flatMap { layer in
            layer.effects.filter { $0.visible != false }.flatMap { effect in
                effect.passes.flatMap { pass in
                    pass.textureSlots.enumerated().compactMap { slotIndex, path in
                        guard acceptsSlot(slotIndex, pass),
                              let reference = SceneNamedTextureReference.parse(path)
                        else {
                            return nil
                        }
                        return Reference(
                            consumerLayerID: layer.id,
                            providerLayerID: reference.providerLayerID,
                            slot: SceneEffectPassSlot(
                                effectID: effect.id,
                                passIndex: pass.passIndex,
                                slotIndex: slotIndex
                            ),
                            variant: reference.variant
                        )
                    }
                }
            }
        }
    }

    nonisolated static func participatingLayerIDs(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> Set<Int> {
        references(in: layers).reduce(into: Set<Int>()) { result, reference in
            result.insert(reference.consumerLayerID)
            result.insert(reference.providerLayerID)
        }
    }

    /// An exact typed optional producer may publish `absent`, which authorizes
    /// the shared frame selector to continue to a lower authored named target.
    /// Path and unknown user-texture kinds retain terminal-shadowing behavior.
    nonisolated static func userTextureAllowsNamedFallback(
        slotIndex: Int,
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        guard pass.userTextureInputs.indices.contains(slotIndex),
              let input = pass.userTextureInputs[slotIndex] else { return true }
        return [.system, .property].contains(input.kind) && !input.value.isEmpty
    }

    private nonisolated static func hasUserTexture(
        slotIndex: Int,
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        pass.userTextureInputs.indices.contains(slotIndex)
            && pass.userTextureInputs[slotIndex] != nil
    }

    /// Descriptor-only potential used while compiling MaterialProgram
    /// ownership. It must never by itself grant runtime capture or block a
    /// safe layer-source passthrough; the runtime plan intersects it with the
    /// admitted external-primary capability set.
    nonisolated static func hasOptionalUserTexture(
        slotIndex: Int,
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        guard pass.userTextureInputs.indices.contains(slotIndex),
              let input = pass.userTextureInputs[slotIndex] else { return false }
        return [.system, .property].contains(input.kind) && !input.value.isEmpty
    }
}
