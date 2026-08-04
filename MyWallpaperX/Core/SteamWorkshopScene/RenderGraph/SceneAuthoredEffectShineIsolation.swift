import Foundation

extension SceneAuthoredEffectChainPlanner {
    /// A validated static Shine stage can still be useful when unrelated siblings
    /// are unsupported or the complete chain exceeds the default texture budget.
    /// Rebase only one unambiguous stage and report every omitted sibling.
    nonisolated static func isolatedShineChain(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        let eligible = graph.effects.enumerated().compactMap {
            candidate -> (offset: Int, graph: Graph, plan: SceneShineExecutionPlan)? in
            guard SceneAuthoredShinePlanner.normalized(candidate.element.definitionPath)
                    == SceneAuthoredShinePlanner.definitionPath,
                  let stageGraph = stageGraph(effect: candidate.element, in: graph),
                  let plan = SceneAuthoredShinePlanner.plan(
                      graph: stageGraph,
                      descriptor: descriptor,
                      shaderContracts: shaderContracts,
                      inputRole: candidate.offset == 0 ? .layerSource : .priorEffectOutput
                  )
            else {
                return nil
            }
            return (candidate.offset, stageGraph, plan)
        }
        guard eligible.count == 1, let candidate = eligible.first,
              let rebasedGraph = rebaseStageToLayerSource(candidate.graph),
              let rebasedPlan = candidate.plan.rebased(renderGraph: rebasedGraph)
        else {
            return nil
        }

        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: rebasedGraph,
            backend: .shine(rebasedPlan),
            materialNodeCount: 5,
            logicalRenderTargetCount: 2,
            inputRole: .layerSource
        )
        guard fitsDefaultTextureBudget([stage]) else { return nil }
        let omitted = graph.effects.enumerated().compactMap {
            $0.offset == candidate.offset ? nil : $0.element.definitionPath
        }
        return SceneAuthoredEffectExecutionChain.legacyRecovery(
            layerID: graph.layerID,
            authoredRenderGraph: graph,
            renderGraph: rebasedGraph,
            legacyRecoveryStages: [stage],
            kind: .isolatedShine,
            omittedEffectPaths: omitted
        )
    }
}

private extension SceneShineExecutionPlan {
    nonisolated func rebased(
        renderGraph: SceneAuthoredEffectRenderPlan
    ) -> SceneShineExecutionPlan? {
        guard renderGraph.effects.first?.key == effectKey else { return nil }
        return SceneShineExecutionPlan(
            layerID: layerID,
            effectKey: effectKey,
            renderGraph: renderGraph,
            firstHalfTarget: firstHalfTarget,
            secondHalfTarget: secondHalfTarget,
            threshold: threshold,
            noiseAmount: noiseAmount,
            noiseScale: noiseScale,
            noiseSpeed: noiseSpeed,
            maskTexturePath: maskTexturePath,
            noiseTexturePath: noiseTexturePath,
            edgeCount: edgeCount,
            sampleCount: sampleCount,
            direction: direction,
            rotationSpeed: rotationSpeed,
            rayLength: rayLength,
            rayIntensity: rayIntensity,
            rayColor: rayColor,
            kernelRadius: kernelRadius,
            blurScaleX: blurScaleX,
            blurScaleY: blurScaleY,
            blendMode: blendMode
        )
    }
}
