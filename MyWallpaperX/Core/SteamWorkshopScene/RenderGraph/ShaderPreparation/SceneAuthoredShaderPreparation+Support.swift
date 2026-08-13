import Foundation

extension SceneAuthoredShaderPreparation {
    nonisolated static func failure(
        phase: SceneEffectStageCompilerFailure.Phase,
        code: SceneEffectStageCompilerFailure.Code,
        details: [String] = []
    ) -> SceneAuthoredShaderPreparationFailure {
        .init(phase: phase, code: code, details: details)
    }
}
