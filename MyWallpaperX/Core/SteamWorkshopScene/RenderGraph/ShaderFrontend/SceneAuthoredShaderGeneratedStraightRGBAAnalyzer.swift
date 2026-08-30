import Foundation

/// Proves one source-independent straight RGBA output whose RGB is generated
/// from authored uniforms/varyings and whose alpha is one independent scalar
/// uniform. Product backends may then premultiply the terminal value at the
/// compositor boundary without selecting by shader, effect, or asset identity.
nonisolated enum SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let rgbName: String
        let alphaName: String
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
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ), let construction =
                SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(expression),
              ["CAST4", "vec4", "float4"].contains(construction.name),
              construction.arguments.count == 2,
              let rgbName = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(construction.arguments[0]),
              let alphaName = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(construction.arguments[1]),
              rgbName != alphaName,
              fragment.declarations.contains(where: {
                  $0.storage == .uniform && $0.typeName == "float"
                      && $0.arraySize == nil && $0.name == alphaName
              }), let rgbDefinition = uniqueRGBDefinition(
                rgbName,
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: rgbDefinition,
                    in: tokens,
                    body: main.bodyRange
                ), !initializer.contains(where: { $0.text == alphaName }),
              countUses(
                rgbName,
                expected: 2,
                tokens: tokens,
                range: rgbDefinition..<expression.endIndex
              ), countUses(
                alphaName,
                expected: 1,
                tokens: tokens,
                range: main.bodyRange
              ), reachableFunctionsAreSourceIndependent(
                fragment,
                startingAt: main,
                alphaName: alphaName
              ) else { return nil }
        return Fact(rgbName: rgbName, alphaName: alphaName)
    }

    private static func uniqueRGBDefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec3", "float3"].contains(tokens[index - 1].text)
                && index + 1 < boundary && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func countUses(
        _ name: String,
        expected: Int,
        tokens: [Token],
        range: some Sequence<Int>
    ) -> Bool {
        range.filter { tokens[$0].text == name }.count == expected
    }

    private static func reachableFunctionsAreSourceIndependent(
        _ fragment: Unit,
        startingAt main: Unit.Function,
        alphaName: String
    ) -> Bool {
        let functions = Dictionary(uniqueKeysWithValues: fragment.functions.map {
            ($0.name, $0)
        })
        var pending = [main.name]
        var visited = Set<String>()
        while let name = pending.popLast() {
            guard visited.insert(name).inserted,
                  let function = functions[name] else { continue }
            let body = fragment.tokens[function.bodyRange]
            guard !body.contains(where: {
                [
                    "texSample2D", "texture2D", "texSample2DLod",
                    "texture2DLod", "texture", "textureLod", "gl_FragData",
                ].contains($0.text)
            }), name == main.name || !body.contains(where: {
                $0.text == "gl_FragColor" || $0.text == alphaName
            }) else { return false }
            for index in function.bodyRange where index + 1 < function.bodyRange.upperBound {
                let candidate = fragment.tokens[index]
                if candidate.kind == .identifier,
                   fragment.tokens[index + 1].text == "(",
                   functions[candidate.text] != nil {
                    pending.append(candidate.text)
                }
            }
        }
        return true
    }
}
