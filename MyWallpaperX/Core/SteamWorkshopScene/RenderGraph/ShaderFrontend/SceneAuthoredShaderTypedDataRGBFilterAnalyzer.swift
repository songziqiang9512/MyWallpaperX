import Foundation

/// A source-derived straight-RGB filter with one preserved-alpha color carrier
/// and only typed data auxiliaries. The fact records every auxiliary sampling
/// projection so compiler lowering can independently conserve the boundary.
nonisolated struct SceneAuthoredShaderTypedDataRGBFilterFact: Equatable, Sendable {
    let sourceSlot: Int
    let fullVectorDataSampleCallCounts: [Int: Int]
    let redDataSampleCallCounts: [Int: Int]
    let redGreenDataSampleCallCounts: [Int: Int]

    var auxiliarySlots: Set<Int> {
        Set(fullVectorDataSampleCallCounts.keys)
            .union(redDataSampleCallCounts.keys)
            .union(redGreenDataSampleCallCounts.keys)
    }

    var totalSampleCallCount: Int {
        1 + fullVectorDataSampleCallCounts.values.reduce(0, +)
            + redDataSampleCallCounts.values.reduce(0, +)
            + redGreenDataSampleCallCounts.values.reduce(0, +)
    }
}

/// Proves only ownership of the color carrier and data projections. It does
/// not inspect effect, material, path, sample, layer, hash, or visual math.
nonisolated enum SceneAuthoredShaderTypedDataRGBFilterAnalyzer {
    typealias Fact = SceneAuthoredShaderTypedDataRGBFilterFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private enum Projection {
        case fullVector
        case red
        case redGreen
    }

    private struct SampleCall {
        let index: Int
        let close: Int
        let slot: Int
        let projection: Projection
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
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1,
              let output = outputs.first,
              main.bodyRange.contains(output),
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
              outputExpression.count == 1,
              outputExpression.first?.kind == .identifier,
              outputExpression.endIndex + 1 == main.bodyRange.upperBound - 1,
              !main.bodyRange.contains(where: {
                  ["discard", "gl_FragDepth"].contains(tokens[$0].text)
              })
        else { return nil }
        let carrier = outputExpression.first!.text

        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index + 1 < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer),
              let calls = sampleCalls(tokens: tokens),
              calls.allSatisfy({
                  main.bodyRange.contains($0.index) && $0.index < output
              })
        else { return nil }

        let sourceCalls = calls.filter { initializer.indices.contains($0.index) }
        guard sourceCalls.count == 1,
              sourceCalls[0].slot == sourceSlot,
              sourceCalls[0].projection == .fullVector,
              calls.filter({ $0.slot == sourceSlot }).count == 1,
              carrierUsesPreserveAlpha(
                  carrier,
                  definition: definition,
                  output: output,
                  outputExpression: outputExpression,
                  main: main,
                  tokens: tokens
              )
        else { return nil }

        var fullVector: [Int: Int] = [:]
        var red: [Int: Int] = [:]
        var redGreen: [Int: Int] = [:]
        for call in calls where call.index != sourceCalls[0].index {
            guard call.slot != sourceSlot else { return nil }
            switch call.projection {
            case .fullVector:
                guard isLocalVectorDataDeclaration(
                    call,
                    calls: calls,
                    before: output,
                    tokens: tokens,
                    body: main.bodyRange
                ) else { return nil }
                fullVector[call.slot, default: 0] += 1
            case .red:
                red[call.slot, default: 0] += 1
            case .redGreen:
                redGreen[call.slot, default: 0] += 1
            }
        }
        let counts = Array(fullVector.values)
            + Array(red.values)
            + Array(redGreen.values)
        let auxiliarySlots = Set(fullVector.keys)
            .union(red.keys)
            .union(redGreen.keys)
        guard !auxiliarySlots.isEmpty,
              Set(fullVector.keys).isDisjoint(with: red.keys),
              Set(fullVector.keys).isDisjoint(with: redGreen.keys),
              Set(red.keys).isDisjoint(with: redGreen.keys),
              counts.allSatisfy({ (1 ... 16).contains($0) }),
              1 + counts.reduce(0, +) <= 32 else { return nil }
        return .init(
            sourceSlot: sourceSlot,
            fullVectorDataSampleCallCounts: fullVector,
            redDataSampleCallCounts: red,
            redGreenDataSampleCallCounts: redGreen
        )
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        var result: [SampleCall] = []
        for index in tokens.indices where
            ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text),
                  tokens[index + 3].text == ",",
                  let close = matchingClose(
                      opening: index + 1,
                      tokens: tokens
                  ) else { return nil }
            let projection: Projection
            if close + 2 < tokens.count, tokens[close + 1].text == "." {
                switch tokens[close + 2].text {
                case "r", "x": projection = .red
                case "rg", "xy": projection = .redGreen
                default: return nil
                }
            } else {
                projection = .fullVector
            }
            result.append(.init(
                index: index,
                close: close,
                slot: slot,
                projection: projection
            ))
        }
        return result
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func matchingClose(
        opening: Int,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func isLocalVectorDataDeclaration(
        _ call: SampleCall,
        calls: [SampleCall],
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        var start = call.index
        while start > body.lowerBound + 1,
              ![";", "{", "}"].contains(tokens[start - 1].text) {
            start -= 1
        }
        guard start + 2 < call.index,
              ["vec4", "float4"].contains(tokens[start].text),
              tokens[start + 1].kind == .identifier,
              tokens[start + 2].text == "=",
              let semicolon = (call.close..<output).first(where: {
                  tokens[$0].text == ";"
              }),
              calls.filter({ (start..<semicolon).contains($0.index) }).count == 1
        else { return false }
        return SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
            start + 1,
            tokens: tokens,
            body: body
        )
    }

    private static func carrierUsesPreserveAlpha(
        _ carrier: String,
        definition: Int,
        output: Int,
        outputExpression: ArraySlice<Token>,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let outputUse = outputExpression.startIndex
        var rgbWriteCount = 0
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in (definition + 1)..<output where tokens[index].text == carrier {
            if index == outputUse { continue }
            guard index + 2 < output,
                  tokens[index + 1].text == ".",
                  ["rgb", "xyz", "a", "w"].contains(tokens[index + 2].text)
            else { return false }
            guard ["rgb", "xyz"].contains(tokens[index + 2].text) else {
                // This first owner cohort does not need carrier-alpha reads.
                // Rejecting every use also closes direct, increment and
                // authored out/inout alias mutation without guessing call ABI.
                return false
            }
            if (index > definition + 1
                    && ["++", "--"].contains(tokens[index - 1].text))
                || (index + 3 < output
                    && ["++", "--"].contains(tokens[index + 3].text)) {
                return false
            }
            guard index + 3 < output,
                  operators.contains(tokens[index + 3].text) else { continue }
            guard tokens[index + 3].text == "=",
                  SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                      index,
                      tokens: tokens,
                      body: main.bodyRange
                  ) else { return false }
            rgbWriteCount += 1
        }
        return rgbWriteCount == 1
    }
}
