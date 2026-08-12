import Foundation

extension SceneEffectProgramCompiler {
    nonisolated static func stageGraph(
        effect: Graph.Effect,
        in graph: Graph
    ) -> Graph? {
        let nodesByIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        var nodes: [Graph.Node] = []
        nodes.reserveCapacity(effect.nodeIndices.count)
        for nodeIndex in effect.nodeIndices {
            let matches = nodesByIndex[nodeIndex] ?? []
            guard matches.count == 1,
                  let node = matches.first,
                  node.effect == effect.key else {
                return nil
            }
            nodes.append(node)
        }
        return Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: nodes,
            finalOutput: effect.output,
            blockers: []
        )
    }
}
