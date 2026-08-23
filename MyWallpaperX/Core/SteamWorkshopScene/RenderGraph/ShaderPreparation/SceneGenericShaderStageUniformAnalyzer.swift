import Foundation

nonisolated enum SceneGenericShaderStageUniformAnalyzer {
    static func hasScopedBindings(
        vertexSource: String,
        fragmentSource: String
    ) -> Bool {
        guard let vertex = activeUniforms(vertexSource, stage: .vertex),
              let fragment = activeUniforms(fragmentSource, stage: .fragment) else {
            return false
        }
        return !vertex.isEmpty && !fragment.isEmpty
    }

    private static func activeUniforms(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> Set<String>? {
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: stage
            ),
            stage: stage
        )
        guard output.diagnostics.isEmpty, let unit = output.unit else { return nil }
        return Set(unit.declarations.compactMap { declaration in
            guard declaration.storage == .uniform,
                  declaration.typeName != "sampler2D",
                  SceneAuthoredShaderGlobalReferenceAnalyzer.isReferenced(
                      declaration.name,
                      in: unit
                  ) else { return nil }
            return declaration.name
        })
    }
}
