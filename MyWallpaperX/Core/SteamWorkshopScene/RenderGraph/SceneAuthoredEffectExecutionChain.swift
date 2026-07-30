import Foundation

nonisolated struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stages: [SceneAuthoredEffectExecutionPlan]
    let irisInlineSuffix: SceneIrisInlineSuffixPlan?
    let isolatedCursorRippleOmittedEffectPaths: [String]
    let isolatedShineOmittedEffectPaths: [String]

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        stages: [SceneAuthoredEffectExecutionPlan],
        irisInlineSuffix: SceneIrisInlineSuffixPlan? = nil,
        isolatedCursorRippleOmittedEffectPaths: [String] = [],
        isolatedShineOmittedEffectPaths: [String] = []
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.stages = stages
        self.irisInlineSuffix = irisInlineSuffix
        self.isolatedCursorRippleOmittedEffectPaths =
            isolatedCursorRippleOmittedEffectPaths
        self.isolatedShineOmittedEffectPaths = isolatedShineOmittedEffectPaths
    }

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

    var colorKeyCount: Int {
        stages.filter { $0.colorKey != nil }.count
    }

    var workshopShiftHueCount: Int {
        stages.filter { $0.workshopShiftHue != nil }.count
    }

    var workshopAudioBarsCount: Int {
        stages.filter { $0.workshopAudioBars != nil }.count
    }

    var workshopGradientCount: Int {
        stages.filter { $0.workshopGradient != nil }.count
    }

    var workshopAudioHueShiftCount: Int {
        stages.filter { $0.workshopAudioHueShift != nil }.count
    }

    var workshopShadowCount: Int {
        stages.filter { $0.workshopShadow != nil }.count
    }

    var spinCount: Int {
        stages.filter { $0.spin != nil }.count
    }

    var proceduralNoiseCount: Int {
        stages.filter { $0.proceduralNoise != nil }.count
    }

    var filmGrainCount: Int {
        stages.filter { $0.filmGrain != nil }.count
    }

    var lightShaftsCount: Int {
        stages.filter { $0.lightShafts != nil }.count
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

    var cursorRippleCount: Int {
        stages.filter { $0.cursorRipple != nil }.count
    }

    var isolatedCursorRippleCount: Int {
        isolatedCursorRippleOmittedEffectPaths.isEmpty ? 0 : cursorRippleCount
    }

    var foliageSwayCount: Int {
        stages.filter { $0.foliageSway != nil }.count
    }

    var waterRippleCount: Int {
        stages.filter { $0.waterRipple != nil }.count
    }

    var depthParallaxCount: Int {
        stages.filter { $0.depthParallax != nil }.count
    }

    var irisInlineSuffixCount: Int {
        irisInlineSuffix == nil ? 0 : 1
    }

    var xRayCount: Int {
        stages.filter { $0.xRay != nil }.count
    }

    var clippingMaskCount: Int {
        stages.filter { $0.clippingMask != nil }.count
    }

    var blendCount: Int {
        stages.filter { $0.blend != nil }.count
    }

    var tintCount: Int {
        stages.filter { $0.tint != nil }.count
    }

    var transformCount: Int {
        stages.filter { $0.transform != nil }.count
    }

    var fisheyeZeroDistortionCount: Int {
        stages.filter { $0.fisheyeZeroDistortion != nil }.count
    }

    var pulseCount: Int {
        stages.filter { $0.pulse != nil }.count
    }

    var godraysCount: Int {
        stages.filter { $0.godrays != nil }.count
    }

    var shineCount: Int {
        stages.filter { $0.shine != nil }.count
    }

    var isolatedShineCount: Int {
        isolatedShineOmittedEffectPaths.isEmpty ? 0 : shineCount
    }

    var authoredShaderCount: Int {
        stages.filter { $0.authoredShader != nil }.count
    }

    func authoredShaderOffscreenSize(for requestedSize: CGSize) -> CGSize? {
        stages.compactMap { $0.authoredShader?.offscreenSize(for: requestedSize) }.min {
            $0.width * $0.height < $1.width * $1.height
        }
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(stages.flatMap(\.liveConsumerTargets))
    }

    var executedUserPropertyKeys: Set<String> {
        Set(stages.flatMap { $0.blend?.executedUserPropertyKeys ?? [] })
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
            let stage = resolveStage(
                stageGraph: stageGraph,
                inputRole: inputRole,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            )
            guard let stage else {
                if let suffix = irisInlineSuffix(
                    plannedStages: stages,
                    unsupportedOrdinal: ordinal,
                    graph: graph,
                    descriptor: descriptor,
                    shaderContracts: shaderContracts
                ) {
                    return suffix
                }
                if let isolated = isolatedCursorRippleChain(
                    graph: graph,
                    descriptor: descriptor,
                    shaderContracts: shaderContracts
                ) {
                    return isolated
                }
                if let isolated = isolatedShineChain(
                    graph: graph,
                    descriptor: descriptor,
                    shaderContracts: shaderContracts
                ) {
                    return isolated
                }
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
        // 这里只能按假设的 2048² 输入估算，不能据此拒绝真实的小纹理长链。
        // SceneOffscreenTexturePool 会在拿到实际 extent 后按精确字节数原子准入，
        // 超出 128 MiB 的链仍会在分配前整条拒绝且不破坏现有 resident state。

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
        // 与运行时 SceneGraphRenderTargetTable 的字节口径一致：混合链每 stage
        // 独立分配 input/output 各 1 个全尺寸单位，logical RT 按 extent 折算
        // （scale=s → 1/s²）；运行时不支持或声明数不符的形态按整张保守计。
        var textureUnits = 0.0
        for stage in stages {
            var stageUnits = 2.0
            let declaredTargets = stage.renderGraph.renderTargets
            if declaredTargets.count == stage.logicalRenderTargetCount {
                for target in declaredTargets {
                    stageUnits += renderTargetUnitCost(target.extent)
                }
            } else {
                stageUnits += Double(
                    max(declaredTargets.count, stage.logicalRenderTargetCount)
                )
            }
            textureUnits += stageUnits
            guard textureUnits <= Double(maximumResidentTextureUnits) else { return false }
        }
        return !stages.isEmpty
    }

    private nonisolated static func renderTargetUnitCost(
        _ extent: SceneAuthoredEffectRenderPlan.TargetExtent
    ) -> Double {
        if extent.kind == .fit,
           let maximumSide = extent.first,
           maximumSide.isFinite,
           maximumSide > 0,
           extent.second == nil {
            // Offscreen admission runs before the concrete input extent is known.
            // The pool's documented 2048² unit is therefore the conservative
            // denominator; smaller inputs cost less at allocation time.
            return min(1, (maximumSide * maximumSide) / (2048 * 2048))
        }
        guard extent.kind == .scale,
              let scale = extent.first,
              scale.isFinite,
              scale >= 1 else {
            return 1
        }
        return 1 / (scale * scale)
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

    // The default 128 MiB pool guarantees eight 2048x2048 BGRA textures.
    private nonisolated static let maximumResidentTextureUnits = 8
}
