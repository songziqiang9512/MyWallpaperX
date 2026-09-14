import Foundation

/// Makes the authored numeric-bool arithmetic surface explicit for Vulkan
/// GLSL without changing ordinary control-flow comparisons.
nonisolated enum SceneGenericShaderBooleanScalarArithmeticNormalizer {
    static func rewrite(_ source: String) -> String {
        let atom = #"(?:[A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[xyzwrgba])?|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))"#
        let pattern = #"(?<![A-Za-z0-9_])\(\s*("# + atom
            + #"\s*(?:<=|>=|==|!=|<|>)\s*"# + atom
            + #")\s*\)(?=\s*[+\-*/])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var result = regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: "float($1)"
        )
        let compound = try! NSRegularExpression(pattern:
            #"\b[A-Za-z_][A-Za-z0-9_]*(?:\s*(?:\.\s*[xyzwrgba]|\[[^\]\r\n]+\]))*\s*(?:\+=|-=|\*=|\/=)\s*([^;?\r\n]*(?:<=|>=|==|!=|<|>)[^;?\r\n]*)(\s*;)"#
        )
        for match in compound.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let expression = String(result[range])
            guard !expression.trimmingCharacters(in: .whitespaces)
                .hasPrefix("float(") else { continue }
            result.replaceSubrange(range, with: "float(\(expression))")
        }
        return rewriteBooleanIdentifiers(result)
    }

    /// A declared boolean used as a numeric assignment operand needs the
    /// same explicit conversion as an inline comparison. Reject ambiguous
    /// names; never infer a type from an identifier's spelling.
    private static func rewriteBooleanIdentifiers(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") ? "" : $0
        }.joined(separator: "\n")
        let lexical = SceneAuthoredShaderLexer.lex(source: analysisSource, stage: .fragment)
        guard lexical.diagnostics.isEmpty else { return normalized }
        let tokens = lexical.tokens
        var declarations: [String: [(type: String, index: Int)]] = [:]
        for index in tokens.indices.dropLast() {
            guard SceneAuthoredShaderValueType(authoredName: tokens[index].text) != nil,
                  tokens[index + 1].kind == .identifier else { continue }
            declarations[tokens[index + 1].text, default: []].append(
                (tokens[index].text, index + 1)
            )
        }
        var lineStarts = [0]
        for (index, scalar) in normalized.unicodeScalars.enumerated() where scalar == "\n" {
            lineStarts.append(index + 1)
        }
        var edits: [(offset: Int, length: Int, text: String)] = []
        for index in tokens.indices where index > 0 && index + 2 < tokens.count {
            guard ["=", "+=", "-=", "*=", "/="].contains(tokens[index].text),
                  tokens[index - 1].kind == .identifier,
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 2].text == ";",
                  index < 2 || tokens[index - 2].text != ".",
                  let targets = declarations[tokens[index - 1].text], targets.count == 1,
                  let inputs = declarations[tokens[index + 1].text], inputs.count == 1,
                  ["float", "int", "uint"].contains(targets[0].type),
                  inputs[0].type == "bool",
                  targets[0].index < index, inputs[0].index < index else { continue }
            let token = tokens[index + 1]
            guard token.line > 0, token.line <= lineStarts.count else { continue }
            edits.append((lineStarts[token.line - 1] + token.column - 1,
                          token.text.unicodeScalars.count,
                          "\(targets[0].type)(\(token.text))"))
        }
        var result = normalized
        for edit in edits.reversed() {
            let scalars = result.unicodeScalars
            let start = scalars.index(scalars.startIndex, offsetBy: edit.offset)
            let end = scalars.index(start, offsetBy: edit.length)
            guard let lower = String.Index(start, within: result),
                  let upper = String.Index(end, within: result) else { return normalized }
            result.replaceSubrange(lower..<upper, with: edit.text)
        }
        return result
    }
}
