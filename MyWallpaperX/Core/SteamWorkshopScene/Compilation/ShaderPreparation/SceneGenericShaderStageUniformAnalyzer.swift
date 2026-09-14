import Foundation

nonisolated enum SceneGenericShaderStageUniformAnalyzer {
    static func hasScopedBindings(
        vertexSource: String,
        fragmentSource: String,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) -> Bool {
        guard let vertex = activeUniforms(
                  vertexSource,
                  stage: .vertex,
                  provenRuntimeLoopBounds: runtimeLoopBounds.vertex
              ),
              let fragment = activeUniforms(
                  fragmentSource,
                  stage: .fragment,
                  provenRuntimeLoopBounds: runtimeLoopBounds.fragment
              ) else {
            return false
        }
        return !vertex.isEmpty && !fragment.isEmpty
    }

    private static func activeUniforms(
        _ source: String,
        stage: SceneShaderContract.StageKind,
        provenRuntimeLoopBounds: [String: SceneAuthoredShaderExactScalarFact]
    ) -> Set<String>? {
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: stage
            ),
            stage: stage,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds
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
