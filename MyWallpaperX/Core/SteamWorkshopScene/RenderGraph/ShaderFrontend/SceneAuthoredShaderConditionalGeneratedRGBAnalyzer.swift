import Foundation

/// Proves a bounded post-process that keeps one sampled carrier alpha while a
/// conditional block replaces its RGB with generated color. Generated color
/// samples remain separate facts so frame finalization can require them to be
/// opaque before the straight-color boundary is admitted.
nonisolated enum SceneAuthoredShaderConditionalGeneratedRGBAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let alphaCarrierSlot: Int
        let generatedOpaqueColorSlots: Set<Int>
        let scalarRedSlots: Set<Int>
        let scalarGreenSlots: Set<Int>
        let scalarBlueSlots: Set<Int>
        let scalarAlphaSlots: Set<Int>
        let sampleCallCounts: [Int: Int]
        let generatedSampleCallCounts: [Int: Int]
        let scalarRedSampleCallCounts: [Int: Int]
        let scalarGreenSampleCallCounts: [Int: Int]
        let scalarBlueSampleCallCounts: [Int: Int]
        let scalarAlphaSampleCallCounts: [Int: Int]
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
        if let fact = analyzeGeneratedReplacement(fragment) {
            return fact
        }
        if let fact = analyzeExhaustiveGeneratedFilter(fragment) {
            return fact
        }
        return SceneAuthoredShaderConditionalUnderlayRGBAnalyzer.analyze(fragment)
    }

    private static func analyzeGeneratedReplacement(_ fragment: Unit) -> Fact? {
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
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output,
                tokens: tokens,
                body: main.bodyRange
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ),
              statementEndsRange(
                  outputExpression,
                  range: (main.bodyRange.lowerBound + 1)..<(
                      main.bodyRange.upperBound - 1
                  ),
                  tokens: tokens
              ),
              let outputArguments = callArguments(
                  outputExpression,
                  functions: ["vec4", "float4"],
                  count: 2
              ),
              let colorName = identifier(outputArguments[0]),
              let carrierName = memberName(
                outputArguments[1],
                components: ["a", "w"]
              ),
              colorName != carrierName,
              let carrierDefinition = uniqueDefinition(
                carrierName,
                types: ["vec4", "float4"],
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ),
              let carrierInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: carrierDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let carrierSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(carrierInitializer),
              let colorDefinition = uniqueDefinition(
                colorName,
                types: ["vec3", "float3"],
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ),
              carrierDefinition < colorDefinition,
              let colorInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: colorDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              memberName(
                colorInitializer,
                components: ["rgb", "xyz"]
              ) == carrierName,
              let conditionalBody = soleConditionalBody(
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ),
              !conditionalBody.contains(where: {
                  ["if", "else", "for", "while", "do", "switch",
                   "discard", "return"].contains(tokens[$0].text)
              }) else { return nil }

        let writes = colorWrites(
            colorName,
            after: colorDefinition,
            before: output,
            tokens: tokens,
            body: main.bodyRange
        )
        guard writes.count >= 3,
              writes.allSatisfy({ conditionalBody.contains($0.nameIndex) }),
              let seed = rgbSampleSlot(writes[0].expression),
              writes[0].member == nil,
              writes[0].operation == "=",
              let terminal = writes.last,
              ["rgb", "xyz"].contains(terminal.member ?? ""),
              terminal.operation == "=",
              let terminalCall = functionCall(terminal.expression),
              terminalCall.arguments.count == 4,
              memberName(
                terminalCall.arguments[1],
                components: ["rgb", "xyz"]
              ) == carrierName,
              identifierOrRGBMember(
                terminalCall.arguments[2],
                named: colorName
              ),
              terminalCall.arguments[0].allSatisfy({
                  $0.text != colorName && $0.text != carrierName
              }),
              terminalCall.arguments[3].allSatisfy({
                  $0.text != colorName && $0.text != carrierName
              }),
              statementEndsRange(
                  terminal.expression,
                  range: conditionalBody,
                  tokens: tokens
              ),
              helperIsPureRGB(
                  terminalCall.name,
                  fragment: fragment,
                  main: main
              ),
              mainCallGraphIsBounded(
                  fragment: fragment,
                  main: main,
                  terminalHelper: terminalCall.name
              ),
              SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .writesOnlyLocalState(
                    main,
                    tokens: tokens,
                    allowingExternalWrites: ["gl_FragColor"]
                ) else { return nil }

        var generatedSlots: Set<Int> = [seed]
        var sawScale = false
        for write in writes.dropFirst().dropLast() {
            switch (write.member, write.operation) {
            case (nil, "+="):
                guard !sawScale, let slot = rgbSampleSlot(write.expression) else {
                    return nil
                }
                generatedSlots.insert(slot)
            case (nil, "*="):
                guard !sawScale,
                      write.expression.allSatisfy({ token in
                          !["texSample2D", "texture2D", colorName, carrierName]
                            .contains(token.text)
                      }) else { return nil }
                sawScale = true
            default:
                return nil
            }
        }
        guard !generatedSlots.contains(carrierSlot) else { return nil }

        let calls = textureSampleCalls(in: main.bodyRange, tokens: tokens)
        guard !calls.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        var scalarRedSlots = Set<Int>()
        var scalarGreenSlots = Set<Int>()
        var scalarBlueSlots = Set<Int>()
        var scalarAlphaSlots = Set<Int>()
        var generatedSampleCallCounts: [Int: Int] = [:]
        var scalarRedSampleCallCounts: [Int: Int] = [:]
        var scalarGreenSampleCallCounts: [Int: Int] = [:]
        var scalarBlueSampleCallCounts: [Int: Int] = [:]
        var scalarAlphaSampleCallCounts: [Int: Int] = [:]
        for call in calls {
            counts[call.slot, default: 0] += 1
            if call.range == carrierInitializer.startIndex..<carrierInitializer.endIndex {
                guard call.slot == carrierSlot else { return nil }
                continue
            }
            let component = sampleComponent(after: call.range, tokens: tokens)
            if generatedSlots.contains(call.slot),
               ["rgb", "xyz"].contains(component ?? "") {
                generatedSampleCallCounts[call.slot, default: 0] += 1
                continue
            }
            switch component {
            case "r", "x":
                scalarRedSlots.insert(call.slot)
                scalarRedSampleCallCounts[call.slot, default: 0] += 1
            case "g", "y":
                scalarGreenSlots.insert(call.slot)
                scalarGreenSampleCallCounts[call.slot, default: 0] += 1
            case "b", "z":
                scalarBlueSlots.insert(call.slot)
                scalarBlueSampleCallCounts[call.slot, default: 0] += 1
            case "a", "w":
                scalarAlphaSlots.insert(call.slot)
                scalarAlphaSampleCallCounts[call.slot, default: 0] += 1
            default: return nil
            }
        }
        let scalarSlots = scalarRedSlots
            .union(scalarGreenSlots)
            .union(scalarBlueSlots)
            .union(scalarAlphaSlots)
        guard counts[carrierSlot] == 1,
              generatedSlots.allSatisfy({ counts[$0, default: 0] > 0 }),
              generatedSlots.isDisjoint(with: scalarSlots) else { return nil }

        let allowedCarrierUses = Set([
            carrierDefinition,
            colorInitializer.startIndex,
            terminalCall.arguments[1].startIndex,
            outputArguments[1].startIndex,
        ])
        guard Set(main.bodyRange.filter({ tokens[$0].text == carrierName }))
                == allowedCarrierUses else { return nil }

        let allowedColorUses = Set(
            [colorDefinition, outputArguments[0].startIndex]
                + writes.map(\.nameIndex)
                + [terminalCall.arguments[2].startIndex]
        )
        guard Set(main.bodyRange.filter({ tokens[$0].text == colorName }))
                == allowedColorUses else { return nil }

        return .init(
            alphaCarrierSlot: carrierSlot,
            generatedOpaqueColorSlots: generatedSlots,
            scalarRedSlots: scalarRedSlots,
            scalarGreenSlots: scalarGreenSlots,
            scalarBlueSlots: scalarBlueSlots,
            scalarAlphaSlots: scalarAlphaSlots,
            sampleCallCounts: counts,
            generatedSampleCallCounts: generatedSampleCallCounts,
            scalarRedSampleCallCounts: scalarRedSampleCallCounts,
            scalarGreenSampleCallCounts: scalarGreenSampleCallCounts,
            scalarBlueSampleCallCounts: scalarBlueSampleCallCounts,
            scalarAlphaSampleCallCounts: scalarAlphaSampleCallCounts
        )
    }

    private struct Write {
        let nameIndex: Int
        let member: String?
        let operation: String
        let expression: ArraySlice<Token>
    }

    private struct SampleCall {
        let slot: Int
        let range: Range<Int>
    }

    private struct FunctionCall {
        let name: String
        let arguments: [ArraySlice<Token>]
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

    private static func soleConditionalBody(
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Range<Int>? {
        let forbiddenControlFlow: Set<String> = [
            "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue",
        ]
        let conditions = body.filter {
            $0 < boundary && tokens[$0].text == "if"
        }
        guard conditions.count == 1, let condition = conditions.first,
              !body.contains(where: {
                  forbiddenControlFlow.contains(tokens[$0].text)
              }),
              condition + 1 < boundary,
              tokens[condition + 1].text == "(",
              let conditionClose = matchingDelimiter(
                opening: condition + 1,
                tokens: tokens,
                boundary: boundary
              ), conditionClose + 1 < boundary,
              tokens[conditionClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                opening: conditionClose + 1,
                tokens: tokens,
                boundary: boundary
              ) else { return nil }
        return (conditionClose + 2)..<bodyClose
    }

    private static func statementEndsRange(
        _ expression: ArraySlice<Token>,
        range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        !expression.isEmpty
            && range.contains(expression.startIndex)
            && expression.endIndex < range.upperBound
            && tokens[expression.endIndex].text == ";"
            && expression.endIndex + 1 == range.upperBound
    }

    private static func colorWrites(
        _ name: String,
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [Write] {
        var result: [Write] = []
        for index in (lowerBound + 1)..<upperBound where tokens[index].text == name {
            var cursor = index + 1
            var member: String?
            if cursor + 1 < upperBound, tokens[cursor].text == "." {
                member = tokens[cursor + 1].text
                cursor += 2
            }
            guard cursor < upperBound,
                  ["=", "+=", "*="].contains(tokens[cursor].text),
                  let expression = statementExpression(
                    afterOperator: cursor,
                    tokens: tokens,
                    body: body
                  ) else { continue }
            result.append(.init(
                nameIndex: index,
                member: member,
                operation: tokens[cursor].text,
                expression: expression
            ))
        }
        return result
    }

    private static func rgbSampleSlot(_ expression: ArraySlice<Token>) -> Int? {
        let values = Array(expression)
        guard values.count >= 4,
              values[values.count - 2].text == ".",
              ["rgb", "xyz"].contains(values.last?.text ?? "") else { return nil }
        let prefix = values[0..<(values.count - 2)]
        return SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(prefix)
    }

    private static func statementExpression(
        afterOperator operation: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> ArraySlice<Token>? {
        let start = operation + 1
        guard body.contains(start) else { return nil }
        var stack: [String] = []
        let closing: [String: String] = [")": "(", "]": "["]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "["].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                return start < index ? tokens[start..<index] : nil
            }
        }
        return nil
    }

    private static func textureSampleCalls(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [SampleCall] {
        var result: [SampleCall] = []
        for index in body where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < body.upperBound,
                  tokens[index + 1].text == "(",
                  let close = matchingDelimiter(
                    opening: index + 1,
                    tokens: tokens,
                    boundary: body.upperBound
                  ), let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(tokens[index...close]) else {
                return []
            }
            result.append(.init(slot: slot, range: index..<(close + 1)))
        }
        return result
    }

    private static func sampleComponent(
        after range: Range<Int>,
        tokens: [Token]
    ) -> String? {
        guard range.upperBound + 1 < tokens.count,
              tokens[range.upperBound].text == "." else { return nil }
        return tokens[range.upperBound + 1].text
    }

    private static func helperIsPureRGB(
        _ name: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let helpers = fragment.functions.filter { $0.name == name }
        guard helpers.count == 1, let helper = helpers.first,
              ["vec3", "float3"].contains(helper.returnType),
              fragment.tokens.filter({ $0.text == name }).count == 2,
              let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .safeReadOnlyHelperClosure(
                    rootName: name,
                    fragment: fragment
                ),
              closure.contains(helper),
              closure.allSatisfy({ function in
                  !function.bodyRange.contains(where: {
                      ["texSample2D", "texture2D"]
                        .contains(fragment.tokens[$0].text)
                  })
              }) else {
            return false
        }
        return fragment.functions.allSatisfy { function in
            function.name == main.name || !function.bodyRange.contains(where: {
                ["texSample2D", "texture2D"].contains(fragment.tokens[$0].text)
            })
        }
    }

    /// This exact analyzer does not grant arbitrary calls in `main` product
    /// authority. The authored form needs only constructors, declared samples,
    /// and the already-proved terminal blend helper. Everything else fails
    /// closed instead of hiding another resource read or side effect.
    private static func mainCallGraphIsBounded(
        fragment: Unit,
        main: Unit.Function,
        terminalHelper: String
    ) -> Bool {
        let allowed: Set<String> = [
            "if",
            "texSample2D", "texture2D",
            "bool", "int", "uint", "float", "double",
            "bvec2", "bvec3", "bvec4",
            "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4",
            "vec2", "vec3", "vec4",
            "float2", "float3", "float4",
            terminalHelper,
        ]
        return main.bodyRange.allSatisfy { index in
            guard index + 1 < main.bodyRange.upperBound,
                  fragment.tokens[index].kind == .identifier,
                  fragment.tokens[index + 1].text == "(" else {
                return true
            }
            let name = fragment.tokens[index].text
            if allowed.contains(name) { return true }
            // A second authored helper would need its own value/side-effect
            // proof; this bounded form intentionally owns only one helper root.
            return false
        }
    }

    private static func functionCall(
        _ expression: ArraySlice<Token>
    ) -> FunctionCall? {
        guard expression.count >= 4,
              let first = expression.first,
              first.kind == .identifier,
              expression[expression.index(after: expression.startIndex)].text == "(",
              expression.last?.text == ")",
              let arguments = split(expression.dropFirst(2).dropLast()) else {
            return nil
        }
        return .init(name: first.text, arguments: arguments)
    }

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        functions: Set<String>,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard let call = functionCall(expression),
              functions.contains(call.name),
              call.arguments.count == count else { return nil }
        return call.arguments
    }

    private static func split(
        _ tokens: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        guard !tokens.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var depth = 0
        var start = tokens.startIndex
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(tokens[start..<index])
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < tokens.endIndex else { return nil }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    private static func identifier(_ tokens: ArraySlice<Token>) -> String? {
        guard tokens.count == 1, tokens.first?.kind == .identifier else {
            return nil
        }
        return tokens.first?.text
    }

    private static func identifierOrRGBMember(
        _ tokens: ArraySlice<Token>,
        named name: String
    ) -> Bool {
        identifier(tokens) == name
            || memberName(tokens, components: ["rgb", "xyz"]) == name
    }

    private static func memberName(
        _ tokens: ArraySlice<Token>,
        components: Set<String>
    ) -> String? {
        guard tokens.count == 3,
              tokens[tokens.startIndex].kind == .identifier,
              tokens[tokens.index(after: tokens.startIndex)].text == ".",
              components.contains(tokens[tokens.index(
                tokens.startIndex,
                offsetBy: 2
              )].text) else { return nil }
        return tokens[tokens.startIndex].text
    }

    private static func matchingDelimiter(
        opening: Int,
        tokens: [Token],
        boundary: Int
    ) -> Int? {
        let open = tokens[opening].text
        let close = open == "(" ? ")" : open == "{" ? "}" : nil
        guard let close else { return nil }
        var depth = 0
        for index in opening..<boundary {
            if tokens[index].text == open { depth += 1 }
            if tokens[index].text == close {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }
}
