import Foundation

nonisolated struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stages: [SceneAuthoredEffectExecutionPlan]

    var singleStage: SceneAuthoredEffectExecutionPlan? {
        stages.count == 1 ? stages[0] : nil
    }

    var materialNodeCount: Int {
        stages.reduce(0) { $0 + $1.materialNodeCount }
    }

    var logicalRenderTargetCount: Int {
        stages.reduce(0) { $0 + $1.logicalRenderTargetCount }
    }

    var localContrastCount: Int {
        stages.filter { $0.localContrast != nil }.count
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(stages.compactMap(\.liveConsumerTarget))
    }
}

enum SceneAuthoredEffectChainPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        guard graph.blockers.isEmpty,
              !graph.effects.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              validOuterChain(graph) else {
            return nil
        }

        var stages: [SceneAuthoredEffectExecutionPlan] = []
        stages.reserveCapacity(graph.effects.count)
        for (ordinal, effect) in graph.effects.enumerated() {
            guard let stageGraph = stageGraph(effect: effect, in: graph) else { return nil }
            let inputRole: SceneAuthoredEffectInputRole = ordinal == 0
                ? .layerSource
                : .priorEffectOutput
            let localContrast = SceneAuthoredLocalContrastPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let stage = SceneAuthoredEffectExecutionPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                inputRole: inputRole
            ) ?? SceneAuthoredStandardBlurPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                inputRole: inputRole
            ) ?? localContrast.map {
                SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .localContrast($0),
                    materialNodeCount: 4,
                    logicalRenderTargetCount: 2,
                    inputRole: inputRole
                )
            }
            guard let stage else { return nil }
            stages.append(stage)
        }

        return SceneAuthoredEffectExecutionChain(
            layerID: graph.layerID,
            renderGraph: graph,
            stages: stages
        )
    }

    private nonisolated static func validOuterChain(_ graph: Graph) -> Bool {
        let layerSource = SceneAuthoredEffectInputValidator.layerSource(layerID: graph.layerID)
        var expectedInput = layerSource
        var seenEffects = Set<Graph.EffectKey>()
        var seenNodeIndices = Set<Int>()
        var lastEffectIndex: Int?

        for effect in graph.effects {
            guard effect.key.layerID == graph.layerID,
                  effect.key.effectIndex >= 0,
                  !effect.key.descriptorID.isEmpty,
                  seenEffects.insert(effect.key).inserted,
                  lastEffectIndex.map({ effect.key.effectIndex > $0 }) ?? true,
                  effect.input == expectedInput,
                  validOutput(effect.output, effect: effect.key, layerID: graph.layerID),
                  !effect.nodeIndices.isEmpty,
                  effect.nodeIndices.allSatisfy({ seenNodeIndices.insert($0).inserted }) else {
                return false
            }
            expectedInput = effect.output
            lastEffectIndex = effect.key.effectIndex
        }

        guard graph.finalOutput == expectedInput,
              seenNodeIndices == Set(graph.nodes.map(\.nodeIndex)),
              graph.nodes.allSatisfy({ seenEffects.contains($0.effect) }),
              graph.renderTargets.allSatisfy({
                  $0.texture.effect.map(seenEffects.contains) == true
              }) else {
            return false
        }
        return true
    }

    private nonisolated static func stageGraph(
        effect: Graph.Effect,
        in graph: Graph
    ) -> Graph? {
        let nodesByIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        var nodes: [Graph.Node] = []
        nodes.reserveCapacity(effect.nodeIndices.count)
        for nodeIndex in effect.nodeIndices {
            guard let matches = nodesByIndex[nodeIndex], matches.count == 1,
                  let node = matches.first, node.effect == effect.key else {
                return nil
            }
            nodes.append(node)
        }
        let targets = graph.renderTargets.filter { $0.texture.effect == effect.key }
        return Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: effect.output,
            blockers: []
        )
    }

    private nonisolated static func validOutput(
        _ output: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        output.kind == .effectOutput
            && output.layerID == layerID
            && output.effect == effect
            && output.name == nil
    }
}
