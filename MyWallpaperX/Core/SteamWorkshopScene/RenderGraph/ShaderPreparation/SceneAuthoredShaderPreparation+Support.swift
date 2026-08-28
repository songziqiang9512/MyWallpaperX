import Foundation

extension SceneAuthoredShaderPreparation {
    nonisolated static func failure(
        phase: SceneAuthoredShaderPreparationFailure.Phase,
        code: SceneAuthoredShaderPreparationFailure.Code,
        details: [String] = []
    ) -> SceneAuthoredShaderPreparationFailure {
        .init(phase: phase, code: code, details: details)
    }
}
