import Foundation

/// Proves a bounded RGB reconstruction whose base, channel sources, and
/// coordinate-driving samples all come from one texture slot. The output alpha
/// must copy the blend base alpha unchanged.
nonisolated enum SceneAuthoredShaderSameSlotChannelReconstructionAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct Sample {
        let name: String
        let definition: Int
        let slot: Int
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        if let slot = SceneAuthoredShaderSameSlotCarrierBlendAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return slot
        }
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens),
              statements.last?.contains(output) == true,
              !containsControlFlow(main.bodyRange, tokens: tokens),
              helperFunctionsDoNotSampleTextures(fragment, excluding: main),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let samples = samples(
                statements: statements,
                before: output,
                fragment: fragment,
                body: main.bodyRange
              ),
              let slot = samples.first?.slot,
              samples.allSatisfy({ $0.slot == slot }),
              Set(samples.map(\.name)).count == samples.count else {
            return nil
        }
        if directComponentReconstructionSlot(
            outputExpression: outputExpression,
            output: output,
            statements: statements,
            samples: samples,
            tokens: tokens,
            body: main.bodyRange
        ) == slot {
            return slot
        }
        guard SceneAuthoredShaderStraightBlendOutputAnalyzer
                .hasNormalBlendHelper(fragment),
              let outputArguments = callArguments(
                outputExpression, names: ["vec4", "float4"], count: 2
              ), let color = identifier(outputArguments[0]),
              let alpha = identifier(outputArguments[1]),
              samples.count >= 4,
              let alphaDefinition = definition(
                alpha, type: ["float"], statements: statements,
                before: output, tokens: tokens
              ), let alphaExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: alphaDefinition, in: tokens, body: main.bodyRange
                ), let base = memberName(alphaExpression, component: "a"),
              let baseSample = samples.first(where: { $0.name == base }),
              let colorDefinition = definition(
                color, type: ["vec3", "float3"], statements: statements,
                before: alphaDefinition, tokens: tokens
              ), let colorExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: colorDefinition, in: tokens, body: main.bodyRange
                ), let channelNames = reconstructedChannelNames(colorExpression),
              Set(channelNames).count == 3,
              !channelNames.contains(base),
              channelNames.allSatisfy({ name in
                  samples.contains(where: { $0.name == name })
              }),
              let blendWrite = uniqueAssignment(
                color, after: colorDefinition, before: alphaDefinition,
                tokens: tokens
              ), let blendExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: blendWrite, in: tokens, body: main.bodyRange
                ), let blendArguments = callArguments(
                    blendExpression, names: ["ApplyBlending"], count: 4
                ), member(blendArguments[1], name: base, component: "rgb"),
              identifierOrRGBMember(blendArguments[2]) == color,
              exactUses(
                baseSample,
                expected: [blendArguments[1].startIndex, alphaExpression.startIndex],
                before: output,
                tokens: tokens
              ), exactUses(
                named: color,
                definition: colorDefinition,
                expected: [
                    blendWrite,
                    blendArguments[2].startIndex,
                    outputArguments[0].startIndex,
                ],
                before: outputExpression.endIndex,
                tokens: tokens
              ), exactUses(
                named: alpha,
                definition: alphaDefinition,
                expected: [outputArguments[1].startIndex],
                before: outputExpression.endIndex,
                tokens: tokens
              ), channelNames.allSatisfy({ name in
                  guard let sample = samples.first(where: { $0.name == name }),
                        let use = channelUse(
                            name,
                            in: colorExpression,
                            component: component(for: name, in: channelNames)
                        ) else { return false }
                  return exactUses(
                    sample, expected: [use], before: output, tokens: tokens
                  )
              }), main.bodyRange.filter({
                  tokens[$0].text == "ApplyBlending"
              }) == [blendExpression.startIndex] else {
            return nil
        }
        return slot
    }

    /// Proves the post-preprocessing stock channel-offset shape without
    /// depending on its variable spelling or effect identity:
    ///
    ///     vec4 output = baseSample;
    ///     output.r = shiftedRed.r;
    ///     output.b = shiftedBlue.b;
    ///     gl_FragColor = output;
    ///
    /// Every sampled value must come from the same slot, every non-base sample
    /// must feed exactly one matching RGB component, and alpha must have no
    /// write at all.
    private static func directComponentReconstructionSlot(
        outputExpression: ArraySlice<Token>,
        output: Int,
        statements: [Range<Int>],
        samples: [Sample],
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        guard samples.count >= 2,
              let carrier = identifier(outputExpression),
              let carrierDefinition = definition(
                carrier,
                type: ["vec4", "float4"],
                statements: statements,
                before: output,
                tokens: tokens
              ),
              let carrierExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: carrierDefinition,
                    in: tokens,
                    body: body
                ),
              let base = identifier(carrierExpression),
              let baseSample = samples.first(where: { $0.name == base }) else {
            return nil
        }

        var carrierWrites: [Int] = []
        var sourceUses: [(sample: Sample, use: Int, component: String)] = []
        for index in (carrierDefinition + 1)..<output where tokens[index].text == carrier {
            guard index + 3 < output,
                  tokens[index + 1].text == ".",
                  ["r", "g", "b"].contains(tokens[index + 2].text),
                  tokens[index + 3].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: index + 2,
                        in: tokens,
                        body: body
                    ),
                  let source = memberName(
                    expression,
                    component: tokens[index + 2].text
                  ),
                  source != base,
                  let sample = samples.first(where: { $0.name == source }) else {
                return nil
            }
            carrierWrites.append(index)
            sourceUses.append((sample, expression.startIndex, tokens[index + 2].text))
        }

        guard !carrierWrites.isEmpty,
              Set(sourceUses.map(\.component)).count == sourceUses.count,
              Set(sourceUses.map({ $0.sample.name })).count == sourceUses.count,
              samples.count == sourceUses.count + 1,
              exactUses(
                baseSample,
                expected: [carrierExpression.startIndex],
                before: output,
                tokens: tokens
              ),
              sourceUses.allSatisfy({ use in
                  exactUses(
                    use.sample,
                    expected: [use.use],
                    before: output,
                    tokens: tokens
                  )
              }),
              exactUses(
                named: carrier,
                definition: carrierDefinition,
                expected: carrierWrites + [outputExpression.startIndex],
                before: outputExpression.endIndex,
                tokens: tokens
              ) else {
            return nil
        }
        return baseSample.slot
    }

    private static func samples(
        statements: [Range<Int>],
        before boundary: Int,
        fragment: Unit,
        body: Range<Int>
    ) -> [Sample]? {
        let tokens = fragment.tokens
        var result: [Sample] = []
        for statement in statements where statement.lowerBound < boundary {
            let sampleCalls = statement.filter {
                ["texSample2D", "texture2D"].contains(tokens[$0].text)
            }
            guard sampleCalls.count <= 1 else { return nil }
            guard !sampleCalls.isEmpty else { continue }
            let definition = statement.lowerBound + 1
            guard statement.count >= 6,
                  ["vec4", "float4"].contains(tokens[statement.lowerBound].text),
                  tokens[definition].kind == .identifier,
                  tokens[definition + 1].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: definition,
                        in: tokens,
                        body: body
                    ), let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(expression) else { return nil }
            result.append(.init(
                name: tokens[definition].text,
                definition: definition,
                slot: slot
            ))
        }
        let allCalls = body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        return allCalls.count == result.count ? result : nil
    }

    private static func reconstructedChannelNames(
        _ expression: ArraySlice<Token>
    ) -> [String]? {
        guard let outer = callArguments(
            expression, names: ["vec3", "float3", "vec4", "float4"],
            count: expression.first?.text == "vec4"
                || expression.first?.text == "float4" ? 4 : 3
        ), outer.count >= 3 else { return nil }
        if outer.count == 4 {
            guard outer[3].count == 1, outer[3].first?.kind == .number else {
                return nil
            }
        }
        let components = ["r", "g", "b"]
        let names = zip(outer.prefix(3), components).compactMap {
            memberName($0.0, component: $0.1)
        }
        return names.count == 3 ? names : nil
    }

    private static func definition(
        _ name: String,
        type: Set<String>,
        statements: [Range<Int>],
        before boundary: Int,
        tokens: [Token]
    ) -> Int? {
        let matches = statements.compactMap { statement -> Int? in
            guard statement.lowerBound < boundary,
                  statement.count >= 3,
                  type.contains(tokens[statement.lowerBound].text),
                  tokens[statement.lowerBound + 1].text == name,
                  tokens[statement.lowerBound + 2].text == "=" else { return nil }
            return statement.lowerBound + 1
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func uniqueAssignment(
        _ name: String,
        after definition: Int,
        before boundary: Int,
        tokens: [Token]
    ) -> Int? {
        let matches = ((definition + 1)..<boundary).filter {
            tokens[$0].text == name && tokens[$0 + 1].text == "="
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func exactUses(
        _ sample: Sample,
        expected: [Int],
        before boundary: Int,
        tokens: [Token]
    ) -> Bool {
        exactUses(
            named: sample.name,
            definition: sample.definition,
            expected: expected,
            before: boundary,
            tokens: tokens
        )
    }

    private static func exactUses(
        named name: String,
        definition: Int,
        expected: [Int],
        before boundary: Int,
        tokens: [Token]
    ) -> Bool {
        ((definition + 1)..<boundary).filter {
            tokens[$0].text == name
        } == expected.sorted()
    }

    private static func channelUse(
        _ name: String,
        in expression: ArraySlice<Token>,
        component: String?
    ) -> Int? {
        guard let component else { return nil }
        let matches = expression.indices.filter { index in
            index + 2 < expression.endIndex
                && expression[index].text == name
                && expression[index + 1].text == "."
                && expression[index + 2].text == component
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func component(for name: String, in names: [String]) -> String? {
        guard let index = names.firstIndex(of: name) else { return nil }
        return ["r", "g", "b"][index]
    }

    private static func containsControlFlow(
        _ body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue",
        ]
        return body.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func helperFunctionsDoNotSampleTextures(
        _ fragment: Unit,
        excluding main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        return fragment.functions.allSatisfy { function in
            function.name == main.name || !function.bodyRange.contains(where: {
                ["texSample2D", "texture2D"].contains(tokens[$0].text)
            })
        }
    }

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        names: Set<String>,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard expression.count >= 3,
              names.contains(expression.first?.text ?? ""),
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")" else { return nil }
        let values = split(expression.dropFirst(2).dropLast())
        return values.count == count ? values : nil
    }

    private static func split(
        _ tokens: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        guard !tokens.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = tokens.startIndex
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return [] }
                result.append(tokens[start..<index])
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return [] }
        }
        guard depth == 0, start < tokens.endIndex else { return [] }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    private static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        tokens.count == 1 && tokens.first?.kind == .identifier
            ? tokens.first?.text : nil
    }

    private static func identifierOrRGBMember(
        _ tokens: ArraySlice<Token>
    ) -> String? {
        identifier(tokens) ?? memberName(tokens, component: "rgb")
    }

    private static func member(
        _ tokens: ArraySlice<Token>, name: String, component: String
    ) -> Bool {
        memberName(tokens, component: component) == name
    }

    private static func memberName(
        _ tokens: ArraySlice<Token>, component: String
    ) -> String? {
        guard tokens.count == 3,
              tokens[tokens.startIndex].kind == .identifier,
              tokens[tokens.startIndex + 1].text == ".",
              tokens[tokens.startIndex + 2].text == component else { return nil }
        return tokens[tokens.startIndex].text
    }
}
