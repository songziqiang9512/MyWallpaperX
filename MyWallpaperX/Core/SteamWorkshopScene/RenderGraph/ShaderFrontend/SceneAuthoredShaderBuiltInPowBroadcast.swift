import Foundation

extension SceneAuthoredShaderBuiltInVectorConversion {
    /// Wallpaper Engine's authored surface accepts one scalar exponent for a
    /// floating vector `pow` base. Vulkan GLSL requires both operands to have
    /// the same vector width. Broadcast only an expression whose scalar type
    /// and base width are proven by the shared syntax model; user overloads
    /// and vector or unknown exponents keep the compiler rejection boundary.
    static func rewriteScalarPowBroadcasts(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#version")
                ? "" : line
        }.joined(separator: "\n")
        let lexer = SceneAuthoredShaderLexer.lex(
            source: analysisSource,
            stage: stage
        )
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexer,
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              !unit.functions.contains(where: { $0.name == "pow" }) else {
            return normalized
        }

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        func tokenOffset(_ index: Int, afterToken: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            return lineStarts[token.line - 1] + token.column - 1
                + (afterToken ? token.text.unicodeScalars.count : 0)
        }

        var insertions: [(offset: Int, text: String)] = []
        for index in unit.tokens.indices {
            guard unit.tokens[index].text == "pow",
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 2,
                  let base = componentExpression(
                      arguments[0], tokens: unit.tokens, unit: unit
                  ),
                  let exponent = componentExpression(
                      arguments[1], tokens: unit.tokens, unit: unit
                  ),
                  let width = floatVectorWidth(base.type),
                  exponent.type == .float,
                  let start = tokenOffset(
                      arguments[1].lowerBound,
                      afterToken: false
                  ),
                  let end = tokenOffset(
                      arguments[1].upperBound - 1,
                      afterToken: true
                  ) else { continue }
            insertions.append((start, "vec\(width)("))
            insertions.append((end, ")"))
        }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for insertion in insertions.sorted(by: { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset > rhs.offset }
            if lhs.text != rhs.text { return lhs.text == ")" }
            return false
        }) {
            guard insertion.offset <= result.unicodeScalars.count else {
                return normalized
            }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: insertion.offset
            )
            guard let stringIndex = String.Index(
                scalarIndex,
                within: result
            ) else { return normalized }
            result.insert(contentsOf: insertion.text, at: stringIndex)
        }
        return result
    }
}
