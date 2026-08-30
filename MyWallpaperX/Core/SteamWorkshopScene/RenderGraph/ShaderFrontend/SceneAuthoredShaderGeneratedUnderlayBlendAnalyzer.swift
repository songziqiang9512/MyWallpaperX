import Foundation

/// Proves one bounded straight-color underlay composition. A complete color
/// sample and a shifted alpha-only sample come from the same graph-input slot;
/// uniform RGB and uniform-scaled shifted alpha form a generated underlay, and
/// the base alpha is the exact terminal mix weight. The fact is derived only
/// from active source structure and never from an effect or sample identity.
nonisolated enum SceneAuthoredShaderGeneratedUnderlayBlendAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable, Sendable {
        let sourceSlot: Int
        let sampleCount: Int
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
              fragment.functions.count == 1,
              let main = fragment.functions.first,
              main.name == "main" else { return nil }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              rootAssignment(output, tokens: tokens, body: main.bodyRange),
              noControlFlow(main, tokens: tokens),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ),
              let blend = call(outputExpression),
              ["mix", "lerp"].contains(blend.name),
              blend.arguments.count == 3,
              let generated = identifier(blend.arguments[0]),
              let base = identifier(blend.arguments[1]),
              member(blend.arguments[2], name: base, component: ["a", "w"]),
              let baseDefinition = uniqueDefinition(
                  base,
                  types: ["vec4", "float4"],
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let baseInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: baseDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(baseInitializer),
              let alphaDefinition = uniqueAlphaSampleDefinition(
                  sourceSlot: sourceSlot,
                  excluding: base,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let alphaName = definitionName(
                  at: alphaDefinition,
                  tokens: tokens
              ),
              let generatedDefinition = uniqueDefinition(
                  generated,
                  types: ["vec4", "float4"],
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              alphaDefinition < generatedDefinition,
              let generatedExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: generatedDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let constructor = call(generatedExpression),
              ["vec4", "float4"].contains(constructor.name),
              constructor.arguments.count == 2,
              let rgbUniform = identifier(constructor.arguments[0]),
              uniform(rgbUniform, types: ["vec3", "float3"], in: fragment),
              let alphaFactors = binaryProduct(constructor.arguments[1]),
              alphaFactors.count == 2,
              let scalarUniform = alphaFactors.compactMap(identifier).first(where: {
                  $0 != alphaName
              }),
              alphaFactors.contains(where: { identifier($0) == alphaName }),
              uniform(scalarUniform, types: ["float"], in: fragment),
              exactSampleCalls(
                  expectedSlot: sourceSlot,
                  count: 2,
                  in: main,
                  tokens: tokens
              ),
              exactUses(
                  base,
                  expected: [
                      blend.arguments[1].startIndex,
                      blend.arguments[2].startIndex,
                  ],
                  after: baseDefinition,
                  before: outputExpression.endIndex,
                  tokens: tokens
              ),
              exactUses(
                  alphaName,
                  expected: [
                      alphaFactors.first(where: {
                          identifier($0) == alphaName
                      })!.startIndex,
                  ],
                  after: alphaDefinition,
                  before: output,
                  tokens: tokens
              ),
              exactUses(
                  generated,
                  expected: [blend.arguments[0].startIndex],
                  after: generatedDefinition,
                  before: outputExpression.endIndex,
                  tokens: tokens
              ),
              exactUses(
                  rgbUniform,
                  expected: [constructor.arguments[0].startIndex],
                  after: main.bodyRange.lowerBound,
                  before: output,
                  tokens: tokens
              ),
              exactUses(
                  scalarUniform,
                  expected: [
                      alphaFactors.first(where: {
                          identifier($0) == scalarUniform
                      })!.startIndex,
                  ],
                  after: main.bodyRange.lowerBound,
                  before: output,
                  tokens: tokens
              ) else {
            return nil
        }
        return Fact(sourceSlot: sourceSlot, sampleCount: 2)
    }

    private struct Call {
        let name: String
        let arguments: [ArraySlice<Token>]
    }

    private static func call(_ expression: ArraySlice<Token>) -> Call? {
        guard expression.count >= 3,
              let first = expression.first,
              first.kind == .identifier,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")",
              let arguments = splitArguments(expression.dropFirst(2).dropLast())
        else { return nil }
        return Call(name: first.text, arguments: arguments)
    }

    private static func splitArguments(
        _ content: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        guard !content.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = content.startIndex
        for index in content.indices {
            switch content[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(content[start..<index])
                start = content.index(after: index)
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < content.endIndex else { return nil }
        result.append(content[start..<content.endIndex])
        return result
    }

    private static func binaryProduct(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        var depth = 0
        for index in expression.indices {
            switch expression[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "*" where depth == 0:
                let next = expression.index(after: index)
                guard expression.startIndex < index,
                      next < expression.endIndex else { return nil }
                return [
                    expression[expression.startIndex..<index],
                    expression[next..<expression.endIndex],
                ]
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
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
                  match,
                  tokens: tokens,
                  body: body
              ) else { return nil }
        return match
    }

    private static func uniqueAlphaSampleDefinition(
        sourceSlot: Int,
        excluding base: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            guard index > body.lowerBound,
                  index + 1 < boundary,
                  tokens[index - 1].text == "float",
                  tokens[index].kind == .identifier,
                  tokens[index].text != base,
                  tokens[index + 1].text == "=",
                  SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                      index,
                      tokens: tokens,
                      body: body
                  ),
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: index, in: tokens, body: body),
                  expression.count >= 3,
                  ["a", "w"].contains(expression.last?.text ?? ""),
                  expression[
                    expression.index(expression.endIndex, offsetBy: -2)
                  ].text == "." else { return false }
            let sample = expression.dropLast(2)
            return SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(sample) == sourceSlot
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func definitionName(
        at index: Int,
        tokens: [Token]
    ) -> String? {
        guard tokens.indices.contains(index),
              tokens[index].kind == .identifier else { return nil }
        return tokens[index].text
    }

    private static func uniform(
        _ name: String,
        types: Set<String>,
        in fragment: Unit
    ) -> Bool {
        fragment.declarations.contains {
            $0.storage == .uniform && $0.name == name
                && types.contains($0.typeName) && $0.arraySize == nil
        }
    }

    private static func exactSampleCalls(
        expectedSlot: Int,
        count: Int,
        in main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let functions: Set<String> = [
            "texSample2D", "texture2D", "texSample2DLod", "texture2DLod",
        ]
        let calls = main.bodyRange.filter { functions.contains(tokens[$0].text) }
        guard calls.count == count else { return false }
        return calls.allSatisfy { index in
            guard index + 2 < tokens.count, tokens[index + 1].text == "(" else {
                return false
            }
            return tokens[index + 2].text == "g_Texture\(expectedSlot)"
                && ["texSample2D", "texture2D"].contains(tokens[index].text)
        }
    }

    private static func exactUses(
        _ name: String,
        expected: [Int],
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [Token]
    ) -> Bool {
        guard lowerBound < upperBound else { return false }
        return ((lowerBound + 1)..<upperBound).filter {
            tokens[$0].text == name
        } == expected.sorted()
    }

    private static func noControlFlow(
        _ main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "return", "discard", "?",
        ]
        return !main.bodyRange.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func rootAssignment(
        _ index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        index + 1 < tokens.count && tokens[index + 1].text == "="
            && body.contains(index)
            && SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index,
                tokens: tokens,
                body: body
            )
    }

    private static func identifier(
        _ tokens: ArraySlice<Token>
    ) -> String? {
        guard tokens.count == 1,
              tokens.first?.kind == .identifier else { return nil }
        return tokens.first?.text
    }

    private static func member(
        _ tokens: ArraySlice<Token>,
        name: String,
        component: Set<String>
    ) -> Bool {
        guard tokens.count == 3,
              tokens[tokens.startIndex].text == name,
              tokens[tokens.index(after: tokens.startIndex)].text == ".",
              component.contains(
                  tokens[tokens.index(tokens.startIndex, offsetBy: 2)].text
              ) else { return false }
        return true
    }
}
