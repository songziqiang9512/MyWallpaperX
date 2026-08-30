import Foundation

/// Proves a sampled straight-color carrier overlaid by one source-independent
/// scalar. The same scalar must drive the RGB mix and alpha union, so the
/// shared compiler can move exactly one color boundary around authored math.
nonisolated enum SceneAuthoredShaderStraightColorOverlayAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              fragment.functions.filter({ $0.name == "main" }).count == 1,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              !fragment.functions.contains(where: {
                  ["mix", "lerp", "max", "vec4", "float4"].contains($0.name)
              }),
              !fragment.tokens.contains(where: {
                  ["imageStore", "discard"].contains($0.text)
              }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (5 ... 64).contains(statements.count) else { return nil }

        let tail = Array(statements.suffix(5))
        guard let source = sourceDeclaration(
                  Array(fragment.tokens[tail[0]]), fragment: fragment
              ), let factor = scalarDeclaration(
                  Array(fragment.tokens[tail[1]])
              ), let rgb = rgbDeclaration(
                  Array(fragment.tokens[tail[2]]),
                  sourceName: source.name,
                  factorName: factor.name,
                  fragment: fragment
              ), let alpha = alphaDeclaration(
                  Array(fragment.tokens[tail[3]]),
                  sourceName: source.name,
                  factorName: factor.name
              ), outputStatement(
                  Array(fragment.tokens[tail[4]]),
                  rgbName: rgb.name,
                  alphaName: alpha
              ), sourceIndependent(
                  factor.expression,
                  sourceName: source.name
              ), exactTextureSample(
                  sourceSlot: source.slot,
                  sourceStatement: tail[0],
                  fragment: fragment
              ), exactUses(
                  sourceName: source.name,
                  factorName: factor.name,
                  rgbName: rgb.name,
                  alphaName: alpha,
                  colorUniformName: rgb.colorUniform,
                  fragment: fragment,
                  main: main
              ) else { return nil }
        return .init(sourceSlot: source.slot)
    }

    private static func sourceDeclaration(
        _ tokens: [Token], fragment: Unit
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(tokens[3...]),
              fragment.declarations.filter({
                  $0.storage == .uniform
                      && $0.typeName == "sampler2D"
                      && $0.arraySize == nil
                      && $0.name == "g_Texture\(slot)"
              }).count == 1 else { return nil }
        return (tokens[1].text, slot)
    }

    private static func scalarDeclaration(
        _ tokens: [Token]
    ) -> (name: String, expression: [Token])? {
        guard tokens.count >= 4,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=" else { return nil }
        return (tokens[1].text, Array(tokens.dropFirst(3)))
    }

    private static func rgbDeclaration(
        _ tokens: [Token],
        sourceName: String,
        factorName: String,
        fragment: Unit
    ) -> (name: String, colorUniform: String)? {
        guard tokens.count >= 8,
              ["vec3", "float3"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let call = SceneAuthoredShaderUniformRGBMixAnalyzer.call(
                  Array(tokens.dropFirst(3))
              ), ["mix", "lerp"].contains(call.name),
              call.arguments.count == 3,
              call.arguments[0].map(\.text) == [sourceName, ".", "rgb"],
              call.arguments[1].count == 1,
              let color = call.arguments[1].first?.text,
              call.arguments[2].map(\.text) == [factorName],
              fragment.declarations.filter({
                  $0.storage == .uniform
                      && ["vec3", "float3"].contains($0.typeName)
                      && $0.arraySize == nil
                      && $0.name == color
              }).count == 1 else { return nil }
        return (tokens[1].text, color)
    }

    private static func alphaDeclaration(
        _ tokens: [Token],
        sourceName: String,
        factorName: String
    ) -> String? {
        guard tokens.count >= 8,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let call = SceneAuthoredShaderUniformRGBMixAnalyzer.call(
                  Array(tokens.dropFirst(3))
              ), call.name == "max", call.arguments.count == 2 else {
            return nil
        }
        let expected = Set([
            [sourceName, ".", "a"],
            [factorName],
        ])
        return Set(call.arguments.map { $0.map(\.text) }) == expected
            ? tokens[1].text : nil
    }

    private static func outputStatement(
        _ tokens: [Token],
        rgbName: String,
        alphaName: String
    ) -> Bool {
        guard tokens.count >= 7,
              tokens[0].text == "gl_FragColor",
              tokens[1].text == "=",
              let call = SceneAuthoredShaderUniformRGBMixAnalyzer.call(
                  Array(tokens.dropFirst(2))
              ), ["vec4", "float4"].contains(call.name),
              call.arguments.count == 2 else { return false }
        return call.arguments[0].map(\.text) == [rgbName]
            && call.arguments[1].map(\.text) == [alphaName]
    }

    private static func sourceIndependent(
        _ expression: [Token], sourceName: String
    ) -> Bool {
        !expression.isEmpty && !expression.contains(where: {
            $0.text == sourceName
                || ["gl_FragColor", "texSample2D", "texture2D", "imageStore"]
                    .contains($0.text)
        })
    }

    private static func exactTextureSample(
        sourceSlot: Int,
        sourceStatement: Range<Int>,
        fragment: Unit
    ) -> Bool {
        let calls = fragment.tokens.indices.filter {
            ["texSample2D", "texture2D"].contains(fragment.tokens[$0].text)
        }
        guard calls.count == 1, let call = calls.first,
              sourceStatement.contains(call), call + 2 < fragment.tokens.count,
              fragment.tokens[call + 1].text == "(",
              fragment.tokens[call + 2].text == "g_Texture\(sourceSlot)" else {
            return false
        }
        return true
    }

    private static func exactUses(
        sourceName: String,
        factorName: String,
        rgbName: String,
        alphaName: String,
        colorUniformName: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let counts = [sourceName, factorName, rgbName, alphaName].map { name in
            main.bodyRange.filter { tokens[$0].text == name }.count
        }
        let outputCount = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }.count
        let colorUniformUses = main.bodyRange.filter {
            tokens[$0].text == colorUniformName
        }.count
        return counts == [3, 3, 2, 2]
            && colorUniformUses == 1
            && outputCount == 1
    }
}
