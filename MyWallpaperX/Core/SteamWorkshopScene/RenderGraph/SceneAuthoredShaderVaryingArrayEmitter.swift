import Foundation

nonisolated enum SceneAuthoredShaderVaryingArrayEmitter {
    struct Result {
        let source: String?
        let nextIndex: Int?
        let diagnostic: SceneAuthoredShaderFrontendDiagnostic?
    }

    static func reference(
        tokens: [SceneAuthoredShaderToken],
        index: Int,
        arrayCounts: [String: Int],
        stage: SceneShaderContract.StageKind
    ) -> Result? {
        let token = tokens[index]
        guard let count = arrayCounts[token.text] else { return nil }
        guard index + 3 < tokens.count,
              tokens[index + 1].text == "[",
              let element = Int(tokens[index + 2].text),
              (0..<count).contains(element),
              tokens[index + 3].text == "]" else {
            return .init(source: nil, nextIndex: nil, diagnostic: .init(
                code: .unsupportedType,
                message: "Varying arrays require a bounded literal index.",
                stage: stage,
                line: token.line,
                column: token.column
            ))
        }
        let prefix = stage == .vertex ? "mwxOutput" : "mwxInput"
        return .init(
            source: "\(prefix).\(token.text)_\(element)",
            nextIndex: index + 4,
            diagnostic: nil
        )
    }
}
