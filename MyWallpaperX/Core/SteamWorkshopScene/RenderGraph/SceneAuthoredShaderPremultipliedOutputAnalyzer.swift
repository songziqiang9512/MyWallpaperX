import Foundation

/// Proves one bounded authored premultiplied construction:
/// a zero color receives an active helper specialized to `mix(A, B, weight)`
/// or `A + B * weight`, then writes alpha as `max(0, weight)` before the
/// unique root output. No shader identity, path or effect family participates
/// in this decision.
nonisolated enum SceneAuthoredShaderPremultipliedOutputAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              hasZeroBasePremultiplyingBlendHelper(fragment),
              let output = outputUses.first,
              rootAssignment(output, tokens: tokens, body: main.bodyRange),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              outputExpression.count == 1,
              let color = outputExpression.first?.text,
              let definition = zeroVectorDefinition(
                color, before: output, tokens: tokens, body: main.bodyRange
              ), let rgbWrite = uniqueMemberWrite(
                color, member: "rgb", before: output,
                tokens: tokens, body: main.bodyRange
              ), let alphaWrite = uniqueMemberWrite(
                color, member: "a", before: output,
                tokens: tokens, body: main.bodyRange
              ), definition < rgbWrite, rgbWrite < alphaWrite,
              let rgbExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: rgbWrite + 2, in: tokens, body: main.bodyRange),
              let blendArguments = callArguments(
                rgbExpression, function: "ApplyBlending", count: 4
              ), !blendArguments[0].isEmpty,
              texts(blendArguments[1]) == [color, ".", "rgb"],
              !blendArguments[2].isEmpty,
              !blendArguments[2].contains(where: { $0.text == color }),
              !blendArguments[3].isEmpty,
              let alphaExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: alphaWrite + 2, in: tokens, body: main.bodyRange),
              let alphaArguments = callArguments(
                alphaExpression, function: "max", count: 2
              ), texts(alphaArguments[0]) == [color, ".", "a"],
              texts(alphaArguments[1]) == texts(blendArguments[3]),
              exactColorUses(
                color,
                expected: [
                    definition,
                    rgbWrite,
                    blendArguments[1].startIndex,
                    alphaWrite,
                    alphaArguments[0].startIndex,
                    outputExpression.startIndex,
                ],
                tokens: tokens,
                range: definition...outputExpression.startIndex
              ) else {
            return false
        }
        return true
    }

    private static func hasZeroBasePremultiplyingBlendHelper(
        _ fragment: Unit
    ) -> Bool {
        let matches = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard matches.count == 1, let function = matches.first else { return false }
        let tokens = fragment.tokens
        let parameters = splitParameters(tokens[function.parameterRange])
        guard parameters.count == 4 else { return false }
        let names = parameters.compactMap { parameter in
            parameter.last(where: { $0.kind == .identifier })?.text
        }
        guard names.count == 4,
              function.bodyRange.count >= 4,
              tokens[function.bodyRange.lowerBound].text == "{",
              tokens[function.bodyRange.lowerBound + 1].text == "return" else {
            return false
        }
        let start = function.bodyRange.lowerBound + 2
        guard let end = (start..<function.bodyRange.upperBound).first(where: {
            tokens[$0].text == ";"
        }) else { return false }
        let expression = tokens[start..<end].map(\.text)
        return expression == [names[1], "+", names[2], "*", names[3]]
            || expression == [
                "mix", "(", names[1], ",", names[2], ",", names[3], ")",
            ]
            || expression == [
                "mix", "(", names[1], ",", "(", names[2], ")", ",",
                names[3], ")",
            ]
    }

    private static func splitParameters(
        _ parameters: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        guard !parameters.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = parameters.startIndex
        for index in parameters.indices {
            switch parameters[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                if start < index { result.append(parameters[start..<index]) }
                start = parameters.index(after: index)
            default: break
            }
        }
        if start < parameters.endIndex {
            result.append(parameters[start..<parameters.endIndex])
        }
        return depth == 0 ? result : []
    }

    private static func zeroVectorDefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count && tokens[index + 1].text == "="
        }
        guard matches.count == 1,
              let definition = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                definition, tokens: tokens, body: body
              ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: body),
              let arguments = callArguments(initializer, function: nil, count: 1),
              ["vec4", "float4", "CAST4"].contains(
                initializer.first?.text ?? ""
              ),
              numericValue(arguments[0]) == 0 else {
            return nil
        }
        return definition
    }

    private static func uniqueMemberWrite(
        _ name: String,
        member: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index + 3 < boundary
                && tokens[index].text == name
                && tokens[index + 1].text == "."
                && tokens[index + 2].text == member
                && tokens[index + 3].text == "="
        }
        guard matches.count == 1,
              let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
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

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        function: String?,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard expression.count >= 3,
              function == nil || expression.first?.text == function,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")" else { return nil }
        var depth = 0
        var start = expression.index(expression.startIndex, offsetBy: 2)
        let end = expression.index(before: expression.endIndex)
        var result: [ArraySlice<Token>] = []
        var index = start
        while index < end {
            switch expression[index].text {
            case "(", "[": depth += 1
            case ")", "]":
                depth -= 1
                guard depth >= 0 else { return nil }
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(expression[start..<index])
                start = expression.index(after: index)
            default: break
            }
            index = expression.index(after: index)
        }
        guard depth == 0, start < end else { return nil }
        result.append(expression[start..<end])
        return result.count == count ? result : nil
    }

    private static func numericValue(_ tokens: ArraySlice<Token>) -> Double? {
        guard tokens.count == 1, let token = tokens.first, token.kind == .number else {
            return nil
        }
        return Double(token.text)
    }

    private static func texts(_ tokens: ArraySlice<Token>) -> [String] {
        tokens.map(\.text)
    }

    private static func exactColorUses(
        _ name: String,
        expected: [Int],
        tokens: [Token],
        range: ClosedRange<Int>
    ) -> Bool {
        range.filter { tokens[$0].text == name } == expected.sorted()
    }
}
