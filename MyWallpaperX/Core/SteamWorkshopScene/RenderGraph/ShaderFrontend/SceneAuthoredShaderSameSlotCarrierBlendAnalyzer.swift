import Foundation

/// Proves the linear carrier form used by authored channel-offset shaders:
/// one same-slot RGBA carrier, bounded matching RGB component replacements,
/// and one terminal same-slot RGB blend. Alpha remains the carrier alpha.
nonisolated enum SceneAuthoredShaderSameSlotCarrierBlendAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens),
              statements.last?.contains(output) == true,
              !containsControlFlow(main.bodyRange, tokens: tokens),
              helpersDoNotSample(fragment, excluding: main),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output, in: tokens, body: main.bodyRange
                ),
              let carrier = identifier(outputExpression),
              let carrierDefinition = carrierDefinition(
                    carrier,
                    statements: statements,
                    before: output,
                    tokens: tokens,
                    body: main.bodyRange
              ),
              let slot = directSampleSlot(carrierDefinition.expression),
              let baseCall = sampleCallStart(carrierDefinition.expression)
        else { return nil }

        var recognizedCalls = [baseCall]
        var carrierUses: [Int] = []
        var projectedComponents: [String] = []
        var blendCount = 0

        for statement in statements where
            statement.lowerBound > carrierDefinition.nameIndex
                && statement.lowerBound < output
        {
            let calls = sampleCalls(in: statement, tokens: tokens)
            guard !calls.isEmpty else { continue }
            guard statement.count >= 5,
                  tokens[statement.lowerBound].text == carrier,
                  tokens[statement.lowerBound + 1].text == ".",
                  tokens[statement.lowerBound + 3].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: statement.lowerBound + 2,
                        in: tokens,
                        body: main.bodyRange
                    ) else { return nil }

            let component = tokens[statement.lowerBound + 2].text
            switch component {
            case "r", "g", "b":
                guard calls.count == 1,
                      let sampled = directSampleMember(expression),
                      sampled.slot == slot,
                      sampled.component == component else { return nil }
                projectedComponents.append(component)
                carrierUses.append(statement.lowerBound)
                recognizedCalls.append(sampled.callStart)
            case "rgb":
                guard blendCount == 0,
                      calls.count == 1,
                      let arguments = callArguments(
                        expression, name: "ApplyBlending", count: 4
                      ),
                      let sampled = directSampleMember(arguments[1]),
                      sampled.slot == slot,
                      sampled.component == "rgb",
                      member(arguments[2], name: carrier, component: "rgb"),
                      sampleCalls(in: arguments[0], tokens: tokens).isEmpty,
                      sampleCalls(in: arguments[3], tokens: tokens).isEmpty
                else { return nil }
                blendCount = 1
                carrierUses.append(statement.lowerBound)
                carrierUses.append(arguments[2].startIndex)
                recognizedCalls.append(sampled.callStart)
            default:
                return nil
            }
        }

        let allCalls = sampleCalls(in: main.bodyRange, tokens: tokens)
        guard (1 ... 3).contains(projectedComponents.count),
              Set(projectedComponents).count == projectedComponents.count,
              blendCount == 1,
              recognizedCalls.sorted() == allCalls,
              exactCarrierUses(
                carrier,
                definition: carrierDefinition.nameIndex,
                expected: carrierUses + [outputExpression.startIndex],
                before: outputExpression.endIndex,
                tokens: tokens
              ) else { return nil }
        return slot
    }

    private static func carrierDefinition(
        _ name: String,
        statements: [Range<Int>],
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> (nameIndex: Int, expression: ArraySlice<Token>)? {
        let matches = statements.compactMap { statement
            -> (Int, ArraySlice<Token>)? in
            guard statement.lowerBound < boundary,
                  statement.count >= 4,
                  ["vec4", "float4"].contains(
                    tokens[statement.lowerBound].text
                  ),
                  tokens[statement.lowerBound + 1].text == name,
                  tokens[statement.lowerBound + 2].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: statement.lowerBound + 1,
                        in: tokens,
                        body: body
                    ) else { return nil }
            return (statement.lowerBound + 1, expression)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func directSampleSlot(
        _ expression: ArraySlice<Token>
    ) -> Int? {
        SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(
            expression
        )
    }

    private static func directSampleMember(
        _ expression: ArraySlice<Token>
    ) -> (slot: Int, component: String, callStart: Int)? {
        guard expression.count > 2,
              expression[expression.endIndex - 2].text == ".",
              let component = expression.last?.text,
              ["r", "g", "b", "rgb"].contains(component),
              let slot = directSampleSlot(expression.dropLast(2)) else {
            return nil
        }
        return (slot, component, expression.startIndex)
    }

    private static func sampleCallStart(
        _ expression: ArraySlice<Token>
    ) -> Int? {
        guard directSampleSlot(expression) != nil else { return nil }
        return expression.startIndex
    }

    private static func sampleCalls(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Int] {
        range.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
    }

    private static func sampleCalls(
        in expression: ArraySlice<Token>,
        tokens: [Token]
    ) -> [Int] {
        expression.indices.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
    }

    private static func exactCarrierUses(
        _ name: String,
        definition: Int,
        expected: [Int],
        before boundary: Int,
        tokens: [Token]
    ) -> Bool {
        ((definition + 1)..<boundary).filter {
            tokens[$0].text == name
        } == expected.sorted()
    }

    private static func identifier(
        _ expression: ArraySlice<Token>
    ) -> String? {
        expression.count == 1 && expression.first?.kind == .identifier
            ? expression.first?.text : nil
    }

    private static func member(
        _ expression: ArraySlice<Token>,
        name: String,
        component: String
    ) -> Bool {
        expression.count == 3
            && expression[expression.startIndex].text == name
            && expression[expression.startIndex + 1].text == "."
            && expression[expression.startIndex + 2].text == component
    }

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        name: String,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard expression.count >= 3,
              expression.first?.text == name,
              expression[expression.startIndex + 1].text == "(",
              expression.last?.text == ")" else { return nil }
        let arguments = split(expression.dropFirst(2).dropLast())
        return arguments.count == count ? arguments : nil
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

    private static func helpersDoNotSample(
        _ fragment: Unit,
        excluding main: Unit.Function
    ) -> Bool {
        fragment.functions.allSatisfy { function in
            function.name == main.name || !function.bodyRange.contains(where: {
                ["texSample2D", "texture2D"].contains(
                    fragment.tokens[$0].text
                )
            })
        }
    }
}
