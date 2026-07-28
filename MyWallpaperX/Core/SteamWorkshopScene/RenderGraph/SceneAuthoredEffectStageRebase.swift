import Foundation

extension SceneAuthoredEffectChainPlanner {
    /// Rebase one already validated stage from its prior chain output to the
    /// layer source. Some effects sample `previous` more than once, so every
    /// binding to the authored input must move together.
    nonisolated static func rebaseStageToLayerSource(_ graph: Graph) -> Graph? {
        guard graph.effects.count == 1, let effect = graph.effects.first else { return nil }
        let layerSource = SceneAuthoredEffectInputValidator.layerSource(layerID: graph.layerID)
        var replacedPreviousBindings = 0
        let nodes = graph.nodes.map { node in
            let bindings = node.bindings.map { binding in
                guard binding.texture == effect.input else { return binding }
                replacedPreviousBindings += 1
                return Graph.Binding(
                    slot: binding.slot,
                    authoredName: binding.authoredName,
                    texture: layerSource,
                    conditions: binding.conditions
                )
            }
            return Graph.Node(
                nodeIndex: node.nodeIndex,
                effect: node.effect,
                definitionPassIndex: node.definitionPassIndex,
                materialOrdinal: node.materialOrdinal,
                instancePassIndex: node.instancePassIndex,
                kind: node.kind,
                materialPath: node.materialPath,
                materialPassID: node.materialPassID,
                target: node.target,
                bindings: bindings,
                commandSource: node.commandSource,
                commandTarget: node.commandTarget,
                compose: node.compose,
                conditions: node.conditions
            )
        }
        guard replacedPreviousBindings > 0 else { return nil }
        let rebasedEffect = Graph.Effect(
            key: effect.key,
            definitionPath: effect.definitionPath,
            input: layerSource,
            output: effect.output,
            nodeIndices: effect.nodeIndices
        )
        return Graph(
            layerID: graph.layerID,
            effects: [rebasedEffect],
            renderTargets: graph.renderTargets,
            nodes: nodes,
            finalOutput: effect.output,
            blockers: []
        )
    }
}
