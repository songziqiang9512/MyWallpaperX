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
              let rebasedGraph = rebaseToLayerSource(originalStageGraph),
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
        return SceneAuthoredEffectExecutionChain(
            layerID: graph.layerID,
            renderGraph: rebasedGraph,
            stages: [stage],
            isolatedCursorRippleOmittedEffectPaths: omitted
        )
    }

    private nonisolated static func rebaseToLayerSource(_ graph: Graph) -> Graph? {
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
        guard replacedPreviousBindings == 1 else { return nil }
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
            maskTexturePath: maskTexturePath
        )
    }
}
