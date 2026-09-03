import Foundation

nonisolated extension SceneAuthoredShaderConditionalGeneratedRGBAnalyzer {
    private struct ExhaustiveBranches {
        let thenBody: Range<Int>
        let elseBody: Range<Int>
    }

    private struct WriteRoles {
        let alphaExpression: ArraySlice<Token>
        let rgbExpressionRanges: [Range<Int>]
    }

    private struct SampleCall {
        let slot: Int
        let range: Range<Int>
    }

    private struct SampleRoles {
        let generatedSlots: Set<Int>
        let scalarRedSlots: Set<Int>
        let scalarGreenSlots: Set<Int>
        let scalarBlueSlots: Set<Int>
        let scalarAlphaSlots: Set<Int>
        let counts: [Int: Int]
        let generatedCounts: [Int: Int]
        let scalarRedCounts: [Int: Int]
        let scalarGreenCounts: [Int: Int]
        let scalarBlueCounts: [Int: Int]
        let scalarAlphaCounts: [Int: Int]
    }

    /// Proves a final source/filter branch in which one sampled carrier is
    /// returned unchanged by the fallback branch, while the active branch
    /// builds RGB from separate sampled color and restores the carrier alpha
    /// immediately before its output. Helper texture reads are admitted only
    /// through pure vec3 helpers used by RGB writes.
    static func analyzeExhaustiveGeneratedFilter(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputUses = main.bodyRange.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 2,
              !main.bodyRange.contains(where: {
                  ["return", "discard", "gl_FragDepth"].contains(tokens[$0].text)
              }),
              let branches = exhaustiveFinalBranches(main: main, tokens: tokens),
              let changedOutput = uniqueIndex(outputUses, in: branches.thenBody),
              let fallbackOutput = uniqueIndex(outputUses, in: branches.elseBody),
              outputEndsBranch(
                  changedOutput, branch: branches.thenBody, tokens: tokens
              ),
              outputEndsBranch(
                  fallbackOutput, branch: branches.elseBody, tokens: tokens
              ),
              let changedExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: changedOutput, in: tokens, body: main.bodyRange
                ),
              let fallbackExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: fallbackOutput, in: tokens, body: main.bodyRange
                ),
              let changedName = identifier(changedExpression),
              let carrierName = identifier(fallbackExpression),
              changedName != carrierName,
              let carrierDefinition = uniqueVectorDefinition(
                  carrierName,
                  before: branches.thenBody.lowerBound,
                  tokens: tokens,
                  body: main.bodyRange,
                  requiresUnconditionalWrite: true
              ),
              let carrierInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: carrierDefinition, in: tokens, body: main.bodyRange
                ),
              let carrierSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(carrierInitializer),
              let changedDefinition = uniqueVectorDefinition(
                  changedName,
                  before: changedOutput,
                  tokens: tokens,
                  body: (branches.thenBody.lowerBound - 1)..<(
                      branches.thenBody.upperBound + 1
                  ),
                  requiresUnconditionalWrite: true
              ),
              branches.thenBody.contains(changedDefinition),
              let changedInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: changedDefinition, in: tokens, body: main.bodyRange
                ),
              changedInitializer.allSatisfy({ token in
                  !["texSample2D", "texture2D", carrierName, changedName]
                    .contains(token.text)
              }),
              carrierIsReadOnly(
                  carrierName,
                  after: carrierDefinition,
                  fallbackExpression: fallbackExpression,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let writes = generatedFilterWrites(
                  changedName,
                  definition: changedDefinition,
                  output: changedOutput,
                  carrierName: carrierName,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              writes.alphaExpression.count == 3,
              writes.alphaExpression.first?.text == carrierName,
              writes.alphaExpression[writes.alphaExpression.index(
                  after: writes.alphaExpression.startIndex
              )].text == ".",
              ["a", "w"].contains(writes.alphaExpression.last?.text ?? ""),
              let samples = generatedFilterSamples(
                  fragment: fragment,
                  main: main,
                  carrierInitializer: carrierInitializer,
                  carrierSlot: carrierSlot,
                  rgbExpressionRanges: writes.rgbExpressionRanges
              ),
              !samples.generatedSlots.isEmpty,
              SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .writesOnlyLocalState(
                    main,
                    tokens: tokens,
                    allowingExternalWrites: ["gl_FragColor"]
                ) else { return nil }

        return .init(
            alphaCarrierSlot: carrierSlot,
            generatedOpaqueColorSlots: samples.generatedSlots,
            scalarRedSlots: samples.scalarRedSlots,
            scalarGreenSlots: samples.scalarGreenSlots,
            scalarBlueSlots: samples.scalarBlueSlots,
            scalarAlphaSlots: samples.scalarAlphaSlots,
            sampleCallCounts: samples.counts,
            generatedSampleCallCounts: samples.generatedCounts,
            scalarRedSampleCallCounts: samples.scalarRedCounts,
            scalarGreenSampleCallCounts: samples.scalarGreenCounts,
            scalarBlueSampleCallCounts: samples.scalarBlueCounts,
            scalarAlphaSampleCallCounts: samples.scalarAlphaCounts
        )
    }

    private static func exhaustiveFinalBranches(
        main: Unit.Function,
        tokens: [Token]
    ) -> ExhaustiveBranches? {
        let body = main.bodyRange
        guard body.count >= 8,
              tokens[body.lowerBound].text == "{",
              tokens[body.upperBound - 1].text == "}" else { return nil }
        var depth = 0
        var rootIfs: [Int] = []
        for index in body {
            if tokens[index].text == "if", depth == 1 { rootIfs.append(index) }
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0,
              rootIfs.count == 1,
              let rootIf = rootIfs.first,
              rootIf + 1 < body.upperBound,
              tokens[rootIf + 1].text == "(",
              let conditionEnd = matchingDelimiter(
                  opening: rootIf + 1, tokens: tokens, boundary: body.upperBound
              ),
              conditionEnd + 1 < body.upperBound,
              tokens[conditionEnd + 1].text == "{",
              let thenEnd = matchingDelimiter(
                  opening: conditionEnd + 1,
                  tokens: tokens,
                  boundary: body.upperBound
              ),
              thenEnd + 2 < body.upperBound,
              tokens[thenEnd + 1].text == "else" else { return nil }
        let thenBody = (conditionEnd + 2)..<thenEnd
        let elseStart = thenEnd + 2
        let elseBody: Range<Int>
        let end: Int
        if tokens[elseStart].text == "{" {
            guard let elseEnd = matchingDelimiter(
                opening: elseStart, tokens: tokens, boundary: body.upperBound
            ) else { return nil }
            elseBody = (elseStart + 1)..<elseEnd
            end = elseEnd + 1
        } else {
            guard let semicolon = (elseStart..<body.upperBound).first(where: {
                tokens[$0].text == ";"
            }) else { return nil }
            elseBody = elseStart..<(semicolon + 1)
            end = semicolon + 1
        }
        guard !thenBody.isEmpty,
              !elseBody.isEmpty,
              end == body.upperBound - 1 else { return nil }
        return .init(thenBody: thenBody, elseBody: elseBody)
    }

    private static func uniqueIndex(
        _ indices: [Int],
        in range: Range<Int>
    ) -> Int? {
        let matches = indices.filter(range.contains)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func outputEndsBranch(
        _ output: Int,
        branch: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        guard output + 1 < branch.upperBound,
              tokens[output + 1].text == "=",
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: (branch.lowerBound - 1)..<(branch.upperBound + 1)
                ) else { return false }
        return expression.endIndex < branch.upperBound
            && tokens[expression.endIndex].text == ";"
            && expression.endIndex + 1 == branch.upperBound
    }

    private static func uniqueVectorDefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>,
        requiresUnconditionalWrite: Bool
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index + 1 < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        if requiresUnconditionalWrite,
           !SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
               match, tokens: tokens, body: body
           ) { return nil }
        return match
    }

    private static func carrierIsReadOnly(
        _ name: String,
        after definition: Int,
        fallbackExpression: ArraySlice<Token>,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in (definition + 1)..<body.upperBound
        where tokens[index].text == name {
            if index == fallbackExpression.startIndex { continue }
            if index + 1 < body.upperBound,
               operators.contains(tokens[index + 1].text) { return false }
            if index + 3 < body.upperBound,
               tokens[index + 1].text == ".",
               operators.contains(tokens[index + 3].text) { return false }
        }
        return true
    }

    private static func generatedFilterWrites(
        _ name: String,
        definition: Int,
        output: Int,
        carrierName: String,
        tokens: [Token],
        body: Range<Int>
    ) -> WriteRoles? {
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        var rgbRanges: [Range<Int>] = []
        var alphaExpression: ArraySlice<Token>?
        for index in (definition + 1)..<output where tokens[index].text == name {
            var component: String?
            var operationIndex = index + 1
            if operationIndex + 1 < output,
               tokens[operationIndex].text == "." {
                component = tokens[operationIndex + 1].text
                operationIndex += 2
            }
            guard operationIndex < output,
                  operators.contains(tokens[operationIndex].text) else { continue }
            guard let expression = statementExpression(
                afterOperator: operationIndex, tokens: tokens, body: body
            ) else { return nil }
            switch component {
            case "rgb", "xyz":
                guard alphaExpression == nil else { return nil }
                rgbRanges.append(expression.startIndex..<expression.endIndex)
            case "a", "w":
                guard tokens[operationIndex].text == "=",
                      alphaExpression == nil else { return nil }
                alphaExpression = expression
            case nil:
                guard tokens[operationIndex].text != "=",
                      alphaExpression == nil else { return nil }
                rgbRanges.append(expression.startIndex..<expression.endIndex)
            default:
                return nil
            }
        }
        guard !rgbRanges.isEmpty,
              let alphaExpression,
              alphaExpression.endIndex + 1 == output,
              alphaExpression.contains(where: { $0.text == carrierName })
        else { return nil }
        return .init(
            alphaExpression: alphaExpression,
            rgbExpressionRanges: rgbRanges
        )
    }

    private static func generatedFilterSamples(
        fragment: Unit,
        main: Unit.Function,
        carrierInitializer: ArraySlice<Token>,
        carrierSlot: Int,
        rgbExpressionRanges: [Range<Int>]
    ) -> SampleRoles? {
        let tokens = fragment.tokens
        let helperNames = Set(fragment.functions.map(\.name)).subtracting(["main"])
        let rootCalls = main.bodyRange.compactMap { index -> (String, Int)? in
            guard index + 1 < main.bodyRange.upperBound,
                  helperNames.contains(tokens[index].text),
                  tokens[index + 1].text == "(" else { return nil }
            return (tokens[index].text, index)
        }
        var helperFunctions: [String: Unit.Function] = [:]
        for (name, callIndex) in rootCalls {
            guard let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .safeReadOnlyHelperClosure(
                    rootName: name, fragment: fragment
                ) else { return nil }
            let readsTexture = closure.contains { function in
                function.bodyRange.contains(where: {
                    ["texSample2D", "texture2D"].contains(tokens[$0].text)
                })
            }
            if readsTexture {
                guard let root = closure.first(where: { $0.name == name }),
                      ["vec3", "float3"].contains(root.returnType),
                      rgbExpressionRanges.contains(where: { $0.contains(callIndex) })
                else { return nil }
            }
            for function in closure { helperFunctions[function.name] = function }
        }

        let analyzedFunctions = [main] + Array(helperFunctions.values)
        guard !analyzedFunctions.contains(where: { function in
            function.bodyRange.contains(where: { index in
                guard index + 1 < function.bodyRange.upperBound,
                      tokens[index + 1].text == "(" else { return false }
                let value = tokens[index].text
                return value == "texelFetch" || value.hasPrefix("image")
            })
        }) else { return nil }

        var counts: [Int: Int] = [:]
        var generatedSlots = Set<Int>()
        var redSlots = Set<Int>()
        var greenSlots = Set<Int>()
        var blueSlots = Set<Int>()
        var alphaSlots = Set<Int>()
        var generatedCounts: [Int: Int] = [:]
        var redCounts: [Int: Int] = [:]
        var greenCounts: [Int: Int] = [:]
        var blueCounts: [Int: Int] = [:]
        var alphaCounts: [Int: Int] = [:]
        var sawCarrierInitializer = false

        for function in analyzedFunctions {
            let calls = textureSampleCalls(in: function.bodyRange, tokens: tokens)
            for call in calls {
                counts[call.slot, default: 0] += 1
                if function.name == "main",
                   call.range == carrierInitializer.startIndex..<carrierInitializer.endIndex {
                    guard call.slot == carrierSlot,
                          !sawCarrierInitializer else { return nil }
                    sawCarrierInitializer = true
                    continue
                }
                guard call.slot != carrierSlot else { return nil }
                let component = sampleComponent(after: call.range, tokens: tokens)
                switch component {
                case "rgb", "xyz":
                    if function.name == "main",
                       !rgbExpressionRanges.contains(where: {
                           $0.contains(call.range.lowerBound)
                       }) { return nil }
                    generatedSlots.insert(call.slot)
                    generatedCounts[call.slot, default: 0] += 1
                case "r", "x":
                    redSlots.insert(call.slot)
                    redCounts[call.slot, default: 0] += 1
                case "g", "y":
                    greenSlots.insert(call.slot)
                    greenCounts[call.slot, default: 0] += 1
                case "b", "z":
                    blueSlots.insert(call.slot)
                    blueCounts[call.slot, default: 0] += 1
                case "a", "w":
                    alphaSlots.insert(call.slot)
                    alphaCounts[call.slot, default: 0] += 1
                default:
                    return nil
                }
            }
        }
        guard sawCarrierInitializer, counts[carrierSlot] == 1 else { return nil }
        return .init(
            generatedSlots: generatedSlots,
            scalarRedSlots: redSlots,
            scalarGreenSlots: greenSlots,
            scalarBlueSlots: blueSlots,
            scalarAlphaSlots: alphaSlots,
            counts: counts,
            generatedCounts: generatedCounts,
            scalarRedCounts: redCounts,
            scalarGreenCounts: greenCounts,
            scalarBlueCounts: blueCounts,
            scalarAlphaCounts: alphaCounts
        )
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
            let value = tokens[index].text
            if ["(", "["].contains(value) {
                stack.append(value)
            } else if let expected = closing[value] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if value == ";", stack.isEmpty {
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
        for index in body
        where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < body.upperBound,
                  tokens[index + 1].text == "(",
                  let close = matchingDelimiter(
                      opening: index + 1,
                      tokens: tokens,
                      boundary: body.upperBound
                  ),
                  let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(tokens[index...close]) else { return [] }
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

    private static func identifier(_ expression: ArraySlice<Token>) -> String? {
        expression.count == 1 && expression.first?.kind == .identifier
            ? expression.first?.text : nil
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
                guard depth >= 0 else { return nil }
            }
        }
        return nil
    }
}
