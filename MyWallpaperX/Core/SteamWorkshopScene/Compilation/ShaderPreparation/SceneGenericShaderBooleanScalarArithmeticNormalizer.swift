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
        let declarations = uniqueScalarDeclarations(in: tokens)
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
                  let target = declarations[tokens[index - 1].text],
                  let input = declarations[tokens[index + 1].text],
                  ["float", "int", "uint"].contains(target.type),
                  input.type == "bool",
                  target.index < index, input.index < index else { continue }
            let token = tokens[index + 1]
            guard token.line > 0, token.line <= lineStarts.count else { continue }
            edits.append((lineStarts[token.line - 1] + token.column - 1,
                          token.text.unicodeScalars.count,
                          "\(target.type)(\(token.text))"))
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

    /// Shared scalar facts for explicit bool/numeric conversions. Count every
    /// declarator in a typed declaration list, including shadowed names and
    /// members; without scope proof any repeated name stays ambiguous. Array
    /// and function names never provide scalar values. Balanced initializers
    /// keep argument commas separate from declaration-list commas.
    static func uniqueScalarDeclarations(
        in tokens: [SceneAuthoredShaderToken]
    ) -> [String: (type: String, index: Int)] {
        var declarations: [String: [(type: String, index: Int, scalar: Bool)]] = [:]
        func record(_ index: Int, type: String) {
            let next = index + 1 < tokens.count ? tokens[index + 1].text : ""
            declarations[tokens[index].text, default: []].append((
                type, index,
                ["float", "int", "uint", "bool"].contains(type)
                    && next != "[" && next != "("
            ))
        }
        for index in tokens.indices.dropLast() {
            guard let valueType = SceneAuthoredShaderValueType(
                authoredName: tokens[index].text
            ), tokens[index + 1].kind == .identifier else { continue }
            record(index + 1, type: valueType.rawValue)
            guard index + 2 < tokens.count,
                  tokens[index + 2].text != "(" else { continue }
            var depth = 0
            var cursor = index + 2
            while cursor < tokens.count {
                let text = tokens[cursor].text
                if depth == 0, [";", ")", "{", "}"].contains(text) { break }
                if ["(", "["].contains(text) { depth += 1 }
                if [")", "]"].contains(text) { depth -= 1 }
                if text == ",", depth == 0, cursor + 2 < tokens.count,
                   tokens[cursor + 1].kind == .identifier,
                   ["=", ";", ",", "["].contains(tokens[cursor + 2].text) {
                    record(cursor + 1, type: valueType.rawValue)
                }
                cursor += 1
            }
        }
        return declarations.compactMapValues { facts in
            guard facts.count == 1, facts[0].scalar else { return nil }
            return (facts[0].type, facts[0].index)
        }
    }
}
