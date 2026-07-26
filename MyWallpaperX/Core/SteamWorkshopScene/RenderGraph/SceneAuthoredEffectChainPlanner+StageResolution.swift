import Foundation

extension SceneAuthoredEffectChainPlanner {
    /// 对单个 stage graph 依次尝试全部 strict backend planner；
    /// 命中顺序与既有调度一致（blur 系优先，随后按接入顺序）。
    nonisolated static func resolveStage(
        stageGraph: Graph,
        inputRole: SceneAuthoredEffectInputRole,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionPlan? {
        if let preciseBlur = SceneAuthoredEffectExecutionPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            inputRole: inputRole
        ) {
            return preciseBlur
        }
        if let standardBlur = SceneAuthoredStandardBlurPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            inputRole: inputRole
        ) {
            return standardBlur
        }
        if let localContrast = SceneAuthoredLocalContrastPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(
                .localContrast(localContrast),
                stageGraph: stageGraph,
                inputRole: inputRole,
                materialNodeCount: 4,
                logicalRenderTargetCount: 2
            )
        }
        if let opacity = SceneAuthoredOpacityPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.opacity(opacity), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let workshopShadow = SceneAuthoredWorkshopShadowPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(
                .workshopShadow(workshopShadow),
                stageGraph: stageGraph,
                inputRole: inputRole
            )
        }
        if let shake = SceneAuthoredShakePlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.shake(shake), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let waterFlow = SceneAuthoredWaterFlowPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.waterFlow(waterFlow), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let waterWaves = SceneAuthoredWaterWavesPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.waterWaves(waterWaves), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let foliageSway = SceneAuthoredFoliageSwayPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(
                .foliageSway(foliageSway),
                stageGraph: stageGraph,
                inputRole: inputRole
            )
        }
        if let waterRipple = SceneAuthoredWaterRipplePlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(
                .waterRipple(waterRipple),
                stageGraph: stageGraph,
                inputRole: inputRole
            )
        }
        if let xRay = SceneAuthoredXRayPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.xRay(xRay), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let tint = SceneAuthoredTintPlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.tint(tint), stageGraph: stageGraph, inputRole: inputRole)
        }
        if let pulse = SceneAuthoredPulsePlanner.plan(
            graph: stageGraph,
            descriptor: descriptor,
            shaderContracts: shaderContracts,
            inputRole: inputRole
        ) {
            return stage(.pulse(pulse), stageGraph: stageGraph, inputRole: inputRole)
        }
        return nil
    }

    private nonisolated static func stage(
        _ backend: SceneAuthoredEffectExecutionPlan.Backend,
        stageGraph: Graph,
        inputRole: SceneAuthoredEffectInputRole,
        materialNodeCount: Int = 1,
        logicalRenderTargetCount: Int = 0
    ) -> SceneAuthoredEffectExecutionPlan {
        SceneAuthoredEffectExecutionPlan(
            layerID: stageGraph.layerID,
            renderGraph: stageGraph,
            backend: backend,
            materialNodeCount: materialNodeCount,
            logicalRenderTargetCount: logicalRenderTargetCount,
            inputRole: inputRole
        )
    }
}
