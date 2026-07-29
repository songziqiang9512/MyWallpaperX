import Foundation

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func irisInlineSuffix(
        plannedStages: [SceneAuthoredEffectExecutionPlan],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        guard !plannedStages.isEmpty,
              unsupportedOrdinal == graph.effects.count - 1,
              plannedStages.count == unsupportedOrdinal,
              let effect = graph.effects.last,
              let stageGraph = stageGraph(effect: effect, in: graph),
              let suffix = SceneAuthoredIrisInlineSuffixPlanner.plan(
                  graph: stageGraph,
                  descriptor: descriptor,
                  shaderContracts: shaderContracts,
                  inputRole: .priorEffectOutput
              ),
              let finalStage = plannedStages.last else {
            return nil
        }
        let includedEffects = Set(plannedStages.compactMap {
            $0.renderGraph.effects.first?.key
        })
        let prefixGraph = Graph(
            layerID: graph.layerID,
            effects: graph.effects.filter { includedEffects.contains($0.key) },
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect.map(includedEffects.contains) == true
            },
            nodes: graph.nodes.filter { includedEffects.contains($0.effect) },
            finalOutput: finalStage.renderGraph.finalOutput,
            blockers: []
        )
#if DEBUG
        print(
            "MWX authored effect chain using Iris inline suffix "
                + "layer=\(graph.layerID) effect=\(effect.definitionPath)"
        )
#endif
        return SceneAuthoredEffectExecutionChain(
            layerID: graph.layerID,
            renderGraph: prefixGraph,
            stages: plannedStages,
            irisInlineSuffix: suffix
        )
    }
}
