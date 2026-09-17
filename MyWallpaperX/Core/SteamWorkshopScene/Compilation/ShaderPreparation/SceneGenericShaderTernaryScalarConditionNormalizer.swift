import Foundation

/// Rewrites authored numeric-literal ternary conditions into explicit bool
/// literals so the strict Vulkan GLSL stage link accepts the Wallpaper Engine
/// dialect's implicit scalar→bool condition conversion (for example
/// `mask = 0 ? 1 - mask : mask;`). The rewrite preserves the authored
/// selection exactly: `0` selects the else branch and any other finite value
/// selects the then branch. Only a number token that is the entire ternary
/// condition is rewritten; scalar expressions and unprovable contexts stay
/// untouched so the stage link keeps failing closed instead of changing
/// meaning silently.
nonisolated enum SceneGenericShaderTernaryScalarConditionNormalizer {
    static func rewrite(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") ? "" : $0
        }.joined(separator: "\n")
        let lexical = SceneAuthoredShaderLexer.lex(source: analysisSource, stage: .fragment)
        guard lexical.diagnostics.isEmpty else { return normalized }
        let tokens = lexical.tokens
        var lineStarts = [0]
        for (index, scalar) in normalized.unicodeScalars.enumerated() where scalar == "\n" {
            lineStarts.append(index + 1)
        }
        // A number is the whole ternary condition only when the previous
        // token opens a value position: assignment, argument, grouping,
        // branch boundary, nested ternary, or `return`. Arithmetic, logic,
        // and comparison operators keep the condition an expression the
        // rewriter cannot prove scalar-typed, so those stay untouched.
        let openers: Set<String> = ["=", "(", ",", ";", "{", "}", ":", "?"]
        let comparisonTokens: Set<String> = ["==", "<=", ">=", "!="]
        var edits: [(offset: Int, length: Int, text: String)] = []
        for index in tokens.indices where index > 0 && index + 1 < tokens.count {
            guard tokens[index].kind == .number,
                  tokens[index + 1].kind == .symbol,
                  tokens[index + 1].text == "?" else { continue }
            let previous = tokens[index - 1]
            var previousOpensCondition: Bool
            switch previous.kind {
            case .symbol:
                previousOpensCondition = openers.contains(previous.text)
                if previousOpensCondition, previous.text == "=",
                   index > 1,
                   comparisonTokens.contains(tokens[index - 2].text) {
                    previousOpensCondition = false
                }
            case .identifier:
                previousOpensCondition = previous.text == "return"
            case .number:
                previousOpensCondition = false
            }
            guard previousOpensCondition else { continue }
            guard let value = Double(tokens[index].text), value.isFinite else { continue }
            let replacement = value == 0 ? "false" : "true"
            let token = tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { continue }
            edits.append((
                lineStarts[token.line - 1] + token.column - 1,
                token.text.unicodeScalars.count,
                replacement
            ))
        }
        var result = normalized
        for edit in edits.reversed() {
            let scalars = result.unicodeScalars
            let start = scalars.index(scalars.startIndex, offsetBy: edit.offset)
            let end = scalars.index(start, offsetBy: edit.length)
            guard let lower = String.Index(start, within: result),
                  let upper = String.Index(end, within: result) else { continue }
            result.replaceSubrange(lower..<upper, with: edit.text)
        }
        return result
    }
}
