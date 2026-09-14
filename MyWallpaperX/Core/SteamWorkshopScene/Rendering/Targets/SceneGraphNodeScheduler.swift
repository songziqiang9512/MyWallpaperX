import Metal

enum SceneGraphNodeScheduler {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Failure: String, Error {
        case invalidTopology
        case commandRuntimeUnavailable
        case materialEncodingFailed
        case commandEncodingFailed
        case incompleteCommandSequence
    }

    static func encode(
        graph: Graph,
        targets: SceneGraphRenderTargetTable,
        commandBuffer: MTLCommandBuffer,
        materialEncoder: (Graph.Node, SceneGraphCommandRuntime) -> Bool
    ) -> Result<Void, Failure> {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              let effect = graph.effects.first,
              graph.layerID == targets.plan.layerID,
              effect.input == targets.plan.input,
              effect.output == targets.plan.output,
              graph.finalOutput == effect.output,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              graph.nodes.allSatisfy({ $0.effect == effect.key }),
              zip(graph.nodes, graph.nodes.dropFirst()).allSatisfy({
                  $0.nodeIndex < $1.nodeIndex
              }) else {
            return .failure(.invalidTopology)
        }
        guard var runtime = targets.makeCommandRuntime() else {
            return .failure(.commandRuntimeUnavailable)
        }

        for node in graph.nodes {
            switch node.kind {
            case .material:
                guard materialEncoder(node, runtime) else {
                    return .failure(.materialEncodingFailed)
                }
            case .copy, .swap:
                guard case .success = runtime.encodeCommand(
                    at: node.nodeIndex,
                    commandBuffer: commandBuffer
                ) else {
                    return .failure(.commandEncodingFailed)
                }
            case .unknownCommand:
                return .failure(.invalidTopology)
            }
        }
        guard runtime.isComplete else {
            return .failure(.incompleteCommandSequence)
        }
        return .success(())
    }
}
