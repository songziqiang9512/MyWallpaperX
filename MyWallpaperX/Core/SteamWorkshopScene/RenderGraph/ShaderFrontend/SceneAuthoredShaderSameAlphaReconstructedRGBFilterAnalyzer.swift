import Foundation

nonisolated enum SceneAuthoredShaderSameAlphaReconstructedRGBSampleProjection:
    String, Equatable, Hashable, Sendable
{
    case fullVector
    case red
    case green
    case blue
    case alpha
    case redGreen
    case rgbPermutation
}

/// Source proof for a post-process that reconstructs one straight RGB carrier
/// from multiple samples of the same color slot, keeps the snapshot alpha, and
/// consumes every other sampled slot only as typed data. The proof is entirely
/// structural and carries exact sample projections into compiler revalidation.
nonisolated struct SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact:
    Equatable, Sendable
{
    typealias Projection =
        SceneAuthoredShaderSameAlphaReconstructedRGBSampleProjection

    let sourceSlot: Int
    let sourceSampleCallCounts: [Projection: Int]
    let dataSampleCallCounts: [Int: [Projection: Int]]

    var auxiliarySlots: Set<Int> { Set(dataSampleCallCounts.keys) }

    var totalSampleCallCount: Int {
        sourceSampleCallCounts.values.reduce(0, +)
            + dataSampleCallCounts.values.flatMap { $0.values }.reduce(0, +)
    }
}

/// Proves only the shared same-alpha reconstruction contract. It does not
/// inspect shader/effect paths, sample IDs, layer IDs, hashes, or visual names.
nonisolated enum SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer {
    typealias Fact = SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact
    private typealias Projection =
        SceneAuthoredShaderSameAlphaReconstructedRGBSampleProjection
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct SampleCall {
        let index: Int
        let close: Int
        let slot: Int
        let projection: Projection
    }

    private struct Assignment {
        let member: String?
        let operation: String
        let expression: ArraySlice<Token>
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
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              !statements.isEmpty,
              mainHasNoControlFlow(main, tokens: fragment.tokens),
              Set(fragment.functions.map(\.name))
                .isDisjoint(with: ["mix", "lerp"]),
              SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .writesOnlyLocalState(
                    main,
                    tokens: fragment.tokens,
                    allowingExternalWrites: ["gl_FragColor"]
                ),
              mainCallGraphIsReadOnly(fragment: fragment, main: main)
        else { return nil }

        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              statements.last?.contains(output) == true,
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
              let terminal = callArguments(
                  outputExpression,
                  names: ["mix", "lerp"],
                  count: 3
              ),
              let snapshot = identifier(terminal[0]),
              let carrier = identifier(terminal[1]),
              snapshot != carrier,
              terminal[2].allSatisfy({
                  $0.text != snapshot
                      && $0.text != carrier
                      && !["texSample2D", "texture2D"].contains($0.text)
              })
        else { return nil }

        guard let snapshotDefinition = uniqueVectorDefinition(
                  snapshot,
                  before: output,
                  statements: statements,
                  tokens: tokens
              ),
              let snapshotInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: snapshotDefinition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(snapshotInitializer),
              samplerType(slot: sourceSlot, fragment: fragment) == "sampler2D",
              let carrierDeclaration = uniqueUninitializedVectorDeclaration(
                  carrier,
                  before: output,
                  statements: statements,
                  tokens: tokens
              ),
              let calls = sampleCalls(tokens: tokens),
              calls.allSatisfy({
                  main.bodyRange.contains($0.index) && $0.index < output
              }),
              let snapshotCall = calls.first(where: {
                  snapshotInitializer.indices.contains($0.index)
              }),
              snapshotCall.slot == sourceSlot,
              snapshotCall.projection == .fullVector
        else { return nil }

        var initialized = Set<String>()
        var sourceCallIndices: Set<Int> = [snapshotCall.index]
        var rgbMutationCount = 0
        var copiedSnapshotAlpha = false
        guard let declarationStatement = statements.firstIndex(where: {
                  $0.contains(carrierDeclaration)
              }),
              let outputStatement = statements.firstIndex(where: {
                  $0.contains(output)
              }),
              declarationStatement < outputStatement else { return nil }

        for statement in statements[(declarationStatement + 1)..<outputStatement] {
            let occurrences = statement.filter { tokens[$0].text == carrier }
            if occurrences.isEmpty { continue }
            guard !hasIncrement(
                      carrier,
                      in: statement,
                      tokens: tokens
                  ),
                  let assignment = assignment(
                      carrier,
                      in: statement,
                      tokens: tokens
                  ) else {
                // Reads are safe only after every carrier lane has a value.
                guard initialized == Set(["x", "y", "z", "w"]) else {
                    return nil
                }
                continue
            }
            guard assignment.operation == "=",
                  let member = assignment.member,
                  let laneSequence = normalizedLaneSequence(member),
                  !laneSequence.isEmpty else { return nil }
            let lanes = Set(laneSequence)

            if initialized != Set(["x", "y", "z", "w"]) {
                guard initialized.isDisjoint(with: lanes) else { return nil }
                if let copied = projectedIdentifier(assignment.expression),
                   copied.name == snapshot,
                   copied.lanes == laneSequence {
                    initialized.formUnion(lanes)
                    if lanes.contains("w") { copiedSnapshotAlpha = true }
                    continue
                }
                guard lanes.count == 1,
                      lanes.first != "w",
                      let call = directProjectedSample(
                          assignment.expression,
                          calls: calls,
                          tokens: tokens
                      ),
                      call.slot == sourceSlot,
                      normalizedLanes(call.projection) == lanes else {
                    return nil
                }
                sourceCallIndices.insert(call.index)
                initialized.formUnion(lanes)
                continue
            }

            guard lanes.isSubset(of: ["x", "y", "z"]) else { return nil }
            rgbMutationCount += 1
        }

        guard initialized == Set(["x", "y", "z", "w"]),
              copiedSnapshotAlpha,
              rgbMutationCount > 0,
              snapshotIsReadOnly(
                  snapshot,
                  definition: snapshotDefinition,
                  body: main.bodyRange,
                  tokens: tokens
              ),
              carrierHasNoAlphaWriteAfterInitialization(
                  carrier,
                  from: statements[declarationStatement + 1].lowerBound,
                  to: output,
                  initializedBy: sourceCallIndices,
                  tokens: tokens
              ) else { return nil }

        let sourceCalls = calls.filter { $0.slot == sourceSlot }
        guard Set(sourceCalls.map(\.index)) == sourceCallIndices,
              sourceCalls.count >= 2,
              sourceCalls.count <= 16 else { return nil }

        var sourceCounts: [Projection: Int] = [:]
        var dataCounts: [Int: [Projection: Int]] = [:]
        for call in calls {
            if call.slot == sourceSlot {
                sourceCounts[call.projection, default: 0] += 1
                continue
            }
            guard samplerType(slot: call.slot, fragment: fragment) == "sampler2D",
                  call.projection != .fullVector,
                  call.projection != .alpha else { return nil }
            dataCounts[call.slot, default: [:]][call.projection, default: 0] += 1
        }
        let counts = Array(sourceCounts.values)
            + dataCounts.values.flatMap { $0.values }
        guard !dataCounts.isEmpty,
              counts.allSatisfy({ (1 ... 16).contains($0) }),
              counts.reduce(0, +) <= 32,
              sourceCounts[.fullVector] == 1 else { return nil }
        return .init(
            sourceSlot: sourceSlot,
            sourceSampleCallCounts: sourceCounts,
            dataSampleCallCounts: dataCounts
        )
    }

    private static func mainHasNoControlFlow(
        _ main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue", "gl_FragDepth", "?",
        ]
        return !main.bodyRange.contains(where: {
            forbidden.contains(tokens[$0].text)
        })
    }

    private static func mainCallGraphIsReadOnly(
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let builtins: Set<String> = [
            "texSample2D", "texture2D", "bool", "int", "uint", "float",
            "double", "bvec2", "bvec3", "bvec4", "ivec2", "ivec3",
            "ivec4", "uvec2", "uvec3", "uvec4", "vec2", "vec3",
            "vec4", "float2", "float3", "float4", "mat2", "mat3",
            "mat4", "CAST2", "CAST3", "CAST4", "abs", "clamp", "cos",
            "dot", "exp", "floor", "frac", "fract", "length", "max",
            "min", "mix", "lerp", "pow", "saturate", "sign", "sin",
            "smoothstep", "sqrt", "step",
        ]
        let defined = Set(fragment.functions.map(\.name)).subtracting(["main"])
        var checked = Set<String>()
        for index in main.bodyRange where index + 1 < main.bodyRange.upperBound
            && fragment.tokens[index].kind == .identifier
            && fragment.tokens[index + 1].text == "(" {
            let name = fragment.tokens[index].text
            if builtins.contains(name) { continue }
            guard defined.contains(name) else { return false }
            if !checked.insert(name).inserted { continue }
            guard let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                    .safeReadOnlyHelperClosure(
                        rootName: name,
                        fragment: fragment
                    ),
                  closure.allSatisfy({ function in
                      !function.bodyRange.contains(where: {
                          ["texSample2D", "texture2D"]
                            .contains(fragment.tokens[$0].text)
                      })
                  }) else { return false }
        }
        return true
    }

    private static func uniqueVectorDefinition(
        _ name: String,
        before boundary: Int,
        statements: [Range<Int>],
        tokens: [Token]
    ) -> Int? {
        let matches = statements.compactMap { statement -> Int? in
            guard statement.lowerBound < boundary,
                  statement.count >= 4,
                  ["vec4", "float4"].contains(tokens[statement.lowerBound].text),
                  tokens[statement.lowerBound + 1].text == name,
                  tokens[statement.lowerBound + 2].text == "=" else { return nil }
            return statement.lowerBound + 1
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func uniqueUninitializedVectorDeclaration(
        _ name: String,
        before boundary: Int,
        statements: [Range<Int>],
        tokens: [Token]
    ) -> Int? {
        let matches = statements.compactMap { statement -> Int? in
            guard statement.lowerBound < boundary,
                  statement.count == 2,
                  ["vec4", "float4"].contains(tokens[statement.lowerBound].text),
                  tokens[statement.lowerBound + 1].text == name else { return nil }
            return statement.lowerBound + 1
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func assignment(
        _ name: String,
        in statement: Range<Int>,
        tokens: [Token]
    ) -> Assignment? {
        guard tokens[statement.lowerBound].text == name else { return nil }
        var cursor = statement.lowerBound + 1
        var member: String?
        if cursor + 1 < statement.upperBound, tokens[cursor].text == "." {
            member = tokens[cursor + 1].text
            cursor += 2
        }
        guard cursor < statement.upperBound,
              ["=", "+=", "-=", "*=", "/="].contains(tokens[cursor].text),
              cursor + 1 < statement.upperBound else { return nil }
        return .init(
            member: member,
            operation: tokens[cursor].text,
            expression: tokens[(cursor + 1)..<statement.upperBound]
        )
    }

    private static func projectedIdentifier(
        _ expression: ArraySlice<Token>
    ) -> (name: String, lanes: [String])? {
        guard expression.count == 3,
              expression[expression.startIndex].kind == .identifier,
              expression[expression.startIndex + 1].text == ".",
              let lanes = normalizedLaneSequence(
                  expression[expression.startIndex + 2].text
              )
        else { return nil }
        return (expression[expression.startIndex].text, lanes)
    }

    private static func directProjectedSample(
        _ expression: ArraySlice<Token>,
        calls: [SampleCall],
        tokens: [Token]
    ) -> SampleCall? {
        let matches = calls.filter { expression.indices.contains($0.index) }
        guard matches.count == 1, let call = matches.first,
              expression.startIndex == call.index,
              expression.endIndex == call.close + 3,
              tokens[call.close + 1].text == "." else { return nil }
        return call
    }

    private static func snapshotIsReadOnly(
        _ name: String,
        definition: Int,
        body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        for index in body where tokens[index].text == name && index != definition {
            if hasWriteOperator(after: index, boundary: body.upperBound, tokens: tokens)
                || (index > body.lowerBound
                    && ["++", "--"].contains(tokens[index - 1].text)) {
                return false
            }
        }
        return true
    }

    private static func carrierHasNoAlphaWriteAfterInitialization(
        _ name: String,
        from lowerBound: Int,
        to upperBound: Int,
        initializedBy sourceCallIndices: Set<Int>,
        tokens: [Token]
    ) -> Bool {
        // Initialization structure was proved statement-by-statement above.
        // This second pass closes component aliases and prefix/suffix writes.
        for index in lowerBound..<upperBound where tokens[index].text == name {
            if index > lowerBound,
               ["++", "--"].contains(tokens[index - 1].text) { return false }
            guard index + 2 < upperBound, tokens[index + 1].text == "." else {
                continue
            }
            guard let lanes = normalizedLanes(tokens[index + 2].text) else {
                return false
            }
            if hasWriteOperator(after: index, boundary: upperBound, tokens: tokens),
               lanes.contains("w") {
                // The sole snapshot-alpha initialization is allowed; any
                // later alpha write would break equal-alpha terminal mixing.
                let statementStart = (lowerBound...index).reversed().first(where: {
                    $0 == lowerBound || tokens[$0 - 1].text == ";"
                }) ?? index
                let sourceCalls = sourceCallIndices.filter {
                    (statementStart...index).contains($0)
                }
                if sourceCalls.isEmpty,
                   !(index + 5 < upperBound
                     && tokens[index + 3].text == "="
                     && tokens[index + 4].kind == .identifier
                     && tokens[index + 5].text == ".") {
                    return false
                }
            }
        }
        return true
    }

    private static func hasIncrement(
        _ name: String,
        in statement: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        statement.contains { index in
            tokens[index].text == name
                && ((index > statement.lowerBound
                    && ["++", "--"].contains(tokens[index - 1].text))
                    || (index + 1 < statement.upperBound
                        && ["++", "--"].contains(tokens[index + 1].text))
                    || (index + 3 < statement.upperBound
                        && ["++", "--"].contains(tokens[index + 3].text)))
        }
    }

    private static func hasWriteOperator(
        after index: Int,
        boundary: Int,
        tokens: [Token]
    ) -> Bool {
        var cursor = index + 1
        if cursor + 1 < boundary, tokens[cursor].text == "." { cursor += 2 }
        return cursor < boundary
            && ["=", "+=", "-=", "*=", "/="].contains(tokens[cursor].text)
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        var result: [SampleCall] = []
        for index in tokens.indices where
            ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text),
                  tokens[index + 3].text == ",",
                  let close = matchingClose(opening: index + 1, tokens: tokens),
                  let projection = projection(after: close, tokens: tokens)
            else { return nil }
            result.append(.init(
                index: index,
                close: close,
                slot: slot,
                projection: projection
            ))
        }
        return result
    }

    private static func projection(after close: Int, tokens: [Token]) -> Projection? {
        guard close + 2 < tokens.count, tokens[close + 1].text == "." else {
            return .fullVector
        }
        switch normalizedProjection(tokens[close + 2].text) {
        case "x": return .red
        case "y": return .green
        case "z": return .blue
        case "w": return .alpha
        case "xy": return .redGreen
        case let value where value.count == 3
            && Set(value).isSubset(of: Set("xyz")):
            return .rgbPermutation
        default: return nil
        }
    }

    private static func normalizedLanes(_ projection: Projection) -> Set<String> {
        switch projection {
        case .fullVector: ["x", "y", "z", "w"]
        case .red: ["x"]
        case .green: ["y"]
        case .blue: ["z"]
        case .alpha: ["w"]
        case .redGreen: ["x", "y"]
        case .rgbPermutation: ["x", "y", "z"]
        }
    }

    private static func normalizedLanes(_ raw: String) -> Set<String>? {
        normalizedLaneSequence(raw).map(Set.init)
    }

    private static func normalizedLaneSequence(_ raw: String) -> [String]? {
        let normalized = normalizedProjection(raw)
        guard !normalized.isEmpty,
              normalized.allSatisfy({ "xyzw".contains($0) }),
              Set(normalized).count == normalized.count else { return nil }
        return normalized.map(String.init)
    }

    private static func normalizedProjection(_ raw: String) -> String {
        String(raw.map { character in
            switch character {
            case "r": "x"
            case "g": "y"
            case "b": "z"
            case "a": "w"
            default: character
            }
        })
    }

    private static func callArguments(
        _ expression: ArraySlice<Token>,
        names: Set<String>,
        count: Int
    ) -> [ArraySlice<Token>]? {
        guard expression.count >= 3,
              names.contains(expression.first?.text ?? ""),
              expression[expression.startIndex + 1].text == "(",
              expression.last?.text == ")" else { return nil }
        var result: [ArraySlice<Token>] = []
        var start = expression.startIndex + 2
        var depth = 0
        for index in start..<expression.index(before: expression.endIndex) {
            switch expression[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(expression[start..<index])
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        let end = expression.index(before: expression.endIndex)
        guard depth == 0, start < end else { return nil }
        result.append(expression[start..<end])
        return result.count == count ? result : nil
    }

    private static func identifier(_ expression: ArraySlice<Token>) -> String? {
        expression.count == 1 && expression.first?.kind == .identifier
            ? expression.first?.text : nil
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        fragment.declarations.first(where: {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)"
        })?.typeName
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func matchingClose(opening: Int, tokens: [Token]) -> Int? {
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
}
