import Foundation

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func xRayPrefix(
        plannedStages: [SceneAuthoredEffectExecutionPlan],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> SceneAuthoredEffectExecutionChain? {
        guard unsupportedOrdinal == 1,
              graph.effects.count > unsupportedOrdinal,
              plannedStages.count == 1,
              let stage = plannedStages.first,
              stage.xRay != nil,
              stage.inputRole == .layerSource,
              descriptor.layers.first(where: { $0.id == graph.layerID })?.contentKind
                == "composition" else {
            return nil
        }
#if DEBUG
        let omitted = graph.effects.dropFirst().map(\.definitionPath).joined(separator: ",")
        print(
            "MWX authored effect chain using X-Ray prefix layer=\(graph.layerID) "
                + "omitted=\(omitted)"
        )
#endif
        return SceneAuthoredEffectExecutionChain(
            layerID: graph.layerID,
            renderGraph: stage.renderGraph,
            stages: plannedStages
        )
    }
}
