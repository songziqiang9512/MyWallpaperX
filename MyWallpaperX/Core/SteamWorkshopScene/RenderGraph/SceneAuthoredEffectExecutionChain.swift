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

    var opacityCount: Int {
        stages.filter { $0.opacity != nil }.count
    }

    var workshopShadowCount: Int {
        stages.filter { $0.workshopShadow != nil }.count
    }

    var shakeCount: Int {
        stages.filter { $0.shake != nil }.count
    }

    var waterFlowCount: Int {
        stages.filter { $0.waterFlow != nil }.count
    }

    var waterWavesCount: Int {
        stages.filter { $0.waterWaves != nil }.count
    }

    var foliageSwayCount: Int {
        stages.filter { $0.foliageSway != nil }.count
    }

    var waterRippleCount: Int {
        stages.filter { $0.waterRipple != nil }.count
    }

    var xRayCount: Int {
        stages.filter { $0.xRay != nil }.count
    }

    var tintCount: Int {
        stages.filter { $0.tint != nil }.count
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(stages.flatMap(\.liveConsumerTargets))
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
#if DEBUG
            print("MWX authored effect chain rejected layer=\(graph.layerID) reason=outer-chain")
#endif
            return nil
        }

        var stages: [SceneAuthoredEffectExecutionPlan] = []
        stages.reserveCapacity(graph.effects.count)
        for (ordinal, effect) in graph.effects.enumerated() {
            guard let stageGraph = stageGraph(effect: effect, in: graph) else {
#if DEBUG
                print(
                    "MWX authored effect chain rejected layer=\(graph.layerID) "
                        + "effect=\(effect.definitionPath) index=\(ordinal) reason=stage-graph"
                )
#endif
                return nil
            }
            let inputRole: SceneAuthoredEffectInputRole = ordinal == 0
                ? .layerSource
                : .priorEffectOutput
            let localContrast = SceneAuthoredLocalContrastPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let opacity = SceneAuthoredOpacityPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let workshopShadow = SceneAuthoredWorkshopShadowPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let preciseBlur = SceneAuthoredEffectExecutionPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                inputRole: inputRole
            )
            let standardBlur = SceneAuthoredStandardBlurPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                inputRole: inputRole
            )
            let shake = SceneAuthoredShakePlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let waterFlow = SceneAuthoredWaterFlowPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let waterWaves = SceneAuthoredWaterWavesPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let foliageSway = SceneAuthoredFoliageSwayPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let waterRipple = SceneAuthoredWaterRipplePlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let xRay = SceneAuthoredXRayPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let tint = SceneAuthoredTintPlanner.plan(
                graph: stageGraph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                inputRole: inputRole
            )
            let stage: SceneAuthoredEffectExecutionPlan?
            if let preciseBlur {
                stage = preciseBlur
            } else if let standardBlur {
                stage = standardBlur
            } else if let localContrast {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .localContrast(localContrast),
                    materialNodeCount: 4,
                    logicalRenderTargetCount: 2,
                    inputRole: inputRole
                )
            } else if let opacity {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .opacity(opacity),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let workshopShadow {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .workshopShadow(workshopShadow),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let shake {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .shake(shake),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let waterFlow {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .waterFlow(waterFlow),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let waterWaves {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .waterWaves(waterWaves),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let foliageSway {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .foliageSway(foliageSway),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let waterRipple {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .waterRipple(waterRipple),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let xRay {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .xRay(xRay),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else if let tint {
                stage = SceneAuthoredEffectExecutionPlan(
                    layerID: graph.layerID,
                    renderGraph: stageGraph,
                    backend: .tint(tint),
                    materialNodeCount: 1,
                    logicalRenderTargetCount: 0,
                    inputRole: inputRole
                )
            } else {
                stage = nil
            }
            guard let stage else {
                if let prefix = xRayPrefix(
                    plannedStages: stages,
                    unsupportedOrdinal: ordinal,
                    graph: graph,
                    descriptor: descriptor
                ) {
                    return prefix
                }
#if DEBUG
                print(
                    "MWX authored effect chain rejected layer=\(graph.layerID) "
                        + "effect=\(effect.definitionPath) index=\(ordinal) reason=unsupported-stage"
                )
#endif
                return nil
            }
            stages.append(stage)
        }
        guard fitsDefaultTextureBudget(stages) else {
#if DEBUG
            print("MWX authored effect chain rejected layer=\(graph.layerID) reason=texture-budget")
#endif
            return nil
        }

        return SceneAuthoredEffectExecutionChain(
            layerID: graph.layerID,
            renderGraph: graph,
            stages: stages
        )
    }

    nonisolated static func fitsDefaultTextureBudget(
        _ stages: [SceneAuthoredEffectExecutionPlan]
    ) -> Bool {
        if stages.allSatisfy({ $0.logicalRenderTargetCount == 0 }) {
            return !stages.isEmpty
        }
        var textureUnits = 0
        for stage in stages {
            let (stageUnits, stageOverflow) = stage.logicalRenderTargetCount
                .addingReportingOverflow(2)
            guard !stageOverflow else { return false }
            let (nextUnits, totalOverflow) = textureUnits.addingReportingOverflow(stageUnits)
            guard !totalOverflow, nextUnits <= maximumResidentTextureUnits else { return false }
            textureUnits = nextUnits
        }
        return !stages.isEmpty
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

    nonisolated static func stageGraph(
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

    // The default 96 MiB pool guarantees six 2048x2048 BGRA textures.
    private nonisolated static let maximumResidentTextureUnits = 6
}
