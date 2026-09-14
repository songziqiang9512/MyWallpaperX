import Foundation

nonisolated extension SceneAuthoredShaderColorTransferAnalyzer {
    /// Proves one unconditional whole-output scalar splat. The scalar may be a
    /// literal or a local `float`; attachment/output ABI separately decides
    /// whether this is color or preserved-channel data. This fact contains no
    /// effect, material, path, or source identity.
    static func isScalarSplatOutput(fragmentSource source: String) -> Bool {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return false
        }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output,
                  in: tokens,
                  body: main.bodyRange
              ) else { return false }
        let value = Array(expression)
        guard value.count == 4,
              ["CAST4", "vec4", "float4"].contains(value[0].text),
              value[1].text == "(", value[3].text == ")" else {
            return false
        }
        if value[2].kind == .number { return true }
        guard value[2].kind == .identifier else { return false }
        let scalar = value[2].text
        let declarations = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index + 1 < output
                && tokens[index].text == scalar
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
        }
        return declarations.count == 1
    }

    /// Proves an opaque local carrier whose alpha starts at one and whose only
    /// intermediate accesses are RGB-member reads or writes. The RGB math may
    /// be arbitrarily authored; no operation can observe or mutate alpha, so
    /// the final whole-vector output remains opaque without an effect-specific
    /// interpretation.
    static func isOpaqueCarrierOutput(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output,
                  in: tokens,
                  body: main.bodyRange
              ), expression.count == 1,
              let carrierToken = expression.first,
              carrierToken.kind == .identifier else {
            return false
        }
        let carrier = carrierToken.text
        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: main.bodyRange
              ), isOpaqueCarrierInitializer(initializer) else {
            return false
        }
        for use in (definition + 1)..<output where tokens[use].text == carrier {
            guard use + 2 < output,
                  tokens[use + 1].text == ".",
                  ["rgb", "xyz"].contains(tokens[use + 2].text) else {
                return false
            }
        }
        return true
    }

    private static func isOpaqueCarrierInitializer(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        if isOpaqueVectorConstruction(expression) { return true }
        let tokens = Array(expression)
        guard tokens.count == 4,
              ["CAST4", "vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(", tokens[3].text == ")",
              tokens[2].kind == .number,
              Double(tokens[2].text) == 1 else {
            return false
        }
        return true
    }

    static func isOpaqueVectorConstruction(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              let comma = topLevelCommas(tokens).last,
              comma + 2 == tokens.count - 1,
              tokens[comma + 1].kind == .number,
              Double(tokens[comma + 1].text) == 1 else {
            return false
        }
        return true
    }

    static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }

    static func topLevelCommas(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> [Int] {
        var depth = 0
        var result: [Int] = []
        for index in tokens.indices {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 1 { result.append(index) }
        }
        return result
    }
}
