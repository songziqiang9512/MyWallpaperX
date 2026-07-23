import Foundation

extension SceneAuthoredEffectExecutionPlanner {
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
        target.texture.kind == .framebuffer
            && target.texture.effect == effect
            && target.extent.kind == .input
            && target.extent.first == nil
            && target.extent.second == nil
            && target.format?.lowercased() == "rgba_backbuffer"
            && target.clear == nil
            && target.uvs == nil
            && target.conditions == nil
    }
}
