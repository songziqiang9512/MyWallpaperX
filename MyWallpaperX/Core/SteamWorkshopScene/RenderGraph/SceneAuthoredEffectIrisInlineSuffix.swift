import Foundation

extension SceneAuthoredEffectChainPlanner {
    nonisolated static func irisInlineSuffix(
        plannedPrograms: [SceneEffectStageProgram],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        guard !plannedPrograms.isEmpty,
              unsupportedOrdinal == graph.effects.count - 1,
              plannedPrograms.count == unsupportedOrdinal,
              let effect = graph.effects.last,
              let stageGraph = stageGraph(effect: effect, in: graph),
              let suffix = SceneAuthoredIrisInlineSuffixPlanner.plan(
                  graph: stageGraph,
                  descriptor: descriptor,
                  shaderContracts: shaderContracts,
                  inputRole: .priorEffectOutput
              ),
              let finalStage = plannedPrograms.last?.executionPlan else {
            return nil
        }
        let includedEffects = Set(plannedPrograms.compactMap {
            $0.executionPlan.renderGraph.effects.first?.key
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
        return SceneAuthoredEffectExecutionChain.legacyRecovery(
            layerID: graph.layerID,
            authoredRenderGraph: graph,
            renderGraph: prefixGraph,
            stagePrograms: plannedPrograms,
            kind: .terminalIrisInlineSuffix,
            irisInlineSuffix: suffix
        )
    }
}
