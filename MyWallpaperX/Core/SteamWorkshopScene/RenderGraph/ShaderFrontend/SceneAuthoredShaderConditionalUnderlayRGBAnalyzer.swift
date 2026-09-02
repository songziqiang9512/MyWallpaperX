import Foundation

/// Proves one conditional post-process that composes a distinct color underlay
/// beneath a sampled carrier, blends source-generated RGB over that result, and
/// preserves the carrier alpha. Texture and variable names are discovered from
/// source structure; effect and sample identity never participate.
nonisolated enum SceneAuthoredShaderConditionalUnderlayRGBAnalyzer {
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit
    typealias Fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact

    private struct Call {
        let name: String
        let arguments: [ArraySlice<Token>]
    }

    private struct MemberWrite {
        let root: Int
        let component: String
        let expression: ArraySlice<Token>
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputUses = main.bodyRange.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output, tokens: tokens, body: main.bodyRange
              ), let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output, in: tokens, body: main.bodyRange
                ), let carrierName = identifier(outputExpression),
              outputExpression.endIndex + 1 == main.bodyRange.upperBound - 1,
              let conditional = soleConditional(
                  before: output, in: main, tokens: tokens
              ), let carrierDefinition = uniqueDefinition(
                  carrierName,
                  types: ["vec4", "float4"],
                  before: conditional.lowerBound,
                  tokens: tokens,
                  body: main.bodyRange
              ), let carrierInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: carrierDefinition, in: tokens, body: main.bodyRange
                ), let carrierSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(carrierInitializer)
        else { return nil }

        let writes = memberWrites(
            carrierName, before: output, tokens: tokens, body: main.bodyRange
        )
        let rgbWrites = writes.filter { ["rgb", "xyz"].contains($0.component) }
        let alphaWrites = writes.filter { ["a", "w"].contains($0.component) }
        guard rgbWrites.count == 2,
              alphaWrites.count == 1,
              writes.count == 3,
              rgbWrites.allSatisfy({ conditional.contains($0.root) }),
              alphaWrites.allSatisfy({ conditional.contains($0.root) }),
              rgbWrites[0].root < rgbWrites[1].root,
              rgbWrites[1].root < alphaWrites[0].root,
              let underlay = uniqueRGBSampleDefinition(
                  excluding: carrierName,
                  in: conditional,
                  tokens: tokens
              ), underlay.slot != carrierSlot,
              underlay.definition < rgbWrites[0].root,
              exactUnderlayComposition(
                  rgbWrites[0].expression,
                  underlayName: underlay.name,
                  carrierName: carrierName
              ), let blend = call(rgbWrites[1].expression),
              blend.arguments.count == 4,
              let mode = integer(blend.arguments[0]),
              (0 ... 32).contains(mode),
              member(
                  blend.arguments[1], name: carrierName,
                  components: ["rgb", "xyz"]
              ), expressionIsIndependent(
                  blend.arguments[2], of: [carrierName, underlay.name]
              ), expressionIsIndependent(
                  blend.arguments[3], of: [carrierName, underlay.name]
              ), helperReturnsRGBAndIsSafe(
                  blend.name, fragment: fragment
              ), let alpha = call(alphaWrites[0].expression),
              alpha.arguments.count == 3,
              member(
                  alpha.arguments[0], name: carrierName,
                  components: ["a", "w"]
              ), expressionIsIndependent(
                  alpha.arguments[1], of: [carrierName, underlay.name]
              ), expressionIsIndependent(
                  alpha.arguments[2], of: [carrierName, underlay.name]
              ), helperPreservesFirstArgument(
                  alpha.name, fragment: fragment
              ), exactMainTextureSamples(
                  carrierSlot: carrierSlot,
                  underlaySlot: underlay.slot,
                  main: main,
                  tokens: tokens
              ), exactCarrierUses(
                  carrierName,
                  definition: carrierDefinition,
                  rgbWrites: rgbWrites,
                  alphaWrite: alphaWrites[0],
                  outputExpression: outputExpression,
                  firstBlend: call(rgbWrites[0].expression)!,
                  secondBlend: blend,
                  alphaCall: alpha,
                  main: main,
                  tokens: tokens
              ), exactUnderlayUses(
                  underlay.name,
                  definition: underlay.definition,
                  composition: call(rgbWrites[0].expression)!,
                  main: main,
                  tokens: tokens
              ), reachableHelpersAreSafe(main: main, fragment: fragment),
              SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .writesOnlyLocalState(
                    main,
                    tokens: tokens,
                    allowingExternalWrites: ["gl_FragColor"]
                ) else { return nil }

        return .init(
            alphaCarrierSlot: carrierSlot,
            generatedOpaqueColorSlots: [underlay.slot],
            scalarRedSlots: [],
            scalarGreenSlots: [],
            scalarBlueSlots: [],
            scalarAlphaSlots: [],
            sampleCallCounts: [carrierSlot: 1, underlay.slot: 1],
            generatedSampleCallCounts: [underlay.slot: 1],
            scalarRedSampleCallCounts: [:],
            scalarGreenSampleCallCounts: [:],
            scalarBlueSampleCallCounts: [:],
            scalarAlphaSampleCallCounts: [:]
        )
    }

    private static func soleConditional(
        before output: Int,
        in main: Unit.Function,
        tokens: [Token]
    ) -> Range<Int>? {
        let conditions = main.bodyRange.filter { tokens[$0].text == "if" }
        let forbidden: Set<String> = [
            "else", "for", "while", "do", "switch", "discard", "return",
            "break", "continue",
        ]
        guard conditions.count == 1, let condition = conditions.first,
              condition < output,
              !main.bodyRange.contains(where: { forbidden.contains(tokens[$0].text) }),
              braceDepth(before: condition, in: main.bodyRange, tokens: tokens) == 1,
              condition + 1 < output, tokens[condition + 1].text == "(",
              let conditionClose = matchingDelimiter(
                  condition + 1, tokens: tokens, upperBound: output
              ), conditionClose + 1 < output,
              tokens[conditionClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  conditionClose + 1, tokens: tokens, upperBound: output
              ), bodyClose < output else { return nil }
        return (conditionClose + 2)..<bodyClose
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
                  match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func uniqueRGBSampleDefinition(
        excluding excluded: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> (name: String, definition: Int, slot: Int)? {
        let matches = range.compactMap { index -> (String, Int, Int)? in
            guard index > range.lowerBound, index + 1 < range.upperBound,
                  tokens[index].kind == .identifier,
                  tokens[index].text != excluded,
                  ["vec3", "float3"].contains(tokens[index - 1].text),
                  tokens[index + 1].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: index, in: tokens,
                        body: (range.lowerBound - 1)..<(range.upperBound + 1)
                    ), let slot = rgbSampleSlot(expression) else { return nil }
            return (tokens[index].text, index, slot)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func memberWrites(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [MemberWrite] {
        body.compactMap { index in
            guard index + 3 < boundary,
                  tokens[index].text == name,
                  tokens[index + 1].text == ".",
                  tokens[index + 3].text == "=",
                  let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: index + 2, in: tokens, body: body
                    ) else { return nil }
            return .init(
                root: index,
                component: tokens[index + 2].text,
                expression: expression
            )
        }
    }

    private static func exactUnderlayComposition(
        _ expression: ArraySlice<Token>,
        underlayName: String,
        carrierName: String
    ) -> Bool {
        guard let blend = call(expression),
              ["mix", "lerp"].contains(blend.name),
              blend.arguments.count == 3 else { return false }
        return identifier(blend.arguments[0]) == underlayName
            && member(
                blend.arguments[1], name: carrierName,
                components: ["rgb", "xyz"]
            )
            && member(
                blend.arguments[2], name: carrierName,
                components: ["a", "w"]
            )
    }

    private static func helperReturnsRGBAndIsSafe(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        guard let function = uniqueFunction(named: name, fragment: fragment),
              ["vec3", "float3"].contains(function.returnType) else {
            return false
        }
        return safeHelperClosure(name, fragment: fragment) != nil
    }

    private static func helperPreservesFirstArgument(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        guard let function = uniqueFunction(named: name, fragment: fragment),
              function.returnType == "float",
              let parameters = parameterNames(function, tokens: fragment.tokens),
              parameters.count == 3,
              safeHelperClosure(name, fragment: fragment) != nil,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(
                    in: function.bodyRange, tokens: fragment.tokens
                ) else { return false }
        let tokens = fragment.tokens
        if statements.count == 1 {
            return Array(tokens[statements[0]]).map(\.text)
                == ["return", parameters[0]]
        }
        guard statements.count == 2 else { return false }
        let alias = Array(tokens[statements[0]])
        guard alias.count == 4,
              alias[0].text == "float",
              alias[1].kind == .identifier,
              alias[2].text == "=",
              alias[3].text == parameters[0],
              let returned = call(tokens[statements[1]].dropFirst()),
              tokens[statements[1].lowerBound].text == "return",
              ["mix", "lerp"].contains(returned.name),
              returned.arguments.count == 3,
              identifier(returned.arguments[0]) == parameters[0],
              identifier(returned.arguments[1]) == alias[1].text else {
            return false
        }
        let body = tokens[function.bodyRange]
        return body.filter({ $0.text == parameters[0] }).count == 2
            && body.filter({ $0.text == alias[1].text }).count == 2
    }

    private static func reachableHelpersAreSafe(
        main: Unit.Function,
        fragment: Unit
    ) -> Bool {
        let names = Set(fragment.functions.map(\.name)).subtracting(["main"])
        let roots = Set(main.bodyRange.compactMap { index -> String? in
            guard index + 1 < fragment.tokens.count,
                  names.contains(fragment.tokens[index].text),
                  fragment.tokens[index + 1].text == "(" else { return nil }
            return fragment.tokens[index].text
        })
        return roots.allSatisfy { safeHelperClosure($0, fragment: fragment) != nil }
    }

    private static func safeHelperClosure(
        _ name: String,
        fragment: Unit
    ) -> [Unit.Function]? {
        guard let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
            .safeReadOnlyHelperClosure(rootName: name, fragment: fragment),
              closure.allSatisfy({ function in
                  !function.bodyRange.contains(where: { index in
                      let token = fragment.tokens[index].text
                      return ["texSample2D", "texture2D", "texelFetch"]
                        .contains(token)
                          || token.hasPrefix("image")
                  })
              }) else { return nil }
        return closure
    }

    private static func exactMainTextureSamples(
        carrierSlot: Int,
        underlaySlot: Int,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let slots = main.bodyRange.compactMap { index -> Int? in
            guard ["texSample2D", "texture2D"].contains(tokens[index].text),
                  index + 2 < main.bodyRange.upperBound,
                  tokens[index + 1].text == "(" else { return nil }
            return textureSlot(tokens[index + 2].text)
        }
        return slots == [carrierSlot, underlaySlot]
    }

    private static func exactCarrierUses(
        _ name: String,
        definition: Int,
        rgbWrites: [MemberWrite],
        alphaWrite: MemberWrite,
        outputExpression: ArraySlice<Token>,
        firstBlend: Call,
        secondBlend: Call,
        alphaCall: Call,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let expected = Set([
            definition,
            rgbWrites[0].root,
            rgbWrites[1].root,
            alphaWrite.root,
            firstBlend.arguments[1].startIndex,
            firstBlend.arguments[2].startIndex,
            secondBlend.arguments[1].startIndex,
            alphaCall.arguments[0].startIndex,
            outputExpression.startIndex,
        ])
        return Set(main.bodyRange.filter({ tokens[$0].text == name })) == expected
    }

    private static func exactUnderlayUses(
        _ name: String,
        definition: Int,
        composition: Call,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        Set(main.bodyRange.filter({ tokens[$0].text == name }))
            == Set([definition, composition.arguments[0].startIndex])
    }

    private static func call(_ expression: ArraySlice<Token>) -> Call? {
        guard expression.count >= 3,
              let first = expression.first,
              first.kind == .identifier,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")",
              let arguments = splitArguments(
                  expression.dropFirst(2).dropLast()
              ) else { return nil }
        return .init(name: first.text, arguments: arguments)
    }

    private static func splitArguments(
        _ content: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        guard !content.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var start = content.startIndex
        var depth = 0
        for index in content.indices {
            if ["(", "["].contains(content[index].text) { depth += 1 }
            if [")", "]"].contains(content[index].text) { depth -= 1 }
            if content[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(content[start..<index])
                start = content.index(after: index)
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < content.endIndex else { return nil }
        result.append(content[start..<content.endIndex])
        return result
    }

    private static func parameterNames(
        _ function: Unit.Function,
        tokens: [Token]
    ) -> [String]? {
        let content = tokens[function.parameterRange].filter {
            !["(", ")"].contains($0.text)
        }
        guard let parts = splitArguments(ArraySlice(content)) else { return nil }
        let names = parts.compactMap { part in
            part.last(where: { $0.kind == .identifier })?.text
        }
        return names.count == parts.count ? names : nil
    }

    private static func rgbSampleSlot(_ expression: ArraySlice<Token>) -> Int? {
        guard expression.count >= 3,
              expression[expression.index(expression.endIndex, offsetBy: -2)].text == ".",
              ["rgb", "xyz"].contains(expression.last?.text ?? "") else {
            return nil
        }
        return SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(
            expression.dropLast(2)
        )
    }

    private static func member(
        _ expression: ArraySlice<Token>,
        name: String,
        components: Set<String>
    ) -> Bool {
        expression.count == 3
            && expression.first?.text == name
            && expression[expression.index(after: expression.startIndex)].text == "."
            && components.contains(expression.last?.text ?? "")
    }

    private static func identifier(_ expression: ArraySlice<Token>) -> String? {
        expression.count == 1 && expression.first?.kind == .identifier
            ? expression.first?.text : nil
    }

    private static func integer(_ expression: ArraySlice<Token>) -> Int? {
        guard expression.count == 1, let raw = expression.first?.text else {
            return nil
        }
        return Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "uU")))
    }

    private static func expressionIsIndependent(
        _ expression: ArraySlice<Token>,
        of names: Set<String>
    ) -> Bool {
        !expression.isEmpty && expression.allSatisfy { !names.contains($0.text) }
    }

    private static func uniqueFunction(
        named name: String,
        fragment: Unit
    ) -> Unit.Function? {
        let matches = fragment.functions.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private static func braceDepth(
        before boundary: Int,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        (range.lowerBound..<boundary).reduce(into: 0) { depth, index in
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
        }
    }

    private static func matchingDelimiter(
        _ opening: Int,
        tokens: [Token],
        upperBound: Int
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "{": "}"]
        guard let closing = pairs[tokens[opening].text] else { return nil }
        var depth = 0
        for index in opening..<upperBound {
            if tokens[index].text == tokens[opening].text { depth += 1 }
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }
}
