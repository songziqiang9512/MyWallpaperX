import Foundation

extension SceneAuthoredEffectExecutionPlanner {
    nonisolated static func binding(
        _ bindings: [Graph.Binding],
        slot: Int
    ) -> Graph.Binding? {
        let matches = bindings.filter { $0.slot == slot }
        return matches.count == 1 ? matches[0] : nil
    }

    nonisolated static func graphSlot(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> Graph.TextureIdentity? {
        guard let slot, case .graph(let texture) = slot.source else { return nil }
        return texture
    }

    nonisolated static func preciseBlurBindingProfile(
        horizontalNode: Graph.Node,
        verticalNode: Graph.Node,
        effect: Graph.Effect
    ) -> Bool? {
        let intermediate = binding(verticalNode.bindings, slot: 0)?.texture
        guard intermediate != nil else { return nil }
        if horizontalNode.bindings.isEmpty,
           verticalNode.bindings.count == 2,
           binding(verticalNode.bindings, slot: 1)?.texture == effect.input {
            return false
        }
        if horizontalNode.bindings.count == 1,
           binding(horizontalNode.bindings, slot: 0)?.texture == effect.input,
           verticalNode.bindings.count == 1 {
            return true
        }
        return nil
    }

    nonisolated static func validMaterialSlots(
        horizontal: SceneResolvedMaterialNode,
        vertical: SceneResolvedMaterialNode,
        effectInput: Graph.TextureIdentity,
        intermediate: Graph.TextureIdentity,
        legacyCompose: Bool
    ) -> Bool {
        guard graphSlot(vertical.textureSlots[0]) == intermediate else { return false }
        if legacyCompose {
            return graphSlot(horizontal.textureSlots[0]) == effectInput
                && horizontal.textureSlots.dropFirst().allSatisfy { $0 == nil }
                && vertical.textureSlots.dropFirst().allSatisfy { $0 == nil }
        }
        return horizontal.textureSlots.allSatisfy { $0 == nil }
            && graphSlot(vertical.textureSlots[1]) == effectInput
            && vertical.textureSlots.dropFirst(2).allSatisfy { $0 == nil }
    }

    nonisolated static func validCommandNode(
        _ node: Graph.Node,
        effect: Graph.EffectKey
    ) -> Bool {
        (node.kind == .copy || node.kind == .swap)
            && node.effect == effect
            && node.materialOrdinal == nil
            && node.instancePassIndex == nil
            && node.materialPath == nil
            && node.materialPassID == nil
            && node.target == nil
            && node.bindings.isEmpty
            && node.commandSource != nil
            && node.commandTarget != nil
            && node.compose == nil
            && node.conditions == nil
    }

    nonisolated static func validTarget(
        _ target: Graph.RenderTarget,
        effect: Graph.EffectKey
    ) -> Bool {
        let extentIsInput = target.extent.kind == .input
            && target.extent.first == nil
            && target.extent.second == nil
        let extentIsFullScale = target.extent.kind == .scale
            && target.extent.first == 1
            && target.extent.second == nil
        return target.texture.kind == .framebuffer
            && target.texture.effect == effect
            && (extentIsInput || extentIsFullScale)
            && target.format?.lowercased() == "rgba_backbuffer"
            && target.clear == nil
            && target.uvs == nil
            && target.conditions == nil
    }
}

extension SceneAuthoredEffectExecutionPlan {
    nonisolated func acceptsPreciseBlurHorizontalBindings(
        _ bindings: [SceneAuthoredEffectRenderPlan.Binding],
        effectInput: SceneAuthoredEffectRenderPlan.TextureIdentity
    ) -> Bool {
        if usesLegacyComposeNormalization {
            return bindings.count == 1
                && bindings.first?.slot == 0
                && bindings.first?.texture == effectInput
        }
        return bindings.isEmpty
    }
}
