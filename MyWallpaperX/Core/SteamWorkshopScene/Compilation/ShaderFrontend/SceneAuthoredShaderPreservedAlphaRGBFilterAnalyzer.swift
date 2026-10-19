import Foundation

/// Source proof for a straight-RGB filter that keeps one sampled alpha intact.
/// Color samples may feed RGB math while `.rg` samples and explicit-LOD scalar
/// `.r` samples remain typed data. The proof is structural and never inspects
/// effect, material, path, or sample IDs.
nonisolated struct SceneAuthoredShaderPreservedAlphaRGBFilterFact: Equatable, Sendable {
    let sourceSlot: Int
    let fullColorSampleCallCounts: [Int: Int]
    let rgbColorSampleCallCounts: [Int: Int]
    let dataSampleCallCounts: [Int: Int]
    let scalarDataSampleCallCounts: [Int: Int]

    var colorSampleCallCounts: [Int: Int] {
        fullColorSampleCallCounts.merging(
            rgbColorSampleCallCounts,
            uniquingKeysWith: +
        )
    }

    var sampledTextureSlots: Set<Int> {
        Set(colorSampleCallCounts.keys).union(dataSampleCallCounts.keys)
    }
}

nonisolated enum SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer {
    typealias Fact = SceneAuthoredShaderPreservedAlphaRGBFilterFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct SampleCall {
        let index: Int
        let close: Int
        let function: String
        let slot: Int
        let swizzle: String?
    }

    private enum DataProjection {
        case scalar
        case vector2
    }

    private static func parsedFragment(_ source: String) -> Unit? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: .fragment),
            stage: .fragment
        )
        return syntax.diagnostics.isEmpty ? syntax.unit : nil
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        parsedFragment(source).flatMap { analyze($0) }
    }

    static func analyzeAny(fragmentSource source: String) -> Fact? {
        parsedFragment(source).flatMap { analyzeAny($0) }
    }

    static func analyzeAny(_ fragment: Unit) -> Fact? {
        analyze(fragment)
            ?? SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer.analyze(
                fragment
            )
            ?? analyzeRGBDifferenceEnhancement(fragment)
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
              outputExpression.first?.kind == .identifier
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
              samplerType(slot: sourceSlot, fragment: fragment) == "sampler2D",
              let calls = sampleCalls(tokens: tokens),
              calls.allSatisfy({ main.bodyRange.contains($0.index) }),
              calls.allSatisfy({ $0.index < output }),
              let sourceCall = calls.first(where: {
                  initializer.indices.contains($0.index)
              }),
              sourceCall.slot == sourceSlot,
              sourceCall.swizzle == nil,
              mainHelperCallsAreReadOnly(fragment: fragment, main: main)
        else { return nil }

        let fullDeclarations = calls.compactMap { call -> (String, SampleCall)? in
            guard call.index >= 3,
                  ["vec4", "float4"].contains(tokens[call.index - 3].text),
                  tokens[call.index - 2].kind == .identifier,
                  tokens[call.index - 1].text == "=",
                  call.swizzle == nil,
                  call.close + 1 < tokens.count,
                  tokens[call.close + 1].text == ";" else { return nil }
            return (tokens[call.index - 2].text, call)
        }
        guard fullDeclarations.contains(where: {
            $0.0 == carrier && $0.1.index == sourceCall.index
        }) else { return nil }
        let bases = fullDeclarations.filter { $0.0 != carrier }
        guard bases.count <= 1,
              bases.allSatisfy({ $0.1.slot != sourceSlot }) else { return nil }

        var fullColorCounts: [Int: Int] = [sourceSlot: 1]
        var rgbColorCounts: [Int: Int] = [:]
        var dataCounts: [Int: Int] = [:]
        var scalarDataCounts: [Int: Int] = [:]
        for call in calls where call.index != sourceCall.index {
            if let base = bases.first, call.index == base.1.index {
                fullColorCounts[call.slot, default: 0] += 1
                continue
            }
            if let projection = dataDeclaration(call, tokens: tokens) {
                guard call.slot != sourceSlot,
                      !bases.contains(where: { $0.1.slot == call.slot }) else {
                    return nil
                }
                dataCounts[call.slot, default: 0] += 1
                if projection == .scalar {
                    scalarDataCounts[call.slot, default: 0] += 1
                }
                continue
            }
            if rgbAccumulation(
                call,
                carrier: carrier,
                body: main.bodyRange,
                tokens: tokens
            ) {
                guard call.slot == sourceSlot else { return nil }
                rgbColorCounts[call.slot, default: 0] += 1
                continue
            }
            return nil
        }
        let colorCounts = fullColorCounts.merging(
            rgbColorCounts,
            uniquingKeysWith: +
        )
        guard !dataCounts.isEmpty,
              colorCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              dataCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              colorCounts.values.reduce(0, +) + dataCounts.values.reduce(0, +) <= 32,
              Set(colorCounts.keys).isDisjoint(with: dataCounts.keys)
        else { return nil }

        let wholeAssignments = main.bodyRange.filter { index in
            index != definition
                && index + 1 < output
                && tokens[index].text == carrier
                && tokens[index + 1].text == "="
        }
        let blendAssignment: Int?
        if let base = bases.first {
            guard wholeAssignments.count == 1,
                  let assignment = wholeAssignments.first,
                  terminalRGBBlend(
                      at: assignment,
                      carrier: carrier,
                      base: base.0,
                      fragment: fragment,
                      main: main
                  ),
                  main.bodyRange.filter({ tokens[$0].text == base.0 }).count == 2
            else { return nil }
            blendAssignment = assignment
        } else {
            guard wholeAssignments.isEmpty else { return nil }
            blendAssignment = nil
        }
        guard carrierUsesAreAlphaPreserving(
            carrier: carrier,
            definition: definition,
            blendAssignment: blendAssignment,
            output: output,
            main: main,
            tokens: tokens
        ) else { return nil }

        return .init(
            sourceSlot: sourceSlot,
            fullColorSampleCallCounts: fullColorCounts,
            rgbColorSampleCallCounts: rgbColorCounts,
            dataSampleCallCounts: dataCounts,
            scalarDataSampleCallCounts: scalarDataCounts
        )
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        var result: [SampleCall] = []
        for index in tokens.indices where
            ["texSample2D", "texture2D", "texSample2DLod", "textureLod"]
                .contains(tokens[index].text) {
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = SceneShaderSourceTextFacts.textureSlot(tokens[index + 2].text),
                  tokens[index + 3].text == ",",
                  let close = matchingDelimiter(
                      at: index + 1,
                      tokens: tokens
                  ) else { return nil }
            let swizzle: String?
            if close + 2 < tokens.count, tokens[close + 1].text == "." {
                swizzle = tokens[close + 2].text
            } else {
                swizzle = nil
            }
            result.append(.init(
                index: index,
                close: close,
                function: tokens[index].text,
                slot: slot,
                swizzle: swizzle
            ))
        }
        return result
    }

    private static func dataDeclaration(
        _ call: SampleCall,
        tokens: [Token]
    ) -> DataProjection? {
        guard call.index >= 3,
              tokens[call.index - 2].kind == .identifier,
              tokens[call.index - 1].text == "=",
              call.close + 3 < tokens.count,
              tokens[call.close + 3].text == ";" else { return nil }
        let type = tokens[call.index - 3].text
        if ["vec2", "float2"].contains(type),
           ["rg", "xy"].contains(call.swizzle ?? "") {
            return .vector2
        }
        if type == "float",
           ["texSample2DLod", "textureLod"].contains(call.function),
           ["r", "x"].contains(call.swizzle ?? "") {
            return .scalar
        }
        return nil
    }

    /// Any authored helper reached from `main` must remain a read-only value
    /// transform. This keeps the broad data-sample grammar from authorizing a
    /// hidden texture read, output write, mutable parameter, global mutation,
    /// or recursive call graph.
    private static func mainHelperCallsAreReadOnly(
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let helperNames = Set(fragment.functions.map(\.name)).subtracting(["main"])
        let called = Set(main.bodyRange.compactMap { index -> String? in
            guard index + 1 < main.bodyRange.upperBound,
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "(",
                  helperNames.contains(tokens[index].text) else { return nil }
            return tokens[index].text
        })
        return called.allSatisfy {
            SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .safeReadOnlyHelperClosure(
                    rootName: $0,
                    fragment: fragment
                ) != nil
        }
    }

    private static func rgbAccumulation(
        _ call: SampleCall,
        carrier: String,
        body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        guard ["rgb", "xyz"].contains(call.swizzle ?? ""),
              call.close + 3 < tokens.count,
              tokens[call.close + 3].text == ";" else { return false }
        var start = call.index
        while start > body.lowerBound + 1,
              ![";", "{", "}"].contains(tokens[start - 1].text) {
            start -= 1
        }
        return Array(tokens[start..<call.index]).map(\.text)
            == [carrier, ".", "rgb", "+="]
    }

    private static func terminalRGBBlend(
        at assignment: Int,
        carrier: String,
        base: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: assignment,
                    in: tokens,
                    body: main.bodyRange
                ),
              let constructor = call(
                  named: ["vec4", "float4"],
                  tokens: Array(expression)
              ),
              constructor.count == 2,
              member(constructor[1], name: carrier, members: ["a", "w"]),
              let blend = call(
                  named: ["ApplyBlending"],
                  tokens: constructor[0]
              ),
              blend.count == 4,
              numericMode(blend[0], defines: fragment.defines),
              Set([
                  memberName(blend[1]),
                  memberName(blend[2]),
              ].compactMap({ $0 })) == Set([base, carrier]),
              member(blend[1], name: memberName(blend[1]) ?? "", members: ["rgb", "xyz"]),
              member(blend[2], name: memberName(blend[2]) ?? "", members: ["rgb", "xyz"]),
              !blend[3].contains(where: {
                  ["texSample2D", "texture2D", "gl_FragColor"].contains($0.text)
              }),
              fragment.functions.filter({ $0.name == "ApplyBlending" }).count == 1,
              let helper = fragment.functions.first(where: {
                  $0.name == "ApplyBlending"
              }),
              ["vec3", "float3"].contains(helper.returnType),
              !fragment.tokens[helper.parameterRange].contains(where: {
                  ["out", "inout"].contains($0.text)
              }),
              !fragment.tokens[helper.bodyRange].contains(where: {
                  ["texSample2D", "texture2D", "gl_FragColor"].contains($0.text)
              }) else { return false }
        let laterCarrierWrites = (assignment + 1)..<main.bodyRange.upperBound
        return !laterCarrierWrites.contains { index in
            index + 1 < tokens.count
                && tokens[index].text == carrier
                && (tokens[index + 1].text == "="
                    || (tokens[index + 1].text == "."
                        && index + 3 < tokens.count
                        && ["=", "+=", "-=", "*=", "/="].contains(
                            tokens[index + 3].text
                        )))
        }
    }

    private static func carrierUsesAreAlphaPreserving(
        carrier: String,
        definition: Int,
        blendAssignment: Int?,
        output: Int,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let assignments: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in main.bodyRange where tokens[index].text == carrier {
            if index == definition || index == blendAssignment || index == output + 2 {
                continue
            }
            if index + 2 < tokens.count, tokens[index + 1].text == "." {
                let member = tokens[index + 2].text
                guard ["rgb", "xyz", "a", "w"].contains(member) else {
                    return false
                }
                if ["a", "w"].contains(member),
                   index + 3 < tokens.count,
                   assignments.contains(tokens[index + 3].text) {
                    return false
                }
                continue
            }
            if index >= 3,
               tokens[index - 1].text == "=",
               tokens[index - 2].kind == .identifier,
               ["vec4", "float4"].contains(tokens[index - 3].text),
               index + 1 < tokens.count,
               tokens[index + 1].text == ";" {
                let alias = tokens[index - 2].text
                guard main.bodyRange.filter({ tokens[$0].text == alias }).count == 1 else {
                    return false
                }
                continue
            }
            return false
        }
        return true
    }

    private static func call(named names: Set<String>, tokens: [Token]) -> [[Token]]? {
        guard tokens.count >= 3,
              names.contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              matchingDelimiter(at: 1, tokens: tokens) == tokens.count - 1 else {
            return nil
        }
        var arguments: [[Token]] = []
        var start = 2
        var depth = 0
        for index in 2..<(tokens.count - 1) {
            if ["(", "[", "{"].contains(tokens[index].text) { depth += 1 }
            if [")", "]", "}"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard index > start else { return nil }
                arguments.append(Array(tokens[start..<index]))
                start = index + 1
            }
        }
        guard start < tokens.count - 1 else { return nil }
        arguments.append(Array(tokens[start..<(tokens.count - 1)]))
        return arguments
    }

    private static func member(
        _ tokens: [Token],
        name: String,
        members: Set<String>
    ) -> Bool {
        tokens.count == 3
            && tokens[0].text == name
            && tokens[1].text == "."
            && members.contains(tokens[2].text)
    }

    private static func memberName(_ tokens: [Token]) -> String? {
        guard tokens.count == 3, tokens[1].text == ".",
              ["rgb", "xyz"].contains(tokens[2].text) else { return nil }
        return tokens[0].text
    }

    private static func numericMode(
        _ tokens: [Token],
        defines: [String: String]
    ) -> Bool {
        guard tokens.count == 1 else { return false }
        let raw = defines[tokens[0].text] ?? tokens[0].text
        return Int(raw).map({ (0 ... 31).contains($0) }) == true
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        fragment.declarations.first(where: {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)"
        })?.typeName
    }

    private static func matchingDelimiter(
        at index: Int,
        tokens: [Token]
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard tokens.indices.contains(index),
              let closing = pairs[tokens[index].text] else { return nil }
        var depth = 0
        for cursor in index..<tokens.count {
            if tokens[cursor].text == tokens[index].text { depth += 1 }
            if tokens[cursor].text == closing {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }
    // This is the two-color, alpha-preserving subcase of the same filter
    // contract. It consumes the already parsed unit and has no separate owner.
    private struct RGBDifferenceSample {
        let variable: String
        let slot: Int
        let coordinate: [String]
        let statement: Range<Int>
    }

    private static func analyzeRGBDifferenceEnhancement(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              fragment.functions.count == 1,
              let main = fragment.functions.first,
              main.name == "main",
              let statements = statements(in: main, tokens: fragment.tokens),
              !statements.isEmpty else { return nil }
        let tokens = fragment.tokens
        let body = (main.bodyRange.lowerBound + 1)..<(main.bodyRange.upperBound - 1)
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "break", "continue", "return", "?",
        ]
        guard !body.contains(where: { forbidden.contains(tokens[$0].text) }) else {
            return nil
        }

        let sampleStatements = statements.filter { statement in
            statement.contains(where: {
                ["texSample2D", "texture2D"].contains(tokens[$0].text)
            })
        }
        guard sampleStatements.count == 2 else { return nil }
        let samples = sampleStatements.compactMap {
            sample(in: $0, tokens: tokens)
        }
        guard samples.count == 2,
              Set(samples.map(\.variable)).count == 2,
              Set(samples.map(\.slot)).count == 2,
              samples.allSatisfy({
                  differenceSamplerType(slot: $0.slot, fragment: fragment) == "sampler2D"
              }) else { return nil }

        let outputStatements = statements.filter {
            $0.contains(where: { tokens[$0].text == "gl_FragColor" })
        }
        guard outputStatements.count == 1,
              let outputStatement = outputStatements.first,
              outputStatement == statements.last,
              texts(outputStatement, tokens: tokens).count == 3 else {
            return nil
        }
        let output = texts(outputStatement, tokens: tokens)
        guard output[0] == "gl_FragColor", output[1] == "=",
              let source = samples.first(where: { $0.variable == output[2] }),
              let reference = samples.first(where: {
                  $0.variable != source.variable
              }) else { return nil }

        guard let deltaStatement = statements.first(where: {
            matchesDifference(
                $0,
                source: source.variable,
                reference: reference.variable,
                tokens: tokens
            )
        }) else { return nil }
        let delta = tokens[deltaStatement.lowerBound + 1].text

        guard let enhancementStatement = statements.first(where: {
            matchesEnhancement(
                $0,
                source: source.variable,
                delta: delta,
                tokens: tokens
            )
        }) else { return nil }
        let enhancement = tokens[enhancementStatement.lowerBound + 1].text
        let amount = tokens[enhancementStatement.upperBound - 1].text
        guard scalarAmountIsProven(amount, fragment: fragment) else { return nil }

        guard let maskStatement = statements.first(where: {
            matchesUnitScalarDeclaration($0, tokens: tokens)
        }) else { return nil }
        let mask = tokens[maskStatement.lowerBound + 1].text

        guard let mixStatement = statements.first(where: {
            matchesMix(
                $0,
                source: source.variable,
                enhancement: enhancement,
                mask: mask,
                tokens: tokens
            )
        }) else { return nil }

        guard source.statement.lowerBound < deltaStatement.lowerBound,
              reference.statement.lowerBound < deltaStatement.lowerBound,
              deltaStatement.lowerBound < enhancementStatement.lowerBound,
              enhancementStatement.lowerBound < maskStatement.lowerBound,
              maskStatement.lowerBound < mixStatement.lowerBound,
              mixStatement.lowerBound < outputStatement.lowerBound else {
            return nil
        }

        var ownedStatements: Set<Range<Int>> = [
            source.statement,
            reference.statement,
            deltaStatement,
            enhancementStatement,
            maskStatement,
            mixStatement,
            outputStatement,
        ]
        let remaining = statements.filter { !ownedStatements.contains($0) }
        guard remaining.count <= 1 else { return nil }
        if let coordinateStatement = remaining.first {
            guard matchesCoordinateAlias(
                coordinateStatement,
                reference: reference,
                fragment: fragment
            ), coordinateStatement.lowerBound < reference.statement.lowerBound else {
                return nil
            }
            ownedStatements.insert(coordinateStatement)
        }
        guard ownedStatements.count == statements.count else { return nil }

        return .init(
            sourceSlot: source.slot,
            fullColorSampleCallCounts: [source.slot: 1, reference.slot: 1],
            rgbColorSampleCallCounts: [:],
            dataSampleCallCounts: [:],
            scalarDataSampleCallCounts: [:]
        )
    }

    private static func statements(
        in main: Unit.Function,
        tokens: [Token]
    ) -> [Range<Int>]? {
        let lower = main.bodyRange.lowerBound + 1
        let upper = main.bodyRange.upperBound - 1
        guard lower <= upper else { return nil }
        var result: [Range<Int>] = []
        var start = lower
        for index in lower..<upper {
            guard !["{", "}"].contains(tokens[index].text) else { return nil }
            guard tokens[index].text == ";" else { continue }
            guard start < index else { return nil }
            result.append(start..<index)
            start = index + 1
        }
        guard start == upper else { return nil }
        return result
    }

    private static func sample(
        in statement: Range<Int>,
        tokens: [Token]
    ) -> RGBDifferenceSample? {
        let values = texts(statement, tokens: tokens)
        guard values.count >= 9,
              ["vec4", "float4"].contains(values[0]),
              tokens[statement.lowerBound + 1].kind == .identifier,
              values[2] == "=",
              ["texSample2D", "texture2D"].contains(values[3]),
              values[4] == "(", values.last == ")",
              let slot = SceneShaderSourceTextFacts.textureSlot(values[5]),
              values[6] == ",",
              matchingClose(in: values, opening: 4) == values.count - 1,
              values.filter({ ["texSample2D", "texture2D"].contains($0) }).count == 1
        else { return nil }
        return .init(
            variable: values[1],
            slot: slot,
            coordinate: Array(values[7..<(values.count - 1)]),
            statement: statement
        )
    }

    private static func matchesCoordinateAlias(
        _ statement: Range<Int>,
        reference: RGBDifferenceSample,
        fragment: Unit
    ) -> Bool {
        let value = texts(statement, tokens: fragment.tokens)
        guard value.count == 6,
              ["vec2", "float2"].contains(value[0]),
              fragment.tokens[statement.lowerBound + 1].kind == .identifier,
              value[2] == "=", value[4] == ".",
              ["xy", "zw"].contains(value[5]),
              reference.coordinate == [value[1]] else { return false }
        let varying = fragment.declarations.filter {
            $0.storage == .varying
                && $0.name == value[3]
                && ["vec4", "float4"].contains($0.typeName)
                && $0.arraySize == nil
        }
        guard varying.count == 1 else { return false }
        return fragment.tokens[statement.lowerBound..<reference.statement.upperBound]
            .filter({ $0.text == value[1] }).count == 2
    }

    private static func matchesDifference(
        _ statement: Range<Int>,
        source: String,
        reference: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 10
            && ["vec3", "float3"].contains(value[0])
            && value[2] == "="
            && value[3] == source && value[4] == "."
            && ["rgb", "xyz"].contains(value[5])
            && value[6] == "-"
            && value[7] == reference && value[8] == "."
            && ["rgb", "xyz"].contains(value[9])
    }

    private static func matchesEnhancement(
        _ statement: Range<Int>,
        source: String,
        delta: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 10
            && ["vec3", "float3"].contains(value[0])
            && value[2] == "="
            && value[3] == source && value[4] == "."
            && ["rgb", "xyz"].contains(value[5])
            && value[6] == "+" && value[7] == delta
            && value[8] == "*"
    }

    private static func matchesUnitScalarDeclaration(
        _ statement: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value.count == 4
            && value[0] == "float"
            && value[2] == "="
            && Double(value[3]) == 1
    }

    private static func matchesMix(
        _ statement: Range<Int>,
        source: String,
        enhancement: String,
        mask: String,
        tokens: [Token]
    ) -> Bool {
        let value = texts(statement, tokens: tokens)
        return value == [
            source, ".", "rgb", "=", "mix", "(",
            source, ".", "rgb", ",",
            enhancement, ".", "rgb", ",", mask, ")",
        ] || value == [
            source, ".", "xyz", "=", "mix", "(",
            source, ".", "xyz", ",",
            enhancement, ".", "xyz", ",", mask, ")",
        ]
    }

    private static func scalarAmountIsProven(
        _ value: String,
        fragment: Unit
    ) -> Bool {
        if let number = Double(value) { return number.isFinite }
        let matches = fragment.declarations.filter {
            $0.storage == .uniform
                && $0.typeName == "float"
                && $0.name == value
                && $0.arraySize == nil
        }
        return matches.count == 1
    }

    private static func differenceSamplerType(slot: Int, fragment: Unit) -> String? {
        let declarations = fragment.declarations.filter {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)"
        }
        guard declarations.count == 1 else { return nil }
        return declarations[0].typeName
    }

    private static func matchingClose(
        in values: [String],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<values.count {
            if values[index] == "(" { depth += 1 }
            if values[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func texts(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        range.map { tokens[$0].text }
    }
}
