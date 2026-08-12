import Foundation

nonisolated enum SceneEffectProgramCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
}

extension SceneEffectProgramCompiler {
    /// Single typed authority for stage backend selection. Dedicated Optional
    /// planners terminate at the ordered adapter boundary; authored-source
    /// fallback already preserves its more specific typed rejection.
    nonisolated static func compileStage(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageCompileResult {
        switch resolveDedicatedStage(input) {
        case .accepted(let backend, let executionPlan, let precedingProbes):
            return .accepted(
                executionPlan,
                compilerBackend: backend,
                input: input,
                precedingProbes: precedingProbes
            )
        case .exhausted(let dedicatedProbes):
            return .unsupported(.init(
                code: .noBackendAccepted,
                probes: dedicatedProbes
            ))
        }
    }

    nonisolated static func stage(
        _ backend: SceneEffectStageExecutionPlan.Backend,
        stageGraph: Graph,
        inputRole: SceneAuthoredEffectInputRole,
        materialNodeCount: Int = 1,
        logicalRenderTargetCount: Int = 0
    ) -> SceneEffectStageExecutionPlan {
        SceneEffectStageExecutionPlan(
            layerID: stageGraph.layerID,
            renderGraph: stageGraph,
            backend: backend,
            materialNodeCount: materialNodeCount,
            logicalRenderTargetCount: logicalRenderTargetCount,
            inputRole: inputRole
        )
    }
}
