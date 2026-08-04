import Foundation

extension SceneAuthoredEffectChainPlanner {
    /// Cursor Ripple is interactive and otherwise unreachable in the current corpus
    /// because an unrelated unsupported stage appears before it. Admit only a
    /// fingerprint-validated Ripple stage, explicitly recording every omitted stage.
    nonisolated static func isolatedCursorRippleChain(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        let candidates = graph.effects.enumerated().filter {
            normalized($0.element.definitionPath) == "effects/cursorripple/effect.json"
        }
        guard candidates.count == 1, let candidate = candidates.first,
              let originalStageGraph = stageGraph(effect: candidate.element, in: graph),
              let validated = SceneAuthoredCursorRipplePlanner.plan(
                  graph: originalStageGraph,
                  descriptor: descriptor,
                  shaderContracts: shaderContracts,
                  inputRole: candidate.offset == 0 ? .layerSource : .priorEffectOutput
              ),
              let rebasedGraph = rebaseStageToLayerSource(originalStageGraph),
              let rebasedPlan = validated.rebased(renderGraph: rebasedGraph) else {
            return nil
        }
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: rebasedGraph,
            backend: .cursorRipple(rebasedPlan),
            materialNodeCount: 3,
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
            kind: .isolatedCursorRipple,
            omittedEffectPaths: omitted
        )
    }

    private nonisolated static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

private extension SceneCursorRippleExecutionPlan {
    nonisolated func rebased(
        renderGraph: SceneAuthoredEffectRenderPlan
    ) -> SceneCursorRippleExecutionPlan? {
        guard renderGraph.effects.first?.key == effectKey else { return nil }
        return SceneCursorRippleExecutionPlan(
            layerID: layerID,
            effectKey: effectKey,
            renderGraph: renderGraph,
            simulationResolution: simulationResolution,
            rippleScale: rippleScale,
            decay: decay,
            speed: speed,
            strength: strength,
            maskTexturePath: maskTexturePath,
            renderStates: renderStates
        )
    }
}
