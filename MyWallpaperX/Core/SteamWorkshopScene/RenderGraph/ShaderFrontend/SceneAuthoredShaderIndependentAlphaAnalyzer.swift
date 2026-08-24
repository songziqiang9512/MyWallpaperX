import Foundation

/// Recognizes bounded color flows whose alpha channel is an authored signal,
/// rather than coverage suitable for direct composition.
nonisolated enum SceneAuthoredShaderIndependentAlphaAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> SceneShaderColorTransfer? {
        if let value = composite(outputUses, fragment: fragment, main: main) {
            return value
        }
        if let slot = producer(outputUses, fragment: fragment, main: main) {
            return .independentAlphaSignal(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderIndependentSignalCarrierAnalyzer.analyze(
            fragment
        ) {
            return .independentAlphaSignalPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer.analyze(
            fragment
        ) {
            return .independentAlphaSignalPreserving(textureSlot: slot)
        }
        if let slot = preserving(outputUses, fragment: fragment, main: main) {
            return .independentAlphaSignalPreserving(textureSlot: slot)
        }
        return nil
    }

    private static func producer(
        _ outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard (1 ... 2).contains(outputUses.count),
              let output = outputUses.first,
              rootWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let name = singleVectorLocal(
                  in: expression, before: output, tokens: tokens, body: main.bodyRange
              ), let definition = vectorDefinition(
                  name, before: output, tokens: tokens, body: main.bodyRange
              ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(initializer),
              contains(
                  tokens,
                  [name, ".", "rgb", "*=", name, ".", "a"],
                  range: (definition + 1)..<output
              ), containsAlphaOneWrite(
                  name, tokens: tokens, range: (definition + 1)..<output
              ), expression.first?.text == name,
              safeVectorUses(
                  name,
                  definition: definition,
                  output: output,
                  expression: expression,
                  tokens: tokens
              ) else { return nil }
        if outputUses.count == 2 {
            guard let alpha = outputUses.last,
                  alpha > output,
                  rootMemberWrite(
                      alpha,
                      member: "a",
                      operators: ["*="],
                      tokens: tokens,
                      body: main.bodyRange
                  ) else { return nil }
        }
        return slot
    }

    private static func preserving(
        _ outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              !main.bodyRange.contains(where: {
                  ["if", "else", "switch", "case"].contains(tokens[$0].text)
              }),
              let output = outputUses.first,
              rootWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let name = singleVectorLocal(
                  in: expression, before: output, tokens: tokens, body: main.bodyRange
              ), let definition = vectorDefinition(
                  name, before: output, tokens: tokens, body: main.bodyRange
              ), expression.filter({ $0.text == name }).count == 1 else { return nil }
        let slots = sampledSlots(tokens: tokens, range: main.bodyRange)
        guard slots.count == 1,
              let slot = slots.first,
              outputDependsOnSamples(
                  name,
                  definition: definition,
                  output: output,
                  tokens: tokens,
                  body: main.bodyRange
              ) else { return nil }
        return slot
    }

    private static func composite(
        _ outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> SceneShaderColorTransfer? {
        if let transfer =
            SceneAuthoredShaderIndependentSignalColorCarrierCompositingAnalyzer
                .analyze(
                    outputUses: outputUses,
                    fragment: fragment,
                    main: main
                ) {
            return transfer
        }
        if let transfer = SceneAuthoredShaderIndependentSignalCompositingAnalyzer
            .analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return transfer
        }
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              rootWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              expression.count == 1,
              let color = expression.first?.text,
              let colorDefinition = vectorDefinition(
                  color, before: output, tokens: tokens, body: main.bodyRange
              ), let colorInitializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: colorDefinition, in: tokens, body: main.bodyRange
                  ), let colorSlot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(colorInitializer) else { return nil }

        let vectorNames = vectorDefinitions(
            before: output, tokens: tokens, body: main.bodyRange
        ).map { tokens[$0].text }.filter { $0 != color }
        let signalCandidates = vectorNames.compactMap { name -> (String, Int)? in
            guard let definition = vectorDefinition(
                name, before: output, tokens: tokens, body: main.bodyRange
            ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
                  let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(initializer) else { return nil }
            return (name, slot)
        }
        guard signalCandidates.count == 1,
              let signal = signalCandidates.first,
              signal.1 != colorSlot,
              contains(
                  tokens,
                  [color, ".", "rgb", "=", "ApplyBlending"],
                  range: (colorDefinition + 1)..<output
              ), contains(
                  tokens,
                  [signal.0, ".", "rgb"],
                  range: (colorDefinition + 1)..<output
              ), contains(
                  tokens,
                  [signal.0, ".", "a"],
                  range: (colorDefinition + 1)..<output
              ), contains(
                  tokens,
                  [color, ".", "a", "+=", signal.0, ".", "a"],
                  range: (colorDefinition + 1)..<output
              ) else { return nil }
        return .independentAlphaSignalCompositing(
            signalSlot: signal.1,
            colorSlot: colorSlot
        )
    }

    private static func vectorDefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = vectorDefinitions(before: boundary, tokens: tokens, body: body)
            .filter { tokens[$0].text == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func vectorDefinitions(
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [Int] {
        body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].kind == .identifier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count && tokens[index + 1].text == "="
        }
    }

    private static func singleVectorLocal(
        in expression: ArraySlice<Token>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> String? {
        let locals = Set(vectorDefinitions(before: boundary, tokens: tokens, body: body)
            .map { tokens[$0].text })
        let matches = Set(expression.filter { locals.contains($0.text) }.map(\.text))
        return matches.count == 1 ? matches.first : nil
    }

    private static func sampledSlots(
        tokens: [Token],
        range: Range<Int>
    ) -> Set<Int> {
        Set(range.compactMap { index in
            guard ["texSample2D", "texture2D"].contains(tokens[index].text),
                  index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  tokens[index + 2].text.hasPrefix("g_Texture"),
                  tokens[index + 3].text == ",",
                  let slot = Int(tokens[index + 2].text.dropFirst("g_Texture".count)),
                  (0 ... 7).contains(slot) else { return nil }
            return slot
        })
    }

    private static func outputDependsOnSamples(
        _ name: String,
        definition: Int,
        output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        guard let initializer = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(after: definition, in: tokens, body: body) else { return false }
        if !sampledSlots(
            tokens: Array(initializer), range: 0..<initializer.count
        ).isEmpty { return true }
        for use in (definition + 1)..<output where tokens[use].text == name {
            guard use + 1 < output,
                  ["=", "+="].contains(tokens[use + 1].text),
                  let value = assignedExpression(
                      after: use, in: tokens, body: body
                  ) else { continue }
            if !sampledSlots(tokens: Array(value), range: 0..<value.count).isEmpty {
                return true
            }
            for token in value where token.kind == .identifier {
                guard let aliasDefinition = vectorDefinition(
                    token.text, before: use, tokens: tokens, body: body
                ), let alias = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                    after: aliasDefinition, in: tokens, body: body
                ) else { continue }
                if !sampledSlots(tokens: Array(alias), range: 0..<alias.count).isEmpty {
                    return true
                }
            }
        }
        return false
    }

    private static func assignedExpression(
        after assignment: Int,
        in tokens: [Token],
        body: Range<Int>
    ) -> ArraySlice<Token>? {
        let start = assignment + 2
        guard assignment + 1 < tokens.count,
              ["=", "+="].contains(tokens[assignment + 1].text),
              body.contains(start) else { return nil }
        var parenthesisDepth = 0
        var bracketDepth = 0
        for index in start..<body.upperBound {
            switch tokens[index].text {
            case "(": parenthesisDepth += 1
            case ")": parenthesisDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case ";" where parenthesisDepth == 0 && bracketDepth == 0:
                return start < index ? tokens[start..<index] : nil
            default: break
            }
            guard parenthesisDepth >= 0, bracketDepth >= 0 else { return nil }
        }
        return nil
    }

    private static func safeVectorUses(
        _ name: String,
        definition: Int,
        output: Int,
        expression: ArraySlice<Token>,
        tokens: [Token]
    ) -> Bool {
        let allowedMembers: Set<String> = ["rgb", "a"]
        for use in (definition + 1)..<output where tokens[use].text == name {
            if expression.indices.contains(use) { continue }
            guard use + 2 < output,
                  tokens[use + 1].text == ".",
                  allowedMembers.contains(tokens[use + 2].text) else { return false }
        }
        return true
    }

    private static func containsAlphaOneWrite(
        _ name: String,
        tokens: [Token],
        range: Range<Int>
    ) -> Bool {
        range.contains { index in
            index + 4 < range.upperBound
                && tokens[index].text == name && tokens[index + 1].text == "."
                && tokens[index + 2].text == "a" && tokens[index + 3].text == "="
                && tokens[index + 4].kind == .number
                && Double(tokens[index + 4].text) == 1
        }
    }

    private static func rootWrite(
        _ output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        output + 1 < tokens.count && tokens[output + 1].text == "="
            && body.contains(output)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: body
            )
    }

    private static func rootMemberWrite(
        _ output: Int,
        member: String,
        operators: Set<String>,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        output + 3 < tokens.count && tokens[output + 1].text == "."
            && tokens[output + 2].text == member
            && operators.contains(tokens[output + 3].text)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: body
            )
    }

    private static func contains(
        _ tokens: [Token],
        _ pattern: [String],
        range: Range<Int>
    ) -> Bool {
        guard !pattern.isEmpty, range.count >= pattern.count else { return false }
        return (range.lowerBound...(range.upperBound - pattern.count)).contains { start in
            zip(tokens[start..<(start + pattern.count)], pattern).allSatisfy {
                $0.0.text == $0.1
            }
        }
    }
}
