import Foundation

/// Proves one bounded two-input straight-color flow. The base sample supplies
/// color, a distinct data sample supplies an RGB replacement and authored
/// alpha, and an exact normal-mix helper combines them. The existing
/// `.straightAlpha` boundary can therefore unpremultiply only the base sample
/// and premultiply the final authored result once.
nonisolated enum SceneAuthoredShaderOverlayAlphaBlendAnalyzer {
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
              rootAssignment(output, tokens: tokens, body: main.bodyRange),
              mainHasNoControlFlow(main, tokens: tokens),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let base = identifier(outputExpression),
              let baseDefinition = uniqueSampleDefinition(
                base, before: output, tokens: tokens, body: main.bodyRange
              ),
              let baseSlot = sampleSlot(
                at: baseDefinition, tokens: tokens, body: main.bodyRange
              ),
              let rgbWrite = uniqueMemberAssignment(
                base,
                component: "rgb",
                after: baseDefinition,
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ),
              let rgbExpression = memberAssignmentExpression(
                after: rgbWrite, tokens: tokens, body: main.bodyRange
              ),
              let blendCall = call(rgbExpression),
              blendCall.name == "ApplyBlending",
              blendCall.arguments.count == 4,
              numericZero(blendCall.arguments[0]),
              member(blendCall.arguments[1], name: base, component: "rgb"),
              let overlay = memberName(blendCall.arguments[2], component: "rgb"),
              overlay != base,
              let overlayDefinition = uniqueSampleDefinition(
                overlay, before: rgbWrite, tokens: tokens, body: main.bodyRange
              ),
              let overlaySlot = sampleSlot(
                at: overlayDefinition, tokens: tokens, body: main.bodyRange
              ),
              overlaySlot != baseSlot,
              let weight = identifier(blendCall.arguments[3]),
              let weightDefinition = uniqueDefinition(
                weight,
                type: "float",
                before: rgbWrite,
                tokens: tokens,
                body: main.bodyRange
              ),
              overlayDefinition < weightDefinition,
              let weightExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: weightDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let weightOverlayUse = overlayAlphaProductUse(
                weightExpression,
                overlay: overlay,
                excluded: base
              ),
              let alphaWrite = uniqueMemberAssignment(
                base,
                component: "a",
                after: rgbWrite,
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ),
              let alphaExpression = memberAssignmentExpression(
                after: alphaWrite, tokens: tokens, body: main.bodyRange
              ),
              let alphaOverlayUse = overlayAlphaProductUse(
                alphaExpression,
                overlay: overlay,
                excluded: base
              ),
              SceneAuthoredShaderStraightBlendOutputAnalyzer
                .hasNormalBlendHelper(fragment),
              exactSampleCalls([baseDefinition, overlayDefinition], tokens: tokens),
              exactUses(
                base,
                expected: [
                    rgbWrite,
                    blendCall.arguments[1].startIndex,
                    alphaWrite,
                    outputExpression.startIndex,
                ],
                after: baseDefinition,
                before: outputExpression.endIndex,
                tokens: tokens
              ),
              exactUses(
                overlay,
                expected: [
                    blendCall.arguments[2].startIndex,
                    weightOverlayUse,
                    alphaOverlayUse,
                ],
                after: overlayDefinition,
                before: output,
                tokens: tokens
              ),
              exactUses(
                weight,
                expected: [blendCall.arguments[3].startIndex],
                after: weightDefinition,
                before: output,
                tokens: tokens
              ) else {
            return nil
        }
        return baseSlot
    }

    private struct Call {
        let name: String
        let arguments: [ArraySlice<Token>]
    }

    private static func call(_ expression: ArraySlice<Token>) -> Call? {
        guard expression.count >= 3,
              expression.first?.kind == .identifier,
              let name = expression.first?.text,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")",
              let arguments = splitCallArguments(expression) else {
            return nil
        }
        return Call(name: name, arguments: arguments)
    }

    private static func splitCallArguments(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        let content = expression.dropFirst(2).dropLast()
        guard !content.isEmpty else { return [] }
        var arguments: [ArraySlice<Token>] = []
        var depth = 0
        var start = content.startIndex
        for index in content.indices {
            switch content[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                arguments.append(content[start..<index])
                start = content.index(after: index)
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < content.endIndex else { return nil }
        arguments.append(content[start..<content.endIndex])
        return arguments
    }

    private static func uniqueSampleDefinition(
        _ name: String, before boundary: Int, tokens: [Token], body: Range<Int>
    ) -> Int? {
        guard let definition = uniqueDefinition(
            name,
            type: ["vec4", "float4"],
            before: boundary,
            tokens: tokens,
            body: body
        ), sampleSlot(at: definition, tokens: tokens, body: body) != nil else {
            return nil
        }
        return definition
    }

    private static func uniqueDefinition(
        _ name: String, type: String, before boundary: Int,
        tokens: [Token], body: Range<Int>
    ) -> Int? {
        uniqueDefinition(
            name,
            type: [type],
            before: boundary,
            tokens: tokens,
            body: body
        )
    }

    private static func uniqueDefinition(
        _ name: String, type: Set<String>, before boundary: Int,
        tokens: [Token], body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index + 1 < boundary
                && tokens[index].text == name
                && type.contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard matches.count == 1,
              let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func sampleSlot(
        at definition: Int, tokens: [Token], body: Range<Int>
    ) -> Int? {
        guard let expression = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(after: definition, in: tokens, body: body) else {
            return nil
        }
        return SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(expression)
    }

    private static func uniqueMemberAssignment(
        _ name: String, component: String, after lowerBound: Int,
        before upperBound: Int, tokens: [Token], body: Range<Int>
    ) -> Int? {
        let matches = ((lowerBound + 1)..<upperBound).filter { index in
            index + 3 < upperBound
                && tokens[index].text == name
                && tokens[index + 1].text == "."
                && tokens[index + 2].text == component
                && tokens[index + 3].text == "="
        }
        guard matches.count == 1,
              let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func memberAssignmentExpression(
        after assignment: Int, tokens: [Token], body: Range<Int>
    ) -> ArraySlice<Token>? {
        let start = assignment + 4
        guard assignment + 3 < tokens.count,
              tokens[assignment + 1].text == ".",
              tokens[assignment + 3].text == "=",
              body.contains(start) else { return nil }
        var depth = 0
        for index in start..<body.upperBound {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case ";" where depth == 0:
                return start < index ? tokens[start..<index] : nil
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func overlayAlphaProductUse(
        _ expression: ArraySlice<Token>, overlay: String, excluded: String
    ) -> Int? {
        let factors = productFactors(expression)
        guard factors.count >= 2,
              !expression.contains(where: { $0.text == excluded }) else {
            return nil
        }
        let overlayFactors = factors.filter {
            member($0, name: overlay, component: "a")
        }
        guard overlayFactors.count == 1,
              let overlayFactor = overlayFactors.first,
              factors.filter({ $0.startIndex != overlayFactor.startIndex })
                .allSatisfy({ factor in
                  !factor.contains(where: { $0.text == overlay })
                      && !factor.contains(where: { sampleFunctions.contains($0.text) })
              }) else {
            return nil
        }
        return overlayFactor.startIndex
    }

    private static func productFactors(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>] {
        guard !expression.isEmpty else { return [] }
        var factors: [ArraySlice<Token>] = []
        var depth = 0
        var start = expression.startIndex
        for index in expression.indices {
            switch expression[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "*" where depth == 0:
                guard start < index else { return [] }
                factors.append(expression[start..<index])
                start = expression.index(after: index)
            default: break
            }
            guard depth >= 0 else { return [] }
        }
        guard depth == 0, start < expression.endIndex else { return [] }
        factors.append(expression[start..<expression.endIndex])
        return factors
    }

    private static let sampleFunctions: Set<String> = [
        "texSample2D", "texture2D", "texSample2DLod", "texture2DLod",
    ]

    private static func exactSampleCalls(
        _ definitions: [Int], tokens: [Token]
    ) -> Bool {
        let expected = definitions.compactMap { definition -> Int? in
            guard definition + 2 < tokens.count else { return nil }
            return definition + 2
        }.sorted()
        let actual = tokens.indices.filter { sampleFunctions.contains(tokens[$0].text) }
        return expected.count == definitions.count && actual == expected
    }

    private static func exactUses(
        _ name: String, expected: [Int], after lowerBound: Int,
        before upperBound: Int, tokens: [Token]
    ) -> Bool {
        let actual = ((lowerBound + 1)..<upperBound).filter {
            tokens[$0].text == name
        }
        return actual == expected.sorted()
    }

    private static func mainHasNoControlFlow(
        _ main: Unit.Function, tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "return", "discard", "?",
        ]
        return !main.bodyRange.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func rootAssignment(
        _ index: Int, tokens: [Token], body: Range<Int>
    ) -> Bool {
        index + 1 < tokens.count
            && tokens[index + 1].text == "="
            && body.contains(index)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index, tokens: tokens, body: body
            )
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
              tokens[tokens.index(after: tokens.startIndex)].text == ".",
              tokens[tokens.index(tokens.startIndex, offsetBy: 2)].text == component else {
            return nil
        }
        return tokens[tokens.startIndex].text
    }

    private static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        guard tokens.count == 1, tokens.first?.kind == .identifier else { return nil }
        return tokens.first?.text
    }

    private static func numericZero(_ tokens: ArraySlice<Token>) -> Bool {
        tokens.count == 1 && Double(tokens.first?.text ?? "") == 0
    }

}
