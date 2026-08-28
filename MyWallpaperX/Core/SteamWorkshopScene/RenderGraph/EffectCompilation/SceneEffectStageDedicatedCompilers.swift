import Foundation

/// Common typed boundary for dedicated planners that share the authored graph,
/// descriptor, shader-contract and input-role inputs. Exact admission remains
/// in each existing planner; this protocol only owns result classification.
nonisolated protocol SceneEffectStageDedicatedPlanner {
    associatedtype DedicatedPlan

    static var compilerBackend: SceneEffectStageCompilerBackend { get }

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> DedicatedPlan?

    static func isCandidate(_ input: SceneEffectStageCompileInput) -> Bool
}

nonisolated protocol SceneEffectStageGraphCandidatePlanner:
    SceneEffectStageDedicatedPlanner
{
    static func containsCandidate(graph: SceneAuthoredEffectRenderPlan) -> Bool
}

extension SceneEffectStageDedicatedPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<DedicatedPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: compilerBackend,
            candidate: { isCandidate(input) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    shaderContracts: input.shaderContracts,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneEffectStageGraphCandidatePlanner {
    nonisolated static func isCandidate(
        _ input: SceneEffectStageCompileInput
    ) -> Bool {
        containsCandidate(graph: input.stageGraph)
    }
}

extension SceneAuthoredStandardBlurPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan> {
        let result = SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .standardBlur,
            candidate: { containsCandidate(graph: input.stageGraph) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
        guard case .accepted = result,
              let effect = input.stageGraph.effects.first,
              !input.hasFrameDrivenEffectVisibilityOwner(for: effect.key),
              let startupInactive = input.authoredEffectIsStartupInactive(
                for: effect.key
              ),
              (startupInactive
                ? input.supportsStartupInactiveUserPropertyVisibility(for: effect.key)
                : input.supportsEffectLocalUserPropertyVisibility(for: effect.key)),
              let terminalNodeIndex = effect.nodeIndices.last else { return result }
        let sourceAccepted =
            SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
                .acceptsDedicatedRevocation(
                    key: .init(
                        effect: effect.key,
                        nodeIndex: terminalNodeIndex
                    ),
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole,
                    shaderContracts: input.shaderContracts,
                    userPropertyProducers: input.userPropertyProducers,
                    propertyDefinitions: input.propertyDefinitions,
                    timelineDefinitions: input.timelineDefinitions
                )
        guard sourceAccepted,
              let baseRevocationDetail =
                SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
                    .dedicatedRevocationDetail(
                        graph: input.stageGraph,
                        descriptor: input.descriptor,
                        userPropertyProducers: input.userPropertyProducers,
                        propertyDefinitions: input.propertyDefinitions
                    ) else { return result }
        let revocationDetail = startupInactive
            ? "startup-inactive-direct-bool-\(baseRevocationDetail)"
            : baseRevocationDetail
        return .rejected(.init(
            backend: .standardBlur,
            phase: .compatibility,
            code: .dedicatedProfileRejected,
            details: [revocationDetail]
        ))
    }
}
