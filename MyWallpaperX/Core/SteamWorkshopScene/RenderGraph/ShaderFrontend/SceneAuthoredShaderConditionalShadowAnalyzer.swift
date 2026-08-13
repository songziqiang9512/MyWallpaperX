import Foundation

/// Proves a bounded same-source shadow union in the authored straight-color
/// domain. Both color leaves sample one slot and every terminal branch is
/// explicit, so the emitter can unpremultiply both reads and premultiply once.
nonisolated enum SceneAuthoredShaderConditionalShadowAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Branches {
        let prelude: Range<Int>
        let firstCondition: ArraySlice<Token>
        let firstBody: Range<Int>
        let secondCondition: ArraySlice<Token>
        let secondBody: Range<Int>
        let fallbackBody: Range<Int>
    }

    struct SampleDefinition {
        let name: String
        let nameIndex: Int
        let sampleCall: Int
        let slot: Int
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 4,
              main.bodyRange.allSatisfy({
                  !["return", "discard", "for", "while", "do", "switch"]
                    .contains(tokens[$0].text)
              }),
              mainCallsAreBounded(main, fragment: fragment),
              let branches = terminalBranches(main: main, tokens: tokens),
              let definitions = sampledDefinitions(
                  in: branches.prelude,
                  main: main,
                  tokens: tokens
              ),
              definitions.count == 2,
              let scalarOneDefinitions = scalarOneDefinitions(
                  in: branches.prelude,
                  main: main,
                  tokens: tokens
              ),
              let base = definitions.first,
              let reflected = definitions.last,
              base.name != reflected.name,
              base.slot == reflected.slot,
              exactStatements(
                  branches.prelude,
                  starts: ([
                      base.nameIndex - 1,
                      reflected.nameIndex - 1,
                  ] + scalarOneDefinitions.map { $0.nameIndex - 1 }).sorted(),
                  tokens: tokens
              ),
              sampleCalls(in: main.bodyRange, tokens: tokens) == [
                  base.sampleCall, reflected.sampleCall,
              ],
              alphaThresholdCondition(
                  branches.firstCondition,
                  name: base.name,
                  fragment: fragment,
                  before: branches.firstBody.lowerBound
              ),
              positiveAlphaCondition(
                  branches.secondCondition,
                  name: reflected.name
              ),
              wholeFallback(
                  branches.firstBody,
                  outputUses: outputUses,
                  name: base.name,
                  tokens: tokens
              ),
              wholeFallback(
                  branches.fallbackBody,
                  outputUses: outputUses,
                  name: base.name,
                  tokens: tokens
              ),
              middleBranch(
                  branches.secondBody,
                  outputUses: outputUses,
                  base: base.name,
                  reflected: reflected.name,
                  scalarOne: scalarOneDefinitions.first?.name,
                  fragment: fragment
              ),
              scalarOneIsExact(
                  scalarOneDefinitions.first,
                  main: main,
                  tokens: tokens
              ),
              sampledValuesAreReadOnly(
                  [base.name, reflected.name],
                  definitions: [
                      base.name: base.nameIndex,
                      reflected.name: reflected.nameIndex,
                  ],
                  main: main,
                  tokens: tokens
              ) else {
            return nil
        }
        return base.slot
    }

    private static func sampledDefinitions(
        in range: Range<Int>,
        main: Unit.Function,
        tokens: [Token]
    ) -> [SampleDefinition]? {
        var result: [SampleDefinition] = []
        for index in range where index > range.lowerBound
            && index + 2 < range.upperBound
            && ["vec4", "float4"].contains(tokens[index - 1].text)
            && tokens[index].kind == .identifier
            && tokens[index + 1].text == "=" {
            guard SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index, tokens: tokens, body: main.bodyRange
            ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: index, in: tokens, body: main.bodyRange),
                  let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(expression) else {
                return nil
            }
            result.append(.init(
                name: tokens[index].text,
                nameIndex: index,
                sampleCall: expression.startIndex,
                slot: slot
            ))
        }
        return result
    }

    private static func middleBranch(
        _ range: Range<Int>,
        outputUses: [Int],
        base: String,
        reflected: String,
        scalarOne: String?,
        fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        let uses = outputUses.filter(range.contains)
        guard uses.count == 2,
              let rgb = uses.first,
              let alpha = uses.last,
              texts(tokens[rgb..<(rgb + 4)]) == ["gl_FragColor", ".", "rgb", "="],
              texts(tokens[alpha..<(alpha + 4)]) == ["gl_FragColor", ".", "a", "="],
              let rgbExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: rgb + 2, in: tokens, body: range),
              let blend = call(rgbExpression),
              blend.name == "ApplyBlending",
              blend.arguments.count == 4,
              let blendMode = number(blend.arguments[0]),
              blendMode == 0 || blendMode == 30,
              member(blend.arguments[1], name: base, component: "rgb"),
              uniformColor(blend.arguments[2], fragment: fragment),
              scalarExpression(
                  blend.arguments[3],
                  scalarOne: scalarOne,
                  fragment: fragment
              ),
              let alphaExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: alpha + 2, in: tokens, body: range),
              alphaUnion(
                  alphaExpression,
                  base: base,
                  reflected: reflected,
                  weight: blend.arguments[3]
              ),
              exactStatements(range, starts: [rgb, alpha], tokens: tokens),
              validBlendHelper(fragment, mode: blendMode) else {
            return false
        }
        return true
    }

    private static func alphaUnion(
        _ expression: ArraySlice<Token>,
        base: String,
        reflected: String,
        weight: ArraySlice<Token>
    ) -> Bool {
        guard let call = call(expression),
              call.name == "min",
              call.arguments.count == 2,
              number(call.arguments[0]) == 1 else { return false }
        let sum = Array(call.arguments[1])
        return sum.count == weight.count + 8
            && texts(sum[0..<4]) == [base, ".", "a", "+"]
            && texts(sum[4..<8]) == [reflected, ".", "a", "*"]
            && texts(sum[8..<sum.count]) == texts(weight)
    }

    private static func wholeFallback(
        _ range: Range<Int>,
        outputUses: [Int],
        name: String,
        tokens: [Token]
    ) -> Bool {
        let uses = outputUses.filter(range.contains)
        guard uses.count == 1,
              let output = uses.first,
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: range),
              texts(expression) == [name] else { return false }
        return exactStatements(range, starts: [output], tokens: tokens)
    }

    private static func alphaThresholdCondition(
        _ expression: ArraySlice<Token>,
        name: String,
        fragment: Unit,
        before boundary: Int
    ) -> Bool {
        let values = texts(strippingParentheses(expression))
        return values.count == 5
            && Array(values[0..<4]) == [name, ".", "a", ">"]
            && scalarName(values[4], fragment: fragment, before: boundary)
    }

    private static func positiveAlphaCondition(
        _ expression: ArraySlice<Token>,
        name: String
    ) -> Bool {
        let values = Array(strippingParentheses(expression))
        return values.count == 5
            && texts(values[0..<4]) == [name, ".", "a", ">"]
            && number(values[4...]) == 0
    }

    private static func uniformColor(
        _ expression: ArraySlice<Token>,
        fragment: Unit
    ) -> Bool {
        let values = Array(strippingParentheses(expression))
        let name: String?
        if values.count == 1 {
            name = values[0].text
        } else if values.count == 3,
                  values[1].text == ".",
                  values[2].text == "rgb" {
            name = values[0].text
        } else {
            name = nil
        }
        guard let name else { return false }
        return fragment.declarations.contains {
            $0.storage == .uniform
                && $0.name == name
                && ["vec3", "float3"].contains($0.typeName)
                && $0.arraySize == nil
        }
    }

    private static func scalarName(
        _ name: String,
        fragment: Unit,
        before boundary: Int
    ) -> Bool {
        let declarations = fragment.declarations.filter {
            $0.name == name
                && ["float", "int", "uint", "bool"].contains($0.typeName)
                && $0.arraySize == nil
        }
        guard declarations.count == 1,
              declarations[0].storage == .uniform else { return false }
        return !fragment.tokens.indices.contains { index in
            index < boundary
                && fragment.tokens[index].text == name
                && index + 1 < fragment.tokens.count
                && ["=", "+=", "-=", "*=", "/="].contains(
                    fragment.tokens[index + 1].text
                )
        }
    }

    private static func sampledValuesAreReadOnly(
        _ names: [String],
        definitions: [String: Int],
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let exactUseCounts = [names[0]: 6, names[1]: 3]
        for name in names {
            // The branch predicates above account for every legitimate use:
            // definition, alpha tests, terminal fallbacks, blend input and
            // alpha union. Any additional occurrence is an alias escape or a
            // hidden side effect inside another expression.
            guard main.bodyRange.filter({ tokens[$0].text == name }).count
                    == exactUseCounts[name] else {
                return false
            }
            for index in main.bodyRange where tokens[index].text == name
                && index != definitions[name] {
                let next = index + 1 < main.bodyRange.upperBound
                    ? tokens[index + 1].text : ""
                if ["=", "+=", "-=", "*=", "/=", "++", "--"].contains(next) {
                    return false
                }
                let previous = index > main.bodyRange.lowerBound
                    ? tokens[index - 1].text : ""
                if ["++", "--"].contains(previous) { return false }
                if next == ".",
                   index + 3 < main.bodyRange.upperBound,
                   ["=", "+=", "-=", "*=", "/=", "++", "--"].contains(
                       tokens[index + 3].text
                   ) {
                    return false
                }
                if next == "[",
                   let close = matching(index + 1, tokens: tokens),
                   close + 1 < main.bodyRange.upperBound,
                   ["=", "+=", "-=", "*=", "/=", "++", "--"].contains(
                       tokens[close + 1].text
                   ) {
                    return false
                }
            }
        }
        return true
    }

    private static func validBlendHelper(_ fragment: Unit, mode: Double) -> Bool {
        let shadowedBuiltins: Set<String> = [
            "CAST3", "float3", "lerp", "max", "min", "mix", "vec3",
        ]
        let helpers = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard fragment.functions.allSatisfy({
                  $0.name == "ApplyBlending"
                      || !shadowedBuiltins.contains($0.name)
              }),
              helpers.count == 1,
              let helper = helpers.first,
              let names = blendParameterNames(helper, fragment: fragment),
              let returns = rootReturnExpressions(helper, fragment: fragment) else {
            return false
        }
        if mode == 0 {
            return returns.count == 1
                && simpleNormalBlend(returns[0], names: names)
        }
        return returns.count == 1 && simpleNormalBlend(returns[0], names: names)
            || returns.count == 2
                && modeThirtyTint(returns[0], names: names)
                && simpleNormalBlend(returns[1], names: names)
    }

    private static func simpleNormalBlend(
        _ expression: ArraySlice<Token>,
        names: [String]
    ) -> Bool {
        guard let call = call(expression),
              ["mix", "lerp"].contains(call.name),
              call.arguments.count == 3 else { return false }
        return identifier(call.arguments[0]) == names[1]
            && identifier(strippingParentheses(call.arguments[1])) == names[2]
            && identifier(call.arguments[2]) == names[3]
    }

    private static func modeThirtyTint(
        _ expression: ArraySlice<Token>,
        names: [String]
    ) -> Bool {
        guard let call = call(expression),
              ["mix", "lerp"].contains(call.name),
              call.arguments.count == 3,
              identifier(call.arguments[0]) == names[1],
              identifier(call.arguments[2]) == names[3] else { return false }
        let value = texts(call.arguments[1]).joined()
        let base = names[1], tint = names[2]
        return [
            "(CAST3(max(\(base).x,max(\(base).y,\(base).z)))*\(tint))",
            "CAST3(max(\(base).x,max(\(base).y,\(base).z))*\(tint)",
            "vec3(max(\(base).x,max(\(base).y,\(base).z))*\(tint)",
            "float3(max(\(base).x,max(\(base).y,\(base).z))*\(tint)",
        ].contains(value)
    }
}
