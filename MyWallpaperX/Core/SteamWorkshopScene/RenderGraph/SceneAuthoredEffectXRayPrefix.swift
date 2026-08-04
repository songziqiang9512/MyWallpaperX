import Foundation

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func xRayPrefix(
        plannedPrograms: [SceneEffectStageProgram],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> SceneAuthoredEffectExecutionChain? {
        guard unsupportedOrdinal == 1,
              graph.effects.count > unsupportedOrdinal,
              plannedPrograms.count == 1,
              let stage = plannedPrograms.first?.executionPlan,
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
        return SceneAuthoredEffectExecutionChain.legacyRecovery(
            layerID: graph.layerID,
            authoredRenderGraph: graph,
            renderGraph: stage.renderGraph,
            stagePrograms: plannedPrograms,
            kind: .xRayPrefix
        )
    }
}
