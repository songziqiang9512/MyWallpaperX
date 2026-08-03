import Foundation

nonisolated enum SceneAuthoredEffectStageGraphAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    case accepted(Graph)
    case rejected(SceneAuthoredEffectChainRejection)

    var graph: Graph? {
        guard case .accepted(let graph) = self else { return nil }
        return graph
    }
}

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func stageGraphAdmission(
        effect: Graph.Effect,
        in graph: Graph
    ) -> SceneAuthoredEffectStageGraphAdmission {
        let nodesByIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        var nodes: [Graph.Node] = []
        nodes.reserveCapacity(effect.nodeIndices.count)
        for nodeIndex in effect.nodeIndices {
            let matches = nodesByIndex[nodeIndex] ?? []
            guard matches.count == 1, let node = matches.first else {
                return .rejected(.init(
                    code: matches.isEmpty ? .stageNodeMissing : .stageNodeAmbiguous,
                    layerID: graph.layerID,
                    effectKey: effect.key,
                    definitionPath: effect.definitionPath,
                    nodeIndex: nodeIndex,
                    observedCount: matches.count
                ))
            }
            guard node.effect == effect.key else {
                return .rejected(.init(
                    code: .stageNodeEffectMismatch,
                    layerID: graph.layerID,
                    effectKey: effect.key,
                    definitionPath: effect.definitionPath,
                    nodeIndex: nodeIndex
                ))
            }
            nodes.append(node)
        }
        return .accepted(Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: nodes,
            finalOutput: effect.output,
            blockers: []
        ))
    }
}
