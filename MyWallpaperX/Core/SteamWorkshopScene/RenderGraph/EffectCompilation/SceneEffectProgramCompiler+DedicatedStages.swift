import Foundation

nonisolated enum SceneEffectDedicatedStageResolution {
    case accepted(
        backend: SceneEffectStageCompilerBackend,
        executionPlan: SceneEffectStageExecutionPlan,
        precedingProbes: [SceneEffectStageCompilerProbe]
    )
    case exhausted(probes: [SceneEffectStageCompilerProbe])
}

extension SceneEffectProgramCompiler {
    /// Compiles typed stage programs without granting execution ownership.
    /// The resolved capability catalog must still admit every active stage in
    /// the layer before GraphExecutor may claim the ordered graph.
    nonisolated static func compileDedicatedLeaves(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer> = [],
        propertyDefinitions: [SceneDynamicTargetDefinition] = [],
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
        activeEffectLocalDirectBoolVisibilityTargets:
            Set<SceneDynamicTarget> = [],
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        frameDrivenEffectVisibilityOwners:
            Set<SceneEffectStageCompileInput.DynamicEffectVisibilityOwner> = []
    ) -> [SceneEffectStageProgram] {
        graph.effects.enumerated().compactMap { ordinal, effect in
            guard let stageGraph = stageGraph(effect: effect, in: graph) else {
                return nil
            }
            let input = SceneEffectStageCompileInput(
                stageGraph: stageGraph,
                authoredOrdinal: ordinal,
                effectKey: effect.key,
                definitionPath: effect.definitionPath,
                inputRole: ordinal == 0 ? .layerSource : .priorEffectOutput,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                userPropertyProducers: userPropertyProducers,
                propertyDefinitions: propertyDefinitions,
                timelineDefinitions: timelineDefinitions,
                activeEffectLocalDirectBoolVisibilityTargets:
                    activeEffectLocalDirectBoolVisibilityTargets,
                startupInactiveEffectVisibilityTargets:
                    startupInactiveEffectVisibilityTargets,
                frameDrivenEffectVisibilityOwners:
                    frameDrivenEffectVisibilityOwners
            )
            guard case let .accepted(backend, plan, probes) =
                    resolveDedicatedStage(input) else { return nil }
            return SceneEffectStageProgram(
                input: input,
                compilerBackend: backend,
                executionPlan: plan,
                precedingProbes: probes
            )
        }
    }

    /// Ordered typed compilers distinguish stages outside a compiler family
    /// from same-family stages rejected by an exact fail-closed profile.
    nonisolated static func resolveDedicatedStage(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectDedicatedStageResolution {
        let stageGraph = input.stageGraph
        let inputRole = input.inputRole
        typealias Probe = (
            backend: SceneEffectStageCompilerBackend,
            compile: () -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan>
        )
        // Precise Gaussian is absent from the product compiler chain because
        // authored two-pass/FBO blur is owned by MaterialProgram and
        // GraphExecutor. The retired dedicated family is physically removed
        // and cannot regain product or oracle execution.
        let probes: [Probe] = [
            (.standardBlur, {
                SceneAuthoredStandardBlurPlanner.compile(input)
            }),
            (.xRay, {
                SceneAuthoredXRayPlanner.compile(input).mapAccepted {
                    stage(.xRay($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.pulse, {
                SceneAuthoredPulsePlanner.compile(input).mapAccepted {
                    stage(.pulse($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
        ]

        var precedingProbes: [SceneEffectStageCompilerProbe] = []
        precedingProbes.reserveCapacity(probes.count)
        for probe in probes {
            switch probe.compile() {
            case .accepted(let executionPlan):
                return .accepted(
                    backend: probe.backend,
                    executionPlan: executionPlan,
                    precedingProbes: precedingProbes
                )
            case .notApplicable:
                precedingProbes.append(.init(
                    backend: probe.backend,
                    outcome: .notApplicable
                ))
            case .rejected(let failure):
                precedingProbes.append(.init(
                    backend: probe.backend,
                    outcome: .rejected(failure)
                ))
            }
        }
        return .exhausted(probes: precedingProbes)
    }
}
