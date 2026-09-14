import Foundation

/// Proves a representation-preserving weighted sum of repeated samples from
/// one texture slot. The proof is deliberately independent of effect names,
/// shader paths, kernel sizes, and coordinate math.
nonisolated enum SceneAuthoredShaderNormalizedSampleSumAnalyzer {
    typealias Unit = SceneAuthoredShaderSyntaxUnit
    typealias Token = SceneAuthoredShaderToken

    static func sourceSlot(fragmentSource source: String) -> Int? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let outputUses = fragment.tokens.indices.filter {
            fragment.tokens[$0].text == "gl_FragColor"
        }
        return analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output, tokens: tokens, body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output,
                      in: tokens,
                      body: main.bodyRange
                  ),
              helperDoesNotBranch(main, tokens: tokens),
              let source = outputSource(
                  expression,
                  output: output,
                  tokens: tokens,
                  main: main
              )
        else { return nil }

        let mainSampleCount = main.bodyRange.filter {
            isTextureSample(at: $0, tokens: tokens)
        }.count
        switch source {
        case let .inline(sum):
            return mainSampleCount == sum.sampleCount ? sum.slot : nil
        case let .helper(call):
            let matches = fragment.functions.filter { $0.name == call.name }
            guard mainSampleCount == 0,
                  matches.count == 1,
                  let helper = matches.first,
                  ["vec4", "float4"].contains(helper.returnType),
                  !helper.parameterRange.contains(where: {
                      $0 < tokens.count && tokens[$0].text.contains("sampler")
                  }),
                  helperDoesNotBranch(helper, tokens: tokens),
                  let returned = singleReturnExpression(helper, tokens: tokens),
                  let sum = normalizedSampleSum(returned),
                  helper.bodyRange.filter({
                      isTextureSample(at: $0, tokens: tokens)
                  }).count == sum.sampleCount
            else { return nil }
            return sum.slot
        }
    }

    private struct Call {
        let name: String
    }

    private struct Sum {
        let slot: Int
        let sampleCount: Int
    }

    private enum OutputSource {
        case helper(Call)
        case inline(Sum)
    }

    /// Accepts either a direct helper call or one immutable local carrier.
    /// The carrier proof is intentionally exact: one declaration/initializer
    /// and one terminal read. Any mutation, additional read, or conditional
    /// definition leaves the color transfer unresolved.
    private static func outputSource(
        _ expression: ArraySlice<Token>,
        output: Int,
        tokens: [Token],
        main: Unit.Function
    ) -> OutputSource? {
        if let direct = functionCall(expression) { return .helper(direct) }
        guard expression.count == 1,
              let carrierToken = expression.first,
              carrierToken.kind == .identifier else { return nil }
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
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: definition,
                      in: tokens,
                      body: main.bodyRange
                  ) else { return nil }
        let uses = main.bodyRange.filter { tokens[$0].text == carrier }
        guard uses.count == 2,
              uses.contains(definition),
              uses.contains(expression.startIndex) else { return nil }
        if let call = functionCall(initializer) { return .helper(call) }
        return normalizedSampleSum(initializer).map(OutputSource.inline)
    }

    private static func functionCall(_ expression: ArraySlice<Token>) -> Call? {
        let values = Array(expression)
        guard values.count >= 3,
              values[0].kind == .identifier,
              values[1].text == "(",
              SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: values, opening: 1
              ) == values.count - 1 else { return nil }
        return .init(name: values[0].text)
    }

    private static func helperDoesNotBranch(
        _ helper: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let rejected = Set([
            "if", "else", "for", "while", "do", "switch", "discard",
            "break", "continue",
        ])
        return !helper.bodyRange.contains { rejected.contains(tokens[$0].text) }
    }

    private static func singleReturnExpression(
        _ helper: Unit.Function,
        tokens: [Token]
    ) -> ArraySlice<Token>? {
        let returns = helper.bodyRange.filter { tokens[$0].text == "return" }
        guard returns.count == 1, let start = returns.first else { return nil }
        var cursor = start + 1
        var depth = 0
        while cursor < helper.bodyRange.upperBound {
            let text = tokens[cursor].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            if text == ";", depth == 0 {
                return tokens[(start + 1)..<cursor]
            }
            guard depth >= 0 else { return nil }
            cursor += 1
        }
        return nil
    }

    private static func normalizedSampleSum(
        _ expression: ArraySlice<Token>
    ) -> Sum? {
        let values = stripOuterParentheses(Array(expression))
        guard !values.isEmpty else { return nil }
        var ranges: [Range<Int>] = []
        var start = 0
        var depth = 0
        for index in values.indices {
            let text = values[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, text == "+" {
                ranges.append(start..<index)
                start = index + 1
            } else if depth == 0, text == "-" {
                return nil
            }
        }
        guard depth == 0 else { return nil }
        ranges.append(start..<values.count)
        guard (1...32).contains(ranges.count) else { return nil }

        var slot: Int?
        var total = 0.0
        var authoredRoundingBound = 0.0
        for range in ranges {
            guard let term = sampleTerm(Array(values[range])) else { return nil }
            if let slot, slot != term.slot { return nil }
            slot = term.slot
            total += term.weight
            authoredRoundingBound += term.roundingBound
        }
        guard let slot, total.isFinite,
              abs(total - 1) <= max(1e-9, Double(ranges.count) * 1e-12)
                + authoredRoundingBound
        else { return nil }
        return .init(slot: slot, sampleCount: ranges.count)
    }

    private static func sampleTerm(
        _ raw: [Token]
    ) -> (slot: Int, weight: Double, roundingBound: Double)? {
        let values = stripOuterParentheses(raw)
        var depth = 0
        var multiplications: [Int] = []
        for index in values.indices {
            let text = values[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            if depth == 0, text == "*" { multiplications.append(index) }
        }
        guard depth == 0, multiplications.count == 1,
              let split = multiplications.first else { return nil }
        let left = Array(values[..<split])
        let right = Array(values[(split + 1)...])
        if let slot = sampleSlot(left), let literal = positiveLiteral(right) {
            return (slot, literal.value, literal.roundingBound)
        }
        if let literal = positiveLiteral(left), let slot = sampleSlot(right) {
            return (slot, literal.value, literal.roundingBound)
        }
        return nil
    }

    private static func sampleSlot(_ raw: [Token]) -> Int? {
        let values = stripOuterParentheses(raw)
        guard values.count >= 6,
              ["texSample2D", "texture2D", "texture"].contains(values[0].text),
              values[1].text == "(",
              SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: values, opening: 1
              ) == values.count - 1,
              values[2].kind == .identifier,
              values[2].text.hasPrefix("g_Texture"),
              let slot = Int(values[2].text.dropFirst("g_Texture".count)),
              (0..<8).contains(slot),
              values[3].text == "," else { return nil }
        return slot
    }

    private static func positiveLiteral(
        _ raw: [Token]
    ) -> (value: Double, roundingBound: Double)? {
        let values = stripOuterParentheses(raw)
        guard values.count == 1,
              values[0].kind == .number,
              !values[0].text.lowercased().contains("e"),
              let value = Double(values[0].text),
              value.isFinite, value > 0 else { return nil }
        let parts = values[0].text.split(separator: ".", omittingEmptySubsequences: false)
        let digits = parts.count == 2 ? parts[1].count : 0
        let bound = digits >= 5 ? 0.5 * pow(10, -Double(digits)) : 0
        return (value, bound)
    }

    private static func stripOuterParentheses(_ raw: [Token]) -> [Token] {
        var values = raw
        while values.count >= 2,
              values.first?.text == "(",
              SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: values, opening: 0
              ) == values.count - 1 {
            values.removeFirst()
            values.removeLast()
        }
        return values
    }

    private static func isTextureSample(at index: Int, tokens: [Token]) -> Bool {
        index < tokens.count
            && ["texSample2D", "texture2D", "texture"].contains(tokens[index].text)
            && index + 1 < tokens.count
            && tokens[index + 1].text == "("
    }
}
