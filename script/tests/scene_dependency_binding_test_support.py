"""Shared Swift dependency-binding stub for resolved-material harnesses."""


SCENE_DEPENDENCY_BINDING_SUPPORT = r'''
enum SceneImageLayerBlendDependencyContract {
    static func supports(blendMode: Int) -> Bool {
        (0...32).contains(blendMode)
    }
}

extension SceneDependencyRenderPlan {
    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind
        let requiresResolvedMaterialProgram: Bool

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind,
            requiresResolvedMaterialProgram: Bool = false
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
            self.requiresResolvedMaterialProgram =
                requiresResolvedMaterialProgram
        }
    }
}
'''
