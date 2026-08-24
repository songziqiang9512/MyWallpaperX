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
