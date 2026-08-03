import Foundation

extension SceneAuthoredEffectChainPlanner {
    /// Single typed authority for stage backend selection. Dedicated Optional
    /// planners terminate at the ordered adapter boundary; authored-source
    /// fallback already preserves its more specific typed rejection.
    nonisolated static func compileStage(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageCompileResult {
        var probes: [SceneEffectStageCompilerProbe]
        switch resolveDedicatedStage(input) {
        case .accepted(let backend, let executionPlan, let precedingProbes):
            return .accepted(
                executionPlan,
                compilerBackend: backend,
                input: input,
                precedingProbes: precedingProbes
            )
        case .exhausted(let dedicatedProbes):
            probes = dedicatedProbes
        }
        switch SceneAuthoredShaderExecutionPlanner.compile(input) {
        case .accepted(let authoredShader):
            let executionPlan = stage(
                .authoredShader(authoredShader),
                stageGraph: input.stageGraph,
                inputRole: input.inputRole
            )
            return .accepted(
                executionPlan,
                compilerBackend: .authoredShader,
                input: input,
                precedingProbes: probes
            )
        case .notApplicable:
            probes.append(.init(
                backend: .authoredShader,
                outcome: .notApplicable
            ))
        case .rejected(let failure):
            probes.append(.init(
                backend: .authoredShader,
                outcome: .rejected(failure)
            ))
        }

        return .unsupported(.init(
            code: .noBackendAccepted,
            probes: probes
        ))
    }

    nonisolated static func stage(
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
