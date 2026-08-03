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

    var colorGradingCount: Int {
        stages.filter { $0.colorGrading != nil }.count
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

    var waterCausticsCount: Int {
        stages.filter { $0.waterCaustics != nil }.count
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
    var scrollCount: Int {
        stages.filter { $0.authoredShader?.profile == .scroll }.count
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
