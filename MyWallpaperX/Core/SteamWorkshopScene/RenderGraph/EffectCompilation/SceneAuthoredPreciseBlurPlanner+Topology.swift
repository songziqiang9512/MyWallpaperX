import Foundation

extension SceneEffectStageExecutionPlanner {
    nonisolated enum PreciseBlurTopology: Equatable {
        case authoredIntermediate(horizontal: Graph.TextureIdentity, vertical: Graph.TextureIdentity)
        case fullFrameCompose

        nonisolated var usesFullFrameCompose: Bool {
            if case .fullFrameCompose = self { return true }
            return false
        }
    }

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

    nonisolated static func preciseBlurTopology(
        horizontalNode: Graph.Node,
        verticalNode: Graph.Node,
        effect: Graph.Effect,
        commandNodeCount: Int
    ) -> PreciseBlurTopology? {
        if commandNodeCount == 0,
           horizontalNode.target == effect.output,
           horizontalNode.bindings.isEmpty,
           horizontalNode.compose == .bool(true),
           verticalNode.target == effect.output,
           verticalNode.bindings.isEmpty,
           verticalNode.compose == nil {
            return .fullFrameCompose
        }
        guard horizontalNode.compose == nil,
              verticalNode.compose == nil,
              horizontalNode.bindings.isEmpty,
              verticalNode.bindings.count == 2,
              binding(verticalNode.bindings, slot: 1)?.texture == effect.input,
              let horizontalTarget = horizontalNode.target,
              let verticalInput = binding(verticalNode.bindings, slot: 0)?.texture else {
            return nil
        }
        return .authoredIntermediate(
            horizontal: horizontalTarget,
            vertical: verticalInput
        )
    }

    nonisolated static func validMaterialSlots(
        horizontal: SceneResolvedMaterialNode,
        vertical: SceneResolvedMaterialNode,
        effectInput: Graph.TextureIdentity,
        topology: PreciseBlurTopology
    ) -> Bool {
        switch topology {
        case .fullFrameCompose:
            return horizontal.textureSlots.allSatisfy { $0 == nil }
                && vertical.textureSlots.allSatisfy { $0 == nil }
        case .authoredIntermediate(_, let verticalInput):
            return horizontal.textureSlots.allSatisfy { $0 == nil }
                && graphSlot(vertical.textureSlots[0]) == verticalInput
                && graphSlot(vertical.textureSlots[1]) == effectInput
                && vertical.textureSlots.dropFirst(2).allSatisfy { $0 == nil }
        }
    }

    nonisolated static func validNode(
        _ node: Graph.Node,
        ordinal: Int,
        effect: Graph.EffectKey
    ) -> Bool {
        node.kind == .material
            && node.effect == effect
            && node.materialOrdinal == ordinal
            && node.conditions == nil
            && node.commandSource == nil
            && node.commandTarget == nil
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
