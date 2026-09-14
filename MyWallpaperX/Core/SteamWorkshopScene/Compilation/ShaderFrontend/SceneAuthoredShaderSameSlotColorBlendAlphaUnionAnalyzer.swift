import Foundation

/// Proves a bounded straight-color flow with two full RGBA reads from one
/// graph input. Authored RGB uses one validated ApplyBlending helper while
/// alpha is the saturated union of the same two samples and the same scalar
/// factor. An optional distinct red-channel sample remains typed scalar data.
nonisolated enum SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let maskSlot: Int?
        let blendMode: Int
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              fragment.functions.filter({ $0.name == "main" }).count == 1,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (4 ... 24).contains(statements.count),
              noControlFlow(main, tokens: fragment.tokens),
              helpersDoNotSample(fragment, excluding: main),
              statements.count >= 2 else { return nil }

        let tokens = fragment.tokens
        let outputStatements = Array(statements.suffix(2))
        guard let rgb = rgbOutput(
                Array(tokens[outputStatements[0]]), fragment: fragment
              ), let alpha = alphaOutput(
                Array(tokens[outputStatements[1]])
              ), rgb.base == alpha.base,
              rgb.reflected == alpha.reflected,
              factorNames(rgb.factor) == alpha.factorNames,
              SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.validBlendHelper(
                fragment,
                mode: rgb.mode
              ) else { return nil }

        let samples = statements.compactMap { statement in
            fullColorSampleDeclaration(
                statement,
                tokens: tokens,
                fragment: fragment
            )
        }
        guard samples.count == 2,
              samples[0].name == rgb.base,
              samples[1].name == rgb.reflected,
              samples[0].slot == samples[1].slot,
              samples[0].statement.lowerBound < samples[1].statement.lowerBound,
              let mask = scalarMaskDeclaration(
                statements: statements,
                tokens: tokens,
                fragment: fragment,
                sourceSlot: samples[0].slot
              ), factorTerms(rgb.factor, fragment: fragment) == Set([
                "local:\(mask.name)",
                "uniform:\(rgb.factorUniform)",
              ]), exactSampleCalls(
                fragment,
                sourceSlot: samples[0].slot,
                maskSlot: mask.slot
              ), exactUses(
                fragment: fragment,
                main: main,
                samples: samples,
                mask: mask,
                factorUniform: rgb.factorUniform,
                outputStatements: outputStatements
              ) else { return nil }

        return .init(
            sourceSlot: samples[0].slot,
            maskSlot: mask.slot,
            blendMode: rgb.mode
        )
    }

    private struct Sample {
        let name: String
        let slot: Int
        let statement: Range<Int>
    }

    private struct Mask {
        let name: String
        let slot: Int?
        let statement: Range<Int>
    }

    private struct RGBOutput {
        let base: String
        let reflected: String
        let factor: [Token]
        let factorUniform: String
        let mode: Int
    }

    private struct AlphaOutput {
        let base: String
        let reflected: String
        let factorNames: Set<String>
    }

    private static func fullColorSampleDeclaration(
        _ statement: Range<Int>,
        tokens: [Token],
        fragment: Unit
    ) -> Sample? {
        let value = Array(tokens[statement])
        guard value.count >= 6,
              ["vec4", "float4"].contains(value[0].text),
              value[1].kind == .identifier,
              value[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(value[3...]),
              samplerType(slot, fragment: fragment) == "sampler2D" else {
            return nil
        }
        return .init(name: value[1].text, slot: slot, statement: statement)
    }

    private static func scalarMaskDeclaration(
        statements: [Range<Int>],
        tokens: [Token],
        fragment: Unit,
        sourceSlot: Int
    ) -> Mask? {
        let matches = statements.compactMap { statement -> Mask? in
            let value = Array(tokens[statement])
            guard value.count >= 4,
                  value[0].text == "float",
                  value[1].kind == .identifier,
                  value[2].text == "=" else { return nil }
            let expression = Array(value.dropFirst(3))
            if expression.count == 1,
               SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(expression[...]) == 1 {
                return .init(
                    name: value[1].text,
                    slot: nil,
                    statement: statement
                )
            }
            guard expression.count >= 3,
                  expression.suffix(2).map(\.text) == [".", "r"],
                  let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(expression.dropLast(2)),
                  slot != sourceSlot,
                  samplerType(slot, fragment: fragment) == "sampler2D" else {
                return nil
            }
            return .init(name: value[1].text, slot: slot, statement: statement)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func rgbOutput(
        _ statement: [Token], fragment: Unit
    ) -> RGBOutput? {
        guard statement.count >= 16,
              Array(statement.prefix(4)).map(\.text)
                == ["gl_FragColor", ".", "rgb", "="],
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(statement[4...]),
              call.name == "ApplyBlending",
              call.arguments.count == 4,
              let rawMode = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(call.arguments[0]),
              rawMode.rounded() == rawMode,
              let mode = Int(exactly: rawMode),
              (0 ... 32).contains(mode),
              let base = memberName(call.arguments[1], component: "rgb"),
              let reflected = memberName(call.arguments[2], component: "rgb"),
              base != reflected,
              let terms = productTerms(call.arguments[3]),
              terms.count == 2,
              terms.compactMap({ term -> String? in
                guard let name = identifier(term),
                      uniformType(name, fragment: fragment) == "float" else {
                    return nil
                }
                return name
              }).count == 1,
              let uniform = terms.compactMap({ term -> String? in
                guard let name = identifier(term),
                      uniformType(name, fragment: fragment) == "float" else {
                    return nil
                }
                return name
              }).first else { return nil }
        return .init(
            base: base,
            reflected: reflected,
            factor: Array(call.arguments[3]),
            factorUniform: uniform,
            mode: mode
        )
    }

    private static func alphaOutput(_ statement: [Token]) -> AlphaOutput? {
        guard statement.count >= 16,
              Array(statement.prefix(4)).map(\.text)
                == ["gl_FragColor", ".", "a", "="],
              let minimum = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(statement[4...]),
              minimum.name == "min",
              minimum.arguments.count == 2 else { return nil }
        let union: ArraySlice<Token>
        if SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .number(minimum.arguments[0]) == 1 {
            union = minimum.arguments[1]
        } else if SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .number(minimum.arguments[1]) == 1 {
            union = minimum.arguments[0]
        } else {
            return nil
        }
        guard let sum = split(union, operator: "+"),
              let base = memberName(sum[0], component: "a"),
              let product = productTerms(sum[1]),
              let reflectedTerm = product.first(where: {
                memberName($0, component: "a") != nil
              }),
              let reflected = memberName(reflectedTerm, component: "a"),
              product.filter({ memberName($0, component: "a") != nil }).count == 1
        else { return nil }
        let factor = product.filter {
            $0.startIndex != reflectedTerm.startIndex
                || $0.endIndex != reflectedTerm.endIndex
        }
        let names = factor.compactMap(identifier)
        guard factor.count == 2, names.count == 2,
              Set(names).count == 2 else { return nil }
        return .init(
            base: base,
            reflected: reflected,
            factorNames: Set(names)
        )
    }

    private static func exactSampleCalls(
        _ fragment: Unit,
        sourceSlot: Int,
        maskSlot: Int?
    ) -> Bool {
        let callIndices = fragment.tokens.indices.filter {
            ["texSample2D", "texture2D"].contains(fragment.tokens[$0].text)
        }
        let slots = callIndices.compactMap { index -> Int? in
            guard ["texSample2D", "texture2D"].contains(
                fragment.tokens[index].text
            ), index + 2 < fragment.tokens.count,
               fragment.tokens[index + 1].text == "(" else { return nil }
            return textureSlot(fragment.tokens[index + 2].text)
        }
        return slots.count == callIndices.count
            && slots.sorted() == ([sourceSlot, sourceSlot]
                + (maskSlot.map { [$0] } ?? [])).sorted()
            .sorted()
    }

    private static func exactUses(
        fragment: Unit,
        main: Unit.Function,
        samples: [Sample],
        mask: Mask,
        factorUniform: String,
        outputStatements: [Range<Int>]
    ) -> Bool {
        let tokens = fragment.tokens
        let outputRange = outputStatements[0].lowerBound
            ..< outputStatements[1].upperBound
        guard samples.allSatisfy({ sample in
            main.bodyRange.filter({ tokens[$0].text == sample.name }).count == 3
        }), main.bodyRange.filter({ tokens[$0].text == factorUniform }).count == 2,
              main.bodyRange.filter({ tokens[$0].text == "gl_FragColor" }).count == 2
        else { return false }

        for index in main.bodyRange where tokens[index].text == mask.name {
            if mask.statement.contains(index) || outputRange.contains(index) {
                continue
            }
            guard index + 1 < tokens.count,
                  ["*=", "="].contains(tokens[index + 1].text),
                  let statement = mainStatement(containing: index,
                                                body: main.bodyRange,
                                                tokens: tokens),
                  !statement.contains(where: {
                    ["texSample2D", "texture2D", "gl_FragColor"]
                        .contains(tokens[$0].text)
                  }) else { return false }
        }
        return true
    }

    private static func factorTerms(
        _ expression: [Token], fragment: Unit
    ) -> Set<String>? {
        guard let terms = productTerms(expression[...]), terms.count == 2 else {
            return nil
        }
        var result: Set<String> = []
        for term in terms {
            guard let name = identifier(term) else { return nil }
            result.insert(
                uniformType(name, fragment: fragment) == "float"
                    ? "uniform:\(name)" : "local:\(name)"
            )
        }
        return result.count == 2 ? result : nil
    }

    private static func factorNames(_ expression: [Token]) -> Set<String>? {
        guard let terms = productTerms(expression[...]), terms.count == 2 else {
            return nil
        }
        let names = terms.compactMap(identifier)
        return names.count == 2 && Set(names).count == 2 ? Set(names) : nil
    }

    private static func productTerms(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        splitMany(
            SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .strippingParentheses(expression),
            operator: "*"
        )
    }

    private static func split(
        _ expression: ArraySlice<Token>, operator operation: String
    ) -> [ArraySlice<Token>]? {
        let parts = splitMany(
            SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .strippingParentheses(expression),
            operator: operation
        )
        return parts?.count == 2 ? parts : nil
    }

    private static func splitMany(
        _ expression: ArraySlice<Token>, operator operation: String
    ) -> [ArraySlice<Token>]? {
        guard !expression.isEmpty else { return nil }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = expression.startIndex
        for index in expression.indices {
            if ["(", "["].contains(expression[index].text) { depth += 1 }
            if [")", "]"].contains(expression[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, expression[index].text == operation {
                guard start < index else { return nil }
                result.append(expression[start..<index])
                start = index + 1
            }
        }
        guard depth == 0, start < expression.endIndex else { return nil }
        result.append(expression[start..<expression.endIndex])
        return result
    }

    private static func memberName(
        _ expression: ArraySlice<Token>, component: String
    ) -> String? {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(expression)
        guard value.count == 3,
              value[value.startIndex].kind == .identifier,
              value[value.startIndex + 1].text == ".",
              value[value.startIndex + 2].text == component else { return nil }
        return value[value.startIndex].text
    }

    private static func identifier(_ expression: ArraySlice<Token>) -> String? {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(expression)
        return value.count == 1 && value.first?.kind == .identifier
            ? value.first?.text : nil
    }

    private static func samplerType(_ slot: Int, fragment: Unit) -> String? {
        let matches = fragment.declarations.filter {
            $0.storage == .uniform && $0.arraySize == nil
                && $0.name == "g_Texture\(slot)"
        }
        return matches.count == 1 ? matches[0].typeName : nil
    }

    private static func uniformType(_ name: String, fragment: Unit) -> String? {
        let matches = fragment.declarations.filter {
            $0.storage == .uniform && $0.arraySize == nil && $0.name == name
        }
        return matches.count == 1 ? matches[0].typeName : nil
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }

    private static func mainStatement(
        containing index: Int,
        body: Range<Int>,
        tokens: [Token]
    ) -> Range<Int>? {
        SceneAuthoredShaderUniformRGBMixAnalyzer
            .topLevelStatements(in: body, tokens: tokens)?
            .first(where: { $0.contains(index) })
    }

    private static func noControlFlow(
        _ main: Unit.Function, tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue", "?",
        ]
        return !main.bodyRange.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func helpersDoNotSample(
        _ fragment: Unit, excluding main: Unit.Function
    ) -> Bool {
        fragment.functions.allSatisfy { function in
            function.name == main.name || !function.bodyRange.contains(where: {
                ["texSample2D", "texture2D"].contains(fragment.tokens[$0].text)
            })
        }
    }
}
