import Foundation

nonisolated struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stagePrograms: [SceneEffectStageProgram]
    let legacyRecoveryStages: [SceneAuthoredEffectExecutionPlan]
    let executionRoute: ExecutionRoute
    let irisInlineSuffix: SceneIrisInlineSuffixPlan?
    let isolatedCursorRippleOmittedEffectPaths: [String]
    let isolatedShineOmittedEffectPaths: [String]

    var executionStages: [SceneAuthoredEffectExecutionPlan] {
        switch executionRoute {
        case .completePrograms:
            stagePrograms.map(\.executionPlan)
        case .legacyRecovery:
            legacyRecoveryStages.isEmpty
                ? stagePrograms.map(\.executionPlan)
                : legacyRecoveryStages
        }
    }

    var singleStage: SceneAuthoredEffectExecutionPlan? {
        let projectedExecutionStages = executionStages
        return projectedExecutionStages.count == 1
            ? projectedExecutionStages[0]
            : nil
    }

    var materialNodeCount: Int {
        executionStages.reduce(0) { $0 + $1.materialNodeCount }
    }

    var logicalRenderTargetCount: Int {
        executionStages.reduce(0) { $0 + $1.logicalRenderTargetCount }
    }

    var localContrastCount: Int {
        executionStages.filter { $0.localContrast != nil }.count
    }

    var opacityCount: Int {
        executionStages.filter { $0.opacity != nil }.count
    }

    var colorGradingCount: Int {
        executionStages.filter { $0.colorGrading != nil }.count
    }

    var workshopShiftHueCount: Int {
        executionStages.filter { $0.workshopShiftHue != nil }.count
    }

    var workshopAudioBarsCount: Int {
        executionStages.filter { $0.workshopAudioBars != nil }.count
    }

    var workshopGradientCount: Int {
        executionStages.filter { $0.workshopGradient != nil }.count
    }

    var workshopAudioHueShiftCount: Int {
        executionStages.filter { $0.workshopAudioHueShift != nil }.count
    }

    var workshopShadowCount: Int {
        executionStages.filter { $0.workshopShadow != nil }.count
    }

    var spinCount: Int {
        executionStages.filter { $0.spin != nil }.count
    }

    var proceduralNoiseCount: Int {
        executionStages.filter { $0.proceduralNoise != nil }.count
    }

    var filmGrainCount: Int {
        executionStages.filter { $0.filmGrain != nil }.count
    }

    var lightShaftsCount: Int {
        executionStages.filter { $0.lightShafts != nil }.count
    }

    var shakeCount: Int {
        executionStages.filter { $0.shake != nil }.count
    }

    var waterFlowCount: Int {
        executionStages.filter { $0.waterFlow != nil }.count
    }

    var waterWavesCount: Int {
        executionStages.filter { $0.waterWaves != nil }.count
    }

    var waterCausticsCount: Int {
        executionStages.filter { $0.waterCaustics != nil }.count
    }

    var cursorRippleCount: Int {
        executionStages.filter { $0.cursorRipple != nil }.count
    }

    var isolatedCursorRippleCount: Int {
        isolatedCursorRippleOmittedEffectPaths.isEmpty ? 0 : cursorRippleCount
    }

    var foliageSwayCount: Int {
        executionStages.filter { $0.foliageSway != nil }.count
    }

    var waterRippleCount: Int {
        executionStages.filter { $0.waterRipple != nil }.count
    }

    var depthParallaxCount: Int {
        executionStages.filter { $0.depthParallax != nil }.count
    }

    var irisInlineSuffixCount: Int {
        irisInlineSuffix == nil ? 0 : 1
    }

    var xRayCount: Int {
        executionStages.filter { $0.xRay != nil }.count
    }

    var clippingMaskCount: Int {
        executionStages.filter { $0.clippingMask != nil }.count
    }

    var blendCount: Int {
        executionStages.filter { $0.blend != nil }.count
    }

    var tintCount: Int {
        executionStages.filter { $0.tint != nil }.count
    }

    var transformCount: Int {
        executionStages.filter { $0.transform != nil }.count
    }

    var fisheyeZeroDistortionCount: Int {
        executionStages.filter { $0.fisheyeZeroDistortion != nil }.count
    }

    var pulseCount: Int {
        executionStages.filter { $0.pulse != nil }.count
    }

    var godraysCount: Int {
        executionStages.filter { $0.godrays != nil }.count
    }

    var shineCount: Int {
        executionStages.filter { $0.shine != nil }.count
    }

    var isolatedShineCount: Int {
        isolatedShineOmittedEffectPaths.isEmpty ? 0 : shineCount
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(executionStages.flatMap(\.liveConsumerTargets))
    }

    var executedUserPropertyKeys: Set<String> {
        Set(executionStages.flatMap { $0.blend?.executedUserPropertyKeys ?? [] })
    }
}

enum SceneAuthoredEffectChainPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        admit(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: shaderContracts
        ).chain
    }

    nonisolated static func fitsDefaultTextureBudget(
        _ stages: [SceneAuthoredEffectExecutionPlan]
    ) -> Bool {
        if stages.allSatisfy({
            $0.logicalRenderTargetCount == 0 && $0.renderGraph.renderTargets.isEmpty
        }) {
            return !stages.isEmpty
        }
        // 混合链每 stage 独立计 input/output 两张全尺寸纹理；已声明 RT
        // 按完整 extent 折算，缺失声明按整张补足，非法 extent 直接拒绝。
        var textureUnits = 0.0
        for stage in stages {
            var stageUnits = 2.0
            let declaredTargets = stage.renderGraph.renderTargets
            let targetCosts = declaredTargets.map { renderTargetUnitCost($0.extent) }
            guard targetCosts.allSatisfy(\.isFinite) else { return false }
            stageUnits += targetCosts.reduce(0, +)
            stageUnits += Double(max(
                0, stage.logicalRenderTargetCount - declaredTargets.count
            ))
            textureUnits += stageUnits
            guard textureUnits <= Double(maximumResidentTextureUnits) else { return false }
        }
        return !stages.isEmpty
    }

    private nonisolated static func renderTargetUnitCost(
        _ extent: SceneAuthoredEffectRenderPlan.TargetExtent
    ) -> Double {
        // Resolve against the same documented 2048² reference used by this
        // admission gate, preserving override -> fit -> scale -> floor order.
        guard let resolved = SceneGraphRenderTargetPlan.pixelExtent(
            extent,
            inputWidth: 2048,
            inputHeight: 2048
        ) else {
            return .infinity
        }
        return (Double(resolved.width) * Double(resolved.height)) / (2048 * 2048)
    }

    nonisolated static func stageGraph(
        effect: Graph.Effect,
        in graph: Graph
    ) -> Graph? {
        stageGraphAdmission(effect: effect, in: graph).graph
    }

    // The default 128 MiB pool guarantees eight 2048x2048 BGRA textures.
    private nonisolated static let maximumResidentTextureUnits = 8
}
