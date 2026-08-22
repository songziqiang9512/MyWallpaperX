import Foundation

/// Proves a complementary independent-signal composition where the final
/// carrier starts as authored RGBA data and a previous color is sampled only
/// for one exact blend/alpha/output tail. Other sampled slots remain typed
/// resource-time data facts rather than implicit color inputs.
nonisolated enum SceneAuthoredShaderIndependentSignalCompositingAnalyzer {
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
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens),
              statements.count >= 5,
              let outputRange = statements.last,
              outputRange.contains(output),
              let signalName = exactOutputCarrier(
                Array(tokens[outputRange])
              ) else { return nil }

        let colorRange = statements[statements.count - 4]
        let blendRange = statements[statements.count - 3]
        let alphaRange = statements[statements.count - 2]
        guard let color = directVectorSample(
            Array(tokens[colorRange]), fragment: fragment
        ), color.name != signalName,
              let blendColorName = signalCarrierBlend(
                Array(tokens[blendRange]), signalName: signalName
              ), blendColorName == color.name,
              exactCombinedAlpha(
                Array(tokens[alphaRange]),
                signalName: signalName,
                colorName: color.name
              ) else { return nil }

        let signalDefinitions = statements.dropLast(4).compactMap { range in
            directVectorSample(Array(tokens[range]), fragment: fragment)
                .flatMap { $0.name == signalName ? (range, $0.slot) : nil }
        }
        guard signalDefinitions.count == 1,
              let signal = signalDefinitions.first,
              signal.1 != color.slot,
              safeSignalPrefixUses(
                signalName,
                after: signal.0,
                before: colorRange,
                tokens: tokens
              ) else { return nil }
        return .independentAlphaSignalCompositing(
            signalSlot: signal.1,
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

    private static func exactOutputCarrier(_ statement: [Token]) -> String? {
        guard statement.count == 3,
              statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              statement[2].kind == .identifier else { return nil }
        return statement[2].text
    }

    private static func signalCarrierBlend(
        _ statement: [Token],
        signalName: String
    ) -> String? {
        guard statement.count >= 16,
              Array(statement.prefix(4)).map(\.text)
                == [signalName, ".", "rgb", "="],
              let arguments = callArguments(
                Array(statement.dropFirst(4)), name: "ApplyBlending"
              ), arguments.count == 4,
              arguments[0].count == 1,
              let mode = Int(arguments[0][0].text),
              (1 ... 32).contains(mode),
              arguments[1].count == 3,
              arguments[1][0].kind == .identifier,
              Array(arguments[1].dropFirst()).map(\.text) == [".", "rgb"],
              arguments[2].map(\.text) == [signalName, ".", "rgb"],
              exactSignalAlphaFactor(
                arguments[3], signalName: signalName,
                colorName: arguments[1][0].text
              ) else { return nil }
        return arguments[1][0].text
    }

    private static func exactSignalAlphaFactor(
        _ expression: [Token],
        signalName: String,
        colorName: String
    ) -> Bool {
        let signalUses = expression.indices.filter {
            expression[$0].text == signalName
        }
        guard signalUses.count == 1,
              let use = signalUses.first,
              use + 2 < expression.count,
              expression[use + 1].text == ".",
              expression[use + 2].text == "a",
              !expression.contains(where: {
                  $0.text == colorName
                      || ["texSample2D", "texture2D", "=", "+=", "-=", "*=", "/="]
                        .contains($0.text)
              }) else { return false }
        return true
    }

    private static func exactCombinedAlpha(
        _ statement: [Token],
        signalName: String,
        colorName: String
    ) -> Bool {
        statement.map(\.text) == [
            signalName, ".", "a", "=", "saturate", "(",
            colorName, ".", "a", "+", signalName, ".", "a", ")",
        ]
    }

    private static func safeSignalPrefixUses(
        _ signalName: String,
        after definition: Range<Int>,
        before boundary: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let allowedMembers: Set<String> = [
            "r", "g", "b", "a", "x", "y", "z", "w",
            "rg", "rgb", "rgba", "xy", "xyz", "xyzw",
        ]
        guard definition.upperBound <= boundary.lowerBound else { return false }
        for use in definition.upperBound..<boundary.lowerBound
        where tokens[use].text == signalName {
            guard use + 2 < boundary.lowerBound,
                  tokens[use + 1].text == ".",
                  allowedMembers.contains(tokens[use + 2].text) else {
                return false
            }
        }
        return true
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
