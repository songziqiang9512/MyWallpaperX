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
        layers.flatMap { layer in
            layer.effects.filter { $0.visible != false }.flatMap { effect in
                effect.passes.flatMap { pass in
                    pass.textureSlots.enumerated().compactMap { slotIndex, path in
                        guard !isShadowedByUserTexture(
                            slotIndex: slotIndex,
                            pass: pass
                        ), let reference = SceneNamedTextureReference.parse(path) else {
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

    /// Instance user textures are appended after instance asset paths by the
    /// shared material resolver. A named path at the same slot remains
    /// provenance, but it is not the selected cross-layer execution input.
    private nonisolated static func isShadowedByUserTexture(
        slotIndex: Int,
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        pass.userTextureInputs.indices.contains(slotIndex)
            && pass.userTextureInputs[slotIndex] != nil
    }
}
