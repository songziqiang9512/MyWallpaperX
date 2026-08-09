import Foundation

/// Canonical accepted result for one authored effect stage. Runtime execution
/// continues to consume `executionPlan`; the extra identity is the compile-time
/// conservation boundary used while planners migrate away from Optional probes.
nonisolated struct SceneEffectStageProgram {
    enum Selection {
        case dedicated(SceneEffectStageCompilerBackend)
    }

    let authoredOrdinal: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let definitionPath: String
    let inputRole: SceneAuthoredEffectInputRole
    let stageGraph: SceneAuthoredEffectRenderPlan
    let selection: Selection
    let precedingProbes: [SceneEffectStageCompilerProbe]
    let executionPlan: SceneAuthoredEffectExecutionPlan

    init?(
        input: SceneEffectStageCompileInput,
        compilerBackend: SceneEffectStageCompilerBackend,
        executionPlan: SceneAuthoredEffectExecutionPlan,
        precedingProbes: [SceneEffectStageCompilerProbe] = []
    ) {
        guard let authoredOrdinal = input.authoredOrdinal,
              let effectKey = input.effectKey,
              let definitionPath = input.definitionPath,
              input.stageGraph.effects.count == 1,
              let graphEffect = input.stageGraph.effects.first,
              graphEffect.key == effectKey,
              graphEffect.definitionPath == definitionPath,
              executionPlan.layerID == input.stageGraph.layerID,
              executionPlan.inputRole == input.inputRole,
              Self.graphsMatch(input.stageGraph, executionPlan.renderGraph),
              Self.backendMatches(
                  compilerBackend: compilerBackend,
                  runtimeBackend: executionPlan.backend
              ) else {
            return nil
        }
        self.authoredOrdinal = authoredOrdinal
        self.effectKey = effectKey
        self.definitionPath = definitionPath
        self.inputRole = input.inputRole
        self.stageGraph = input.stageGraph
        selection = .dedicated(compilerBackend)
        self.precedingProbes = precedingProbes
        self.executionPlan = executionPlan
    }

    nonisolated static func graphsMatch(
        _ lhs: SceneAuthoredEffectRenderPlan,
        _ rhs: SceneAuthoredEffectRenderPlan
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let lhsData = try? encoder.encode(lhs),
              let rhsData = try? encoder.encode(rhs) else {
            return false
        }
        return lhsData == rhsData
    }

    private nonisolated static func backendMatches(
        compilerBackend: SceneEffectStageCompilerBackend,
        runtimeBackend: SceneAuthoredEffectExecutionPlan.Backend
    ) -> Bool {
        switch (compilerBackend, runtimeBackend) {
        case (.preciseGaussian, .preciseGaussian),
             (.standardBlur, .standardBlur),
             (.localContrast, .localContrast),
             (.opacity, .opacity),
             (.colorGrading, .colorGrading),
             (.workshopShiftHue, .workshopShiftHue),
             (.workshopGradient, .workshopGradient),
             (.workshopShadow, .workshopShadow),
             (.spin, .spin),
             (.proceduralNoise, .proceduralNoise),
             (.filmGrain, .filmGrain),
             (.lightShafts, .lightShafts),
             (.shake, .shake),
             (.waterFlow, .waterFlow),
             (.waterWaves, .waterWaves),
             (.waterCaustics, .waterCaustics),
             (.cursorRipple, .cursorRipple),
             (.foliageSway, .foliageSway),
             (.waterRipple, .waterRipple),
             (.depthParallax, .depthParallax),
             (.xRay, .xRay),
             (.clippingMask, .clippingMask),
             (.blend, .blend),
             (.tint, .tint),
             (.transform, .transform),
             (.fisheyeZeroDistortion, .fisheyeZeroDistortion),
             (.pulse, .pulse),
             (.godrays, .godrays),
             (.shine, .shine):
            return true
        case (.workshopAudioBars, .workshopAudioBars(let plan)):
            if case .enhancedSegmented = plan.profile { return true }
            return false
        default:
            return false
        }
    }
}

nonisolated struct SceneEffectStageCompileFailure {
    enum Code: String {
        case noBackendAccepted = "no-backend-accepted"
        case stageProgramInvariant = "stage-program-invariant"
    }

    let code: Code
    let probes: [SceneEffectStageCompilerProbe]
}

nonisolated enum SceneEffectStageCompileResult {
    case accepted(SceneEffectStageProgram)
    case unsupported(SceneEffectStageCompileFailure)

    static func accepted(
        _ executionPlan: SceneAuthoredEffectExecutionPlan,
        compilerBackend: SceneEffectStageCompilerBackend,
        input: SceneEffectStageCompileInput,
        precedingProbes: [SceneEffectStageCompilerProbe] = []
    ) -> Self {
        guard let program = SceneEffectStageProgram(
            input: input,
            compilerBackend: compilerBackend,
            executionPlan: executionPlan,
            precedingProbes: precedingProbes
        ) else {
            return .unsupported(.init(
                code: .stageProgramInvariant,
                probes: precedingProbes + [.init(
                    backend: compilerBackend,
                    outcome: .rejected(.init(
                        backend: compilerBackend,
                        phase: .invariant,
                        code: .stageProgramInvariant
                    ))
                )]
            ))
        }
        return .accepted(program)
    }
}
