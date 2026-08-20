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

extension SceneEffectStageExecutionPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .preciseGaussian,
            candidate: {
                containsAuthoredPreciseBlurCandidate(
                    graph: input.stageGraph,
                    descriptor: input.descriptor
                )
            },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredStandardBlurPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
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
    }
}

extension SceneAuthoredLocalContrastPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneLocalContrastPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .localContrast }
}

extension SceneAuthoredColorGradingPlanner: SceneEffectStageDedicatedPlanner {
    typealias DedicatedPlan = SceneColorGradingExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .colorGrading }

    nonisolated static func isCandidate(_ input: SceneEffectStageCompileInput) -> Bool {
        containsCandidate(graph: input.stageGraph, descriptor: input.descriptor)
    }
}

extension SceneAuthoredWorkshopAudioBarsPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneWorkshopAudioBarsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .workshopAudioBars }
}

extension SceneAuthoredProceduralNoisePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneProceduralNoiseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .proceduralNoise }
}

extension SceneAuthoredShakePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneShakeExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .shake }
}

extension SceneAuthoredWaterFlowPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneWaterFlowExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterFlow }
}

extension SceneAuthoredWaterWavesPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneWaterWavesExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterWaves }
}

nonisolated extension SceneAuthoredWaterCausticsPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneWaterCausticsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterCaustics }
}

nonisolated extension SceneAuthoredCursorRipplePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneCursorRippleExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .cursorRipple }
}

extension SceneAuthoredWaterRipplePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneWaterRippleExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterRipple }
}

extension SceneAuthoredDepthParallaxPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneDepthParallaxExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .depthParallax }
}

extension SceneAuthoredXRayPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneXRayExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .xRay }
}

extension SceneAuthoredBlendPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneBlendExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .blend }
}

extension SceneAuthoredTransformPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneTransformExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .transform }
}

extension SceneAuthoredPulsePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = ScenePulseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .pulse }
}

extension SceneAuthoredGodraysPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneGodraysPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .godrays }
}

extension SceneAuthoredShinePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneShineExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .shine }
}
