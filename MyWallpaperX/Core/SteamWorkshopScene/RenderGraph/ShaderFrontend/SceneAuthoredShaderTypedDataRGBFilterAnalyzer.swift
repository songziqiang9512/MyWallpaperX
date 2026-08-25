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
        analyzeDirectCarrier(fragment) ?? analyzeMaskedSnapshotCarrier(fragment)
    }

    private static func analyzeDirectCarrier(_ fragment: Unit) -> Fact? {
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

    /// The source snapshot and the mutable carrier have identical alpha. An
    /// RGB-only mutation followed by a scalar `mix` between those two values
    /// therefore preserves that alpha even when the final color is saturated.
    private static func analyzeMaskedSnapshotCarrier(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              fragment.functions.allSatisfy({ !["mix", "lerp", "saturate"].contains($0.name) }),
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
              outputExpression.endIndex + 1 == main.bodyRange.upperBound - 1,
              let carrier = saturatedIdentifier(outputExpression),
              !main.bodyRange.contains(where: {
                  ["discard", "gl_FragDepth"].contains(tokens[$0].text)
              })
        else { return nil }

        let carrierDefinitions = vectorDefinitions(
            carrier,
            before: output,
            body: main.bodyRange,
            tokens: tokens
        )
        guard carrierDefinitions.count == 1,
              let carrierDefinition = carrierDefinitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  carrierDefinition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let carrierInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: carrierDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              carrierInitializer.count == 1,
              let source = carrierInitializer.first,
              source.kind == .identifier
        else { return nil }
        let sourceName = source.text

        let sourceDefinitions = vectorDefinitions(
            sourceName,
            before: carrierDefinition,
            body: main.bodyRange,
            tokens: tokens
        )
        guard sourceDefinitions.count == 1,
              let sourceDefinition = sourceDefinitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  sourceDefinition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let sourceInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: sourceDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(sourceInitializer),
              let calls = sampleCalls(tokens: tokens),
              calls.allSatisfy({
                  main.bodyRange.contains($0.index) && $0.index < output
              })
        else { return nil }

        let sourceCalls = calls.filter { sourceInitializer.indices.contains($0.index) }
        guard sourceCalls.count == 1,
              sourceCalls[0].slot == sourceSlot,
              sourceCalls[0].projection == .fullVector,
              calls.filter({ $0.slot == sourceSlot }).count == 1
        else { return nil }

        let wholeCarrierAssignments = main.bodyRange.filter { index in
            index != carrierDefinition && index + 1 < output
                && tokens[index].text == carrier
                && tokens[index + 1].text == "="
        }
        guard wholeCarrierAssignments.count <= 1 else { return nil }
        let mixAssignment = wholeCarrierAssignments.first
        var carrierMixUse: Int?
        var sourceMixUse: Int?
        if let mixAssignment {
            guard carrierDefinition < mixAssignment,
                  SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                      mixAssignment,
                      tokens: tokens,
                      body: main.bodyRange
                  ),
                  let mixExpression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(
                        after: mixAssignment,
                        in: tokens,
                        body: main.bodyRange
                    ),
                  let mixArguments = callArguments(
                      Array(mixExpression),
                      names: ["mix", "lerp"]
                  ),
                  mixArguments.count == 3,
                  Set(mixArguments.prefix(2).compactMap(singleIdentifier))
                    == Set([sourceName, carrier]),
                  mixArguments.prefix(2).allSatisfy({
                      singleIdentifier($0) != nil
                  }),
                  scalarWeight(
                      mixArguments[2],
                      before: mixAssignment,
                      tokens: tokens
                  ),
                  let carrierUse = mixExpression.indices.first(where: {
                      tokens[$0].text == carrier
                  }),
                  let sourceUse = mixExpression.indices.first(where: {
                      tokens[$0].text == sourceName
                  })
            else { return nil }
            carrierMixUse = carrierUse
            sourceMixUse = sourceUse
        }
        let outputUse = outputExpression.startIndex + 2
        var rgbWriteCount = 0
        for index in main.bodyRange where tokens[index].text == carrier {
            if index == carrierDefinition || index == mixAssignment
                || index == outputUse || index == carrierMixUse {
                continue
            }
            guard index + 2 < output,
                  tokens[index + 1].text == ".",
                  ["rgb", "xyz"].contains(tokens[index + 2].text)
            else { return nil }
            if index + 3 < output,
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text) {
                guard tokens[index + 3].text == "=",
                      SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                          index,
                          tokens: tokens,
                          body: main.bodyRange
                      ) else { return nil }
                rgbWriteCount += 1
            }
        }
        guard rgbWriteCount == 1 else { return nil }
        for index in main.bodyRange where tokens[index].text == sourceName {
            guard index == sourceDefinition
                    || index == carrierInitializer.startIndex
                    || index == sourceMixUse else { return nil }
        }

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
        let counts = Array(fullVector.values) + Array(red.values) + Array(redGreen.values)
        let auxiliarySlots = Set(fullVector.keys).union(red.keys).union(redGreen.keys)
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

    private static func saturatedIdentifier(
        _ expression: ArraySlice<Token>
    ) -> String? {
        let values = Array(expression)
        guard values.count == 4,
              values[0].text == "saturate",
              values[1].text == "(",
              values[2].kind == .identifier,
              values[3].text == ")" else { return nil }
        return values[2].text
    }

    private static func vectorDefinitions(
        _ name: String,
        before boundary: Int,
        body: Range<Int>,
        tokens: [Token]
    ) -> [Int] {
        body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
    }

    private static func callArguments(
        _ values: [Token],
        names: Set<String>
    ) -> [[Token]]? {
        guard values.count >= 3,
              names.contains(values[0].text),
              values[1].text == "(",
              values.last?.text == ")" else { return nil }
        var result: [[Token]] = []
        var current: [Token] = []
        var depth = 0
        for token in values.dropFirst(2).dropLast() {
            switch token.text {
            case "(", "[":
                depth += 1
                current.append(token)
            case ")", "]":
                depth -= 1
                guard depth >= 0 else { return nil }
                current.append(token)
            case "," where depth == 0:
                guard !current.isEmpty else { return nil }
                result.append(current)
                current = []
            default:
                current.append(token)
            }
        }
        guard depth == 0, !current.isEmpty else { return nil }
        result.append(current)
        return result
    }

    private static func singleIdentifier(_ values: [Token]) -> String? {
        guard values.count == 1, values[0].kind == .identifier else { return nil }
        return values[0].text
    }

    private static func scalarWeight(
        _ values: [Token],
        before boundary: Int,
        tokens: [Token]
    ) -> Bool {
        guard values.count == 1 else { return false }
        if values[0].kind == .number {
            let raw = values[0].text.trimmingCharacters(
                in: CharacterSet(charactersIn: "fFuU")
            )
            return Double(raw).map(\.isFinite) == true
        }
        guard values[0].kind == .identifier else { return false }
        let name = values[0].text
        let declarations = tokens.indices.filter { index in
            index > 0 && index < boundary
                && tokens[index].text == name
                && tokens[index - 1].text == "float"
                && index + 1 < tokens.count
                && tokens[index + 1].text != "["
        }
        return declarations.count == 1
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
