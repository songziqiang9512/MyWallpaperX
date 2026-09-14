import Foundation

/// Proves one exact two-input composition whose color sample remains the
/// output carrier while a separate RGBA sample contributes RGB and alpha.
/// The proof is intentionally limited to five unconditional top-level
/// statements so hidden sampling, writes, or control flow cannot be admitted.
nonisolated enum SceneAuthoredShaderIndependentSignalColorCarrierCompositingAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> SceneShaderColorTransfer? {
        let tokens = fragment.tokens
        if let underlay = underlayComposition(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return underlay
        }
        guard outputUses.count == 1,
              fragment.functions.allSatisfy({ $0.name != "saturate" }),
              !main.bodyRange.contains(where: {
                  [
                      "if", "else", "for", "while", "do", "switch", "case",
                      "discard", "break", "continue", "return", "?",
                  ].contains(tokens[$0].text)
              }),
              main.bodyRange.filter({
                  ["texSample2D", "texture2D"].contains(tokens[$0].text)
              }).count == 2,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens),
              statements.count == 5,
              let first = directVectorSample(
                  Array(tokens[statements[0]]), fragment: fragment
              ),
              let second = directVectorSample(
                  Array(tokens[statements[1]]), fragment: fragment
              ),
              first.name != second.name,
              first.slot != second.slot,
              let tail = exactBlend(Array(tokens[statements[2]])),
              tail.colorName != tail.signalName,
              exactCombinedAlpha(
                  Array(tokens[statements[3]]),
                  colorName: tail.colorName,
                  signalName: tail.signalName
              ),
              exactOutputCarrier(
                  Array(tokens[statements[4]]), colorName: tail.colorName
              ),
              let color = [first, second].first(where: {
                  $0.name == tail.colorName
              }),
              let signal = [first, second].first(where: {
                  $0.name == tail.signalName
              }) else { return nil }

        return .independentAlphaSignalCompositing(
            signalSlot: signal.slot,
            colorSlot: color.slot
        )
    }

    /// Proves the ordered three-input form used by authored same-frame
    /// background composition: signal, color carrier and color underlay. The
    /// coordinate expression stays author-controlled, while its statement is
    /// required to be sample-free and unable to mutate any color carrier.
    private static func underlayComposition(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> SceneShaderColorTransfer? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              fragment.functions.allSatisfy({
                  !["saturate", "mix", "lerp"].contains($0.name)
              }),
              !main.bodyRange.contains(where: {
                  [
                      "if", "else", "for", "while", "do", "switch", "case",
                      "discard", "break", "continue", "return", "?",
                  ].contains(tokens[$0].text)
              }),
              main.bodyRange.filter({
                  ["texSample2D", "texture2D"].contains(tokens[$0].text)
              }).count == 3,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens),
              statements.count == 8,
              let first = directVectorSample(
                  Array(tokens[statements[0]]), fragment: fragment
              ),
              let second = directVectorSample(
                  Array(tokens[statements[1]]), fragment: fragment
              ),
              safeCoordinateDeclaration(
                  Array(tokens[statements[2]]),
                  excluding: [first.name, second.name]
              ),
              let third = directVectorSample(
                  Array(tokens[statements[3]]), fragment: fragment
              ),
              Set([first.name, second.name, third.name]).count == 3,
              Set([first.slot, second.slot, third.slot]).count == 3,
              let tail = exactBlend(Array(tokens[statements[5]])),
              tail.colorName != tail.signalName,
              let underlayName = exactUnderlayMix(
                  Array(tokens[statements[4]]),
                  colorName: tail.colorName
              ),
              underlayName != tail.signalName,
              exactCombinedAlpha(
                  Array(tokens[statements[6]]),
                  colorName: tail.colorName,
                  signalName: tail.signalName
              ),
              exactOutputCarrier(
                  Array(tokens[statements[7]]), colorName: tail.colorName
              ),
              let color = [first, second, third].first(where: {
                  $0.name == tail.colorName
              }),
              let signal = [first, second, third].first(where: {
                  $0.name == tail.signalName
              }),
              let underlay = [first, second, third].first(where: {
                  $0.name == underlayName
              }) else { return nil }

        return .independentAlphaSignalUnderlayCompositing(
            signalSlot: signal.slot,
            colorSlot: color.slot,
            underlaySlot: underlay.slot
        )
    }

    private static func safeCoordinateDeclaration(
        _ statement: [Token],
        excluding colorNames: Set<String>
    ) -> Bool {
        guard statement.count >= 4,
              ["vec2", "float2"].contains(statement[0].text),
              statement[1].kind == .identifier,
              statement[2].text == "=",
              !colorNames.contains(statement[1].text),
              !statement.dropFirst(3).contains(where: {
                  colorNames.contains($0.text)
                      || [
                          "gl_FragColor", "texSample2D", "texture2D",
                          "+=", "-=", "*=", "/=", "++", "--",
                      ].contains($0.text)
              }) else { return false }
        return true
    }

    private static func exactUnderlayMix(
        _ statement: [Token],
        colorName: String
    ) -> String? {
        guard statement.count >= 16,
              Array(statement.prefix(4)).map(\.text)
                == [colorName, ".", "rgb", "="],
              let arguments = callArguments(
                  Array(statement.dropFirst(4)),
                  name: statement.dropFirst(4).first?.text ?? ""
              ),
              ["mix", "lerp"].contains(statement[4].text),
              arguments.count == 3,
              arguments[0].count == 3,
              arguments[0][0].kind == .identifier,
              Array(arguments[0].dropFirst()).map(\.text) == [".", "rgb"],
              arguments[1].map(\.text) == [colorName, ".", "rgb"],
              arguments[2].map(\.text) == [colorName, ".", "a"],
              arguments[0][0].text != colorName else { return nil }
        return arguments[0][0].text
    }

    private static func directVectorSample(
        _ statement: [Token],
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        guard statement.count >= 6,
              ["vec4", "float4"].contains(statement[0].text),
              statement[1].kind == .identifier,
              statement[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(statement[3...]),
              fragment.declarations.filter({
                  $0.storage == .uniform && $0.arraySize == nil
                      && $0.typeName == "sampler2D"
                      && $0.name == "g_Texture\(slot)"
              }).count == 1 else { return nil }
        return (statement[1].text, slot)
    }

    private static func exactBlend(
        _ statement: [Token]
    ) -> (colorName: String, signalName: String)? {
        guard statement.count >= 16,
              statement[0].kind == .identifier,
              Array(statement.prefix(4)).map(\.text)
                == [statement[0].text, ".", "rgb", "="],
              let arguments = callArguments(
                  Array(statement.dropFirst(4)), name: "ApplyBlending"
              ),
              arguments.count == 4,
              arguments[0].count == 1,
              let mode = Int(arguments[0][0].text),
              (1 ... 32).contains(mode),
              arguments[1].map(\.text)
                == [statement[0].text, ".", "rgb"],
              arguments[2].count == 3,
              arguments[2][0].kind == .identifier,
              Array(arguments[2].dropFirst()).map(\.text) == [".", "rgb"],
              arguments[3].map(\.text)
                == [arguments[2][0].text, ".", "a"] else { return nil }
        return (statement[0].text, arguments[2][0].text)
    }

    private static func exactCombinedAlpha(
        _ statement: [Token],
        colorName: String,
        signalName: String
    ) -> Bool {
        statement.map(\.text) == [
            colorName, ".", "a", "=", "saturate", "(",
            colorName, ".", "a", "+", signalName, ".", "a", ")",
        ]
    }

    private static func exactOutputCarrier(
        _ statement: [Token],
        colorName: String
    ) -> Bool {
        statement.map(\.text) == ["gl_FragColor", "=", colorName]
    }

    private static func callArguments(
        _ tokens: [Token],
        name: String
    ) -> [[Token]]? {
        guard tokens.count >= 3,
              tokens[0].text == name,
              tokens[1].text == "(",
              tokens.last?.text == ")" else { return nil }
        var result: [[Token]] = []
        var start = 2
        var depth = 0
        for index in 2..<(tokens.count - 1) {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(Array(tokens[start..<index]))
                start = index + 1
            }
        }
        guard depth == 0, start < tokens.count - 1 else { return nil }
        result.append(Array(tokens[start..<(tokens.count - 1)]))
        return result
    }
}
