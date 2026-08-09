import Foundation

/// Proves one bounded straight-color replacement flow. A single sampled
/// source participates in a normal blend whose weight is also the output
/// alpha; the emitted boundary can therefore unpremultiply the source and
/// premultiply the authored `vec4(rgb, alpha)` result.
nonisolated enum SceneAuthoredShaderStraightBlendOutputAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private enum BlendHelper {
        case normal
        case additive
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              rootAssignment(output, tokens: tokens, body: main.bodyRange),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let outputArguments = callArguments(
                outputExpression, function: ["vec4", "float4"], count: 2
              ), let color = identifier(outputArguments[0]),
              let alpha = identifier(outputArguments[1]) else {
            return nil
        }
        guard let colorDefinition = uniqueDefinition(
                color, types: ["vec3", "float3"], before: output,
                tokens: tokens, body: main.bodyRange
              ), let alphaDefinition = uniqueDefinition(
                alpha, types: ["float"], before: output,
                tokens: tokens, body: main.bodyRange
              ), let colorWrite = uniqueAssignment(
                color, after: colorDefinition, before: output,
                tokens: tokens, body: main.bodyRange
              ) else {
            return nil
        }
        guard let blendExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: colorWrite, in: tokens, body: main.bodyRange),
              let blendArguments = callArguments(
                blendExpression, function: ["ApplyBlending"], count: 4
              ), member(blendArguments[2], name: color, component: "rgb"),
              let baseArguments = callArguments(
                blendArguments[1], function: ["mix", "lerp"], count: 3
              ), member(baseArguments[0], name: color, component: "rgb"),
              let sample = memberName(baseArguments[1], component: "rgb"),
              member(baseArguments[2], name: sample, component: "a") else {
            return nil
        }
        guard let helper = blendHelper(fragment),
              let alphaExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: alphaDefinition, in: tokens, body: main.bodyRange
                ),
              let slot = uniqueSampleSlot(
                sample, before: output, tokens: tokens, body: main.bodyRange
              ) else {
            return nil
        }
        let alphaSampleUse: Int?
        switch helper {
        case .normal:
            guard texts(alphaExpression) == texts(blendArguments[3]),
                  !alphaExpression.contains(where: { $0.text == sample }) else {
                return nil
            }
            alphaSampleUse = nil
        case .additive:
            guard let use = intersectAlphaSampleUse(
                alphaExpression,
                sample: sample,
                weight: blendArguments[3]
            ) else { return nil }
            alphaSampleUse = use
        }
        guard exactUses(
                sample,
                expected: [
                    baseArguments[1].startIndex,
                    baseArguments[2].startIndex,
                ] + [alphaSampleUse].compactMap { $0 },
                afterDefinitionBefore: output,
                tokens: tokens,
                body: main.bodyRange
              ) else {
            return nil
        }
        guard exactUses(
                alpha,
                expected: [outputArguments[1].startIndex],
                afterDefinitionBefore: outputExpression.endIndex,
                tokens: tokens,
                body: main.bodyRange
        ) else {
            return nil
        }
        return slot
    }

    private static func blendHelper(_ fragment: Unit) -> BlendHelper? {
        let matches = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard matches.count == 1, let function = matches.first else { return nil }
        let tokens = fragment.tokens
        let parameters = split(tokens[function.parameterRange])
        let names = parameters.compactMap {
            $0.last(where: { $0.kind == .identifier })?.text
        }
        guard names.count == 4,
              function.bodyRange.count >= 5,
              tokens[function.bodyRange.lowerBound].text == "{",
              tokens[function.bodyRange.lowerBound + 1].text == "return",
              tokens[function.bodyRange.upperBound - 1].text == "}" else {
            return nil
        }
        let start = function.bodyRange.lowerBound + 2
        guard let semicolon = (start..<function.bodyRange.upperBound).first(
            where: { tokens[$0].text == ";" }
        ) else { return nil }
        let firstExpression = tokens[start..<semicolon]
        if semicolon == function.bodyRange.upperBound - 2,
           let arguments = callArguments(
                tokens[start..<semicolon], function: ["mix", "lerp"], count: 3
           ), identifier(arguments[0]) == names[1],
           identifier(strippingParentheses(arguments[1])) == names[2],
           identifier(arguments[2]) == names[3] {
            return .normal
        }
        guard texts(firstExpression) == [
            names[1], "+", names[2], "*", names[3],
        ] else { return nil }
        return .additive
    }

    private static func intersectAlphaSampleUse(
        _ expression: ArraySlice<Token>,
        sample: String,
        weight: ArraySlice<Token>
    ) -> Int? {
        guard expression.count == weight.count + 4,
              texts(expression.prefix(4)) == [sample, ".", "a", "*"],
              texts(expression.dropFirst(4)) == texts(weight) else {
            return nil
        }
        return expression.startIndex
    }

    private static func uniqueSampleSlot(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        guard let definition = uniqueDefinition(
            name, types: ["vec4", "float4"], before: boundary,
            tokens: tokens, body: body
        ), let expression = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(after: definition, in: tokens, body: body),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(expression) else {
            return nil
        }
        let samples = body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        return samples.count == 1 ? slot : nil
    }

    private static func uniqueDefinition(
        _ name: String,
        types: Set<String>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index + 1 < boundary
                && tokens[index].text == name
                && types.contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func uniqueAssignment(
        _ name: String,
        after definition: Int,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = ((definition + 1)..<boundary).filter {
            tokens[$0].text == name && tokens[$0 + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        function: Set<String>,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard expression.count >= 3,
              function.contains(expression.first?.text ?? ""),
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")" else { return nil }
        let content = expression.dropFirst(2).dropLast()
        let result = split(content)
        return result.count == count ? result : nil
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
                start = tokens.index(after: index)
            default: break
            }
            guard depth >= 0 else { return [] }
        }
        guard depth == 0, start < tokens.endIndex else { return [] }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    private static func strippingParentheses(
        _ tokens: ArraySlice<Token>
    ) -> ArraySlice<Token> {
        guard tokens.count == 3,
              tokens.first?.text == "(", tokens.last?.text == ")" else {
            return tokens
        }
        return tokens.dropFirst().dropLast()
    }

    private static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        guard tokens.count == 1, tokens.first?.kind == .identifier else { return nil }
        return tokens.first?.text
    }

    private static func member(
        _ tokens: ArraySlice<Token>,
        name: String,
        component: String
    ) -> Bool {
        memberName(tokens, component: component) == name
    }

    private static func memberName(
        _ tokens: ArraySlice<Token>,
        component: String
    ) -> String? {
        guard tokens.count == 3,
              tokens[tokens.startIndex].kind == .identifier,
              tokens[tokens.index(after: tokens.startIndex)].text == ".",
              tokens[tokens.index(tokens.startIndex, offsetBy: 2)].text
                == component else { return nil }
        return tokens[tokens.startIndex].text
    }

    private static func exactUses(
        _ name: String,
        expected: [Int],
        afterDefinitionBefore boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        guard let definition = body.first(where: {
            $0 < boundary && tokens[$0].text == name
                && $0 + 1 < boundary && tokens[$0 + 1].text == "="
        }) else { return false }
        return ((definition + 1)..<boundary).filter {
            tokens[$0].text == name
        } == expected.sorted()
    }

    private static func rootAssignment(
        _ index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        index + 1 < tokens.count && tokens[index + 1].text == "="
            && body.contains(index)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index, tokens: tokens, body: body
            )
    }

    private static func texts(_ tokens: ArraySlice<Token>) -> [String] {
        tokens.map(\.text)
    }
}
