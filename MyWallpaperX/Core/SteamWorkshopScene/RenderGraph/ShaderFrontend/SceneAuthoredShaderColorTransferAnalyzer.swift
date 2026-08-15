import Foundation

/// Derives a deliberately small color transfer fact from the same active
/// syntax unit that the authored frontend emits. It does not inspect paths,
/// effect identities, render state, or shader fingerprints.
nonisolated enum SceneAuthoredShaderColorTransferAnalyzer {
    static func analyze(
        _ fragment: SceneAuthoredShaderSyntaxUnit
    ) -> SceneShaderColorTransfer {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return .unresolved
        }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        if outputUses.count != 1,
           let transfer = SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return transfer
        }
        if let slot = SceneAuthoredShaderConditionalAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderConditionalShadowAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotMixAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotMixAnalyzer.analyzeAliasReplacement(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotMixGraphAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderOpaqueInputAlphaAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderUniformRGBMixAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(
                outputUses: outputUses,
                fragment: fragment,
                main: main
            ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if SceneAuthoredShaderPremultipliedOutputAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .premultipliedAlpha
        }
        guard outputUses.count == 1,
              let assignment = outputUses.first,
              assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              main.bodyRange.contains(assignment),
              isUnconditionalWrite(assignment, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) else {
            return .unresolved
        }
        if let slot = directTextureSampleSlot(expression) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = straightAlphaSlot(
            expression,
            outputAssignment: assignment,
            tokens: tokens,
            body: main.bodyRange
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = mutatedStraightAlphaSlot(
            expression,
            outputAssignment: assignment,
            tokens: tokens,
            body: main.bodyRange
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightWholeColorFilterAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlphaUNorm(textureSlot: slot)
        }
        if let transfer = SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return transfer
        }
        return isOpaqueVectorConstruction(expression) ? .opaque : .unresolved
    }

    /// Proves a sampled local with no RGB writes and one root alpha write.
    /// The emitter applies the straight-color boundary around authored math.
    private static func mutatedStraightAlphaSlot(
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

    private static func textureSampleSlots(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Int]? {
        var slots: [Int] = []
        for index in range where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 2 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text) else {
                return nil
            }
            slots.append(slot)
        }
        return slots
    }

    private static func straightAlphaSlot(
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

    static func isUnconditionalWrite(
        _ assignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let functionExits: Set<String> = ["discard", "return"]
        guard !body.contains(where: {
            tokens[$0].kind == .identifier && functionExits.contains(tokens[$0].text)
        }) else {
            return false
        }
        var braceDepth = 0
        var parenthesisDepth = 0
        var bracketDepth = 0
        var statementStart = body.lowerBound + 1
        for index in body.lowerBound..<assignment {
            switch tokens[index].text {
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
                if braceDepth == 1 && parenthesisDepth == 0 && bracketDepth == 0 {
                    statementStart = index + 1
                }
            case "(": parenthesisDepth += 1
            case ")": parenthesisDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case ";" where braceDepth == 1 && parenthesisDepth == 0 && bracketDepth == 0:
                statementStart = index + 1
            default: break
            }
        }
        guard braceDepth == 1, parenthesisDepth == 0, bracketDepth == 0 else {
            return false
        }
        let directControllers: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
        ]
        return !tokens[statementStart..<assignment].contains {
            $0.kind == .identifier && directControllers.contains($0.text)
        }
    }

    static func assignmentExpression(
        after assignment: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> ArraySlice<SceneAuthoredShaderToken>? {
        let start = assignment + 2
        guard assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              body.contains(start) else {
            return nil
        }
        var stack: [String] = []
        let closing: [String: String] = [")": "(", "]": "[", "}": "{"]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "[", "{"].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                guard index > start else { return nil }
                return tokens[start..<index]
            }
        }
        return nil
    }

    static func directTextureSampleSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Int? {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              topLevelCommas(tokens) == [3],
              let slot = textureSlot(tokens[2].text) else {
            return nil
        }
        return slot
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0...7).contains(slot) else {
            return nil
        }
        return slot
    }
}
