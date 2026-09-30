import Foundation

nonisolated extension SceneAuthoredShaderColorTransferAnalyzer {
    struct DirectCarrierFact {
        let slot: Int
        let rgbWrites: Int
        let alphaWrites: Int
    }

    /// The direct-carrier proof is intentionally stricter than the historical
    /// independent-alpha fallback.  It accepts only one sampled local and
    /// unconditional member writes; aliases, whole-vector writes, swizzles,
    /// extra samples, control flow, and alpha resets after RGB mutation are
    /// rejected so ordinary framebuffer colors cannot be promoted to an
    /// independent signal contract.
    static func directCarrierFact(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> DirectCarrierFact? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output, in: tokens, body: main.bodyRange
              ),
              expression.count == 1,
              let carrier = expression.first,
              carrier.kind == .identifier,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                  .topLevelStatements(in: main.bodyRange, tokens: tokens),
              !statements.isEmpty,
              statements.last?.contains(output) == true,
              !containsForbiddenDirectCarrierControlFlow(
                  main.bodyRange, tokens: tokens
              ) else { return nil }

        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index < output
                && tokens[index].text == carrier.text
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: main.bodyRange),
              let initializer = assignmentExpression(
                  after: definition, in: tokens, body: main.bodyRange
              ),
              let slot = directTextureSampleSlot(initializer),
              let sampleSlots = textureSampleSlots(
                  in: main.bodyRange, tokens: tokens
              ),
              sampleSlots == [slot],
              carrierDefinitionIsTopLevel(
                  definition, statements: statements
              ),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: statements
                      .filter { $0.lowerBound > definition && $0.upperBound <= output }
              ) else { return nil }

        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        var rgbWrites = 0
        var alphaWrites = 0
        var rgbWasWritten = false
        var alphaResetToOne = false

        for use in (definition + 1)..<output where tokens[use].text == carrier.text {
            guard use + 2 < output,
                  tokens[use + 1].text == ".",
                  ["rgb", "a"].contains(tokens[use + 2].text) else {
                // A bare carrier use is an alias/escape.  The sole output
                // expression was checked above and is outside this range.
                return nil
            }
            let member = tokens[use + 2].text
            let operatorIndex = use + 3
            guard operatorIndex < output else { return nil }
            let operation = tokens[operatorIndex].text
            guard assignmentOperators.contains(operation) else { continue }
            guard isUnconditionalWrite(
                use, tokens: tokens, body: main.bodyRange
            ), let rhs = memberAssignmentExpression(
                after: operatorIndex, tokens: tokens, body: main.bodyRange,
                boundary: output
            ) else { return nil }

            switch member {
            case "rgb":
                guard !expressionContainsTextureSample(rhs),
                      directCarrierRGBExpressionIsSafe(
                          rhs,
                          carrier: carrier.text,
                          operation: operation,
                          fragment: fragment
                      ) else { return nil }
                rgbWrites += 1
                rgbWasWritten = true
            case "a":
                guard directCarrierAlphaExpressionIsSafe(
                    rhs,
                    carrier: carrier.text,
                    fragment: fragment
                ) else { return nil }
                if expressionIsOne(rhs) { alphaResetToOne = true }
                alphaWrites += 1
            default:
                return nil
            }
        }

        // A one-valued alpha reset following a color mutation is the bounded
        // independent-signal producer shape, not ordinary framebuffer
        // coverage.  Leave it to the typed independent analyzer (or reject).
        guard !(rgbWasWritten && alphaResetToOne),
              rgbWrites > 0 || alphaWrites > 0 else { return nil }
        return DirectCarrierFact(
            slot: slot,
            rgbWrites: rgbWrites,
            alphaWrites: alphaWrites
        )
    }

    /// Proves one sampled carrier whose RGB is transformed in place while its
    /// alpha is copied unchanged to the sole output. Every replacement RGB
    /// assignment must still read the carrier RGB, and no other texture sample
    /// may participate, so arbitrary uniform/helper math cannot invent a
    /// second color source.
    static func preservedAlphaRGBMutationSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count >= 9,
              ["vec4", "float4"].contains(output[0].text),
              output[1].text == "(",
              output.last?.text == ")",
              outerCallClosesAtEnd(output),
              topLevelCommas(output).count == 1,
              let comma = topLevelCommas(output).first else { return nil }
        let rgb = Array(output[2..<comma])
        let alpha = Array(output[(comma + 1)..<(output.count - 1)])
        guard alpha.count == 3,
              alpha[0].kind == .identifier,
              alpha[1].text == ".",
              alpha[2].text == "a" else { return nil }
        let carrier = alpha[0].text
        let rgbUses = rgb.indices.filter { rgb[$0].text == carrier }
        guard !rgbUses.isEmpty,
              rgbUses.allSatisfy({ index in
                  index + 2 < rgb.count
                      && rgb[index + 1].text == "."
                      && rgb[index + 2].text == "rgb"
              }) else { return nil }

        let definitions = body.filter { index in
            index > body.lowerBound
                && index + 1 < outputAssignment
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ), let slot = directTextureSampleSlot(initializer),
              textureSampleSlots(in: body, tokens: tokens) == [slot] else {
            return nil
        }

        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for use in tokens.indices where use > definition && use < outputAssignment
            && tokens[use].text == carrier {
            guard use + 2 < outputAssignment,
                  tokens[use + 1].text == ".",
                  tokens[use + 2].text == "rgb" else { return nil }
            guard use + 3 < outputAssignment,
                  operators.contains(tokens[use + 3].text) else { continue }
            if tokens[use + 3].text == "=" {
                guard let semicolon = (use + 4..<outputAssignment).first(
                    where: { tokens[$0].text == ";" }
                ), (use + 4..<semicolon).contains(where: { index in
                    index + 2 < semicolon
                        && tokens[index].text == carrier
                        && tokens[index + 1].text == "."
                        && tokens[index + 2].text == "rgb"
                }) else { return nil }
            }
        }
        return slot
    }

    /// Proves a sampled local with no RGB writes and one root alpha write.
    /// The emitter applies the straight-color boundary around authored math.
    static func mutatedStraightAlphaSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count == 1, output[0].kind == .identifier else {
            return nil
        }
        let colorName = output[0].text
        let definitions = body.filter { index in
            index + 1 < outputAssignment
                && tokens[index].text == colorName
                && index > body.lowerBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ),
              let slot = directTextureSampleSlot(initializer) else {
            return nil
        }
        guard let sampleSlots = textureSampleSlots(in: body, tokens: tokens),
              sampleSlots.filter({ $0 == slot }).count == 1,
              Set(sampleSlots.filter({ $0 != slot })).count == sampleSlots.count - 1
        else { return nil }

        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        var alphaWrites = 0
        for use in tokens.indices where use > definition && use < outputAssignment
            && tokens[use].text == colorName {
            guard use + 2 < outputAssignment,
                  tokens[use + 1].text == ".",
                  ["rgb", "a"].contains(tokens[use + 2].text) else {
                return nil
            }
            let member = tokens[use + 2].text
            let next = use + 3 < outputAssignment ? tokens[use + 3].text : ""
            guard !assignmentOperators.contains(next) || member == "a" else {
                return nil
            }
            if member == "a", assignmentOperators.contains(next) {
                guard isUnconditionalWrite(use, tokens: tokens, body: body) else {
                    return nil
                }
                alphaWrites += 1
            }
        }
        return alphaWrites == 1 ? slot : nil
    }

    static func mutatedStraightAlphaSlot(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < fragment.tokens.count,
              fragment.tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(
                  output,
                  tokens: fragment.tokens,
                  body: main.bodyRange
              ),
              let expression = assignmentExpression(
                  after: output,
                  in: fragment.tokens,
                  body: main.bodyRange
              ) else {
            return nil
        }
        return mutatedStraightAlphaSlot(
            expression,
            outputAssignment: output,
            tokens: fragment.tokens,
            body: main.bodyRange
        )
    }

    static func analyzedMain(
        _ source: String
    ) -> (
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function,
        outputUses: [Int]
    )? {
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
        return (
            fragment,
            main,
            fragment.tokens.indices.filter {
                fragment.tokens[$0].text == "gl_FragColor"
            }
        )
    }

    private static func textureSampleSlots(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Int]? {
        var slots: [Int] = []
        for index in range where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 2 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let slot = SceneShaderSourceTextFacts.textureSlot(tokens[index + 2].text) else {
                return nil
            }
            slots.append(slot)
        }
        return slots
    }

    static func straightAlphaSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count >= 9,
              ["vec4", "float4"].contains(output[0].text),
              output[1].text == "(",
              output.last?.text == ")",
              outerCallClosesAtEnd(output),
              topLevelCommas(output).count == 1,
              let comma = topLevelCommas(output).first,
              comma == 5,
              output[2].kind == .identifier,
              output[3].text == ".",
              output[4].text == "rgb" else {
            return nil
        }
        let colorName = output[2].text
        let alpha = Array(output[(comma + 1)..<(output.count - 1)])
        let colorUses = alpha.indices.filter { index in
            alpha[index].text == colorName
        }
        let alphaMembers = alpha.indices.filter { index in
            guard index + 2 < alpha.count else { return false }
            return alpha[index].kind == .identifier
                && alpha[index + 1].text == "."
                && alpha[index + 2].text == "a"
        }
        guard colorUses.count == 1,
              let alphaUse = colorUses.first,
              alphaUse + 2 < alpha.count,
              alpha[alphaUse + 1].text == ".",
              alpha[alphaUse + 2].text == "a",
              alphaMembers.allSatisfy({ alpha[$0].text == colorName }) else {
            return nil
        }

        let definitions = body.filter { index in
            index + 1 < outputAssignment
                && tokens[index].text == colorName
                && index > body.lowerBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ),
              let slot = directTextureSampleSlot(initializer) else {
            return nil
        }
        let sampleCalls = body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        guard sampleCalls.count == 1 else { return nil }
        let intermediateUses = tokens.indices.filter {
            $0 > definition && $0 < outputAssignment && tokens[$0].text == colorName
        }
        return intermediateUses.isEmpty ? slot : nil
    }
}
