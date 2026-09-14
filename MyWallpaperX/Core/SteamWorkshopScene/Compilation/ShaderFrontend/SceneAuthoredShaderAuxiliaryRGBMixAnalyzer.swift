import Foundation

/// Proves one bounded RGB replacement while preserving the graph-input alpha.
/// The shape is structural: one source color sample, one distinct auxiliary
/// RGB slot used either directly or by the registered bounded preprocessing,
/// a scalar-uniform blend, and one terminal source carrier.
nonisolated enum SceneAuthoredShaderAuxiliaryRGBMixAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              fragment.functions.allSatisfy({ $0.name != "mix" }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: tokens)
        else { return nil }
        if let slot = analyzeDirectMix(
            statements: statements,
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return slot
        }
        return analyzeProcessedBlend(
            statements: statements,
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    private static func analyzeDirectMix(
        statements: [Range<Int>],
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard statements.count == 4,
              let source = colorSampleDeclaration(
                tokens[statements[0]], fragment: fragment
              ),
              let auxiliary = auxiliarySampleDeclaration(
                tokens[statements[1]], fragment: fragment
              ),
              source.slot != auxiliary.slot,
              !sourceCarrierEscapesToMutableAuthoredCall(
                source.name, fragment: fragment, main: main
              ),
              rgbMixAssignment(
                tokens[statements[2]],
                sourceName: source.name,
                auxiliaryName: auxiliary.name,
                fragment: fragment
              ),
              terminalOutput(
                tokens[statements[3]], sourceName: source.name
              ),
              statements[3].contains(outputUses[0]),
              sampleCallCount(in: main.bodyRange, tokens: tokens) == 2,
              sampleCallCount(
                in: fragment.tokens.indices,
                tokens: fragment.tokens
              ) == 2
        else { return nil }
        return source.slot
    }

    private static func analyzeProcessedBlend(
        statements: [Range<Int>],
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        let hasMatchedGreyscalePreprocessing = statements.count == 10
        let preprocessingCount = hasMatchedGreyscalePreprocessing ? 2 : 0
        guard [8, 10].contains(statements.count),
              let source = colorSampleDeclaration(
                tokens[statements[0]], fragment: fragment
              ),
              let first = swizzledAuxiliarySampleDeclaration(
                tokens[statements[1]], fragment: fragment
              ),
              let second = swizzledAuxiliarySampleDeclaration(
                tokens[statements[2]], fragment: fragment
              ),
              source.slot != first.slot,
              first.slot == second.slot,
              first.name != second.name,
              !sourceCarrierEscapesToMutableAuthoredCall(
                source.name, fragment: fragment, main: main
              ),
              !hasMatchedGreyscalePreprocessing || (
                greyscaleAssignment(
                    tokens[statements[3]], accumulator: first.name
                )
                && greyscaleAssignment(
                    tokens[statements[4]], accumulator: second.name
                )
              ),
              productSaturateAssignment(
                tokens[statements[3 + preprocessingCount]],
                first: first.name,
                second: second.name
              ),
              let power = powerAssignment(
                tokens[statements[4 + preprocessingCount]],
                accumulator: first.name
              ),
              uniformFloat(power, fragment: fragment),
              let blend = scalarUniformAlias(
                tokens[statements[5 + preprocessingCount]],
                fragment: fragment
              ),
              processedRGBBlendAssignment(
                tokens[statements[6 + preprocessingCount]],
                sourceName: source.name,
                auxiliaryName: first.name,
                blendName: blend
              ),
              terminalOutput(
                tokens[statements[7 + preprocessingCount]],
                sourceName: source.name
              ),
              statements[7 + preprocessingCount].contains(outputUses[0]),
              sampleCallCount(in: main.bodyRange, tokens: tokens) == 3,
              sampleCallCount(
                in: fragment.tokens.indices,
                tokens: fragment.tokens
              ) == 3
        else { return nil }
        return source.slot
    }

    /// Mutable authored parameters can hide a carrier write inside an
    /// otherwise read-only-looking sample coordinate or helper expression.
    /// Reject only calls to helpers that declare such a parameter and receive
    /// this carrier; unrelated common-header `inout` helpers remain harmless.
    private static func sourceCarrierEscapesToMutableAuthoredCall(
        _ sourceName: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let mutableFunctionNames = Set(fragment.functions.compactMap {
            function -> String? in
            tokens[function.parameterRange].contains(where: {
                ["out", "inout"].contains($0.text)
            }) ? function.name : nil
        })
        guard !mutableFunctionNames.isEmpty else { return false }
        return main.bodyRange.contains { index in
            guard mutableFunctionNames.contains(tokens[index].text),
                  index + 1 < main.bodyRange.upperBound,
                  tokens[index + 1].text == "(",
                  let close = SceneAuthoredShaderVectorConversion
                    .matchingParenthesis(tokens: tokens, opening: index + 1),
                  close < main.bodyRange.upperBound else { return false }
            return tokens[(index + 2)..<close].contains(where: {
                $0.text == sourceName
            })
        }
    }

    /// Accepts the authored common-helper form only as a matched pair over
    /// the two local RGB noise values. The helper remains compiler-executed;
    /// this proof only establishes that preprocessing cannot replace the
    /// source carrier or mutate its alpha before the bounded RGB blend.
    private static func greyscaleAssignment(
        _ slice: ArraySlice<Token>,
        accumulator: String
    ) -> Bool {
        Array(slice).map(\.text) == [
            accumulator, "=", "CAST3", "(", "greyscale", "(",
            accumulator, ")", ")",
        ]
    }

    private static func colorSampleDeclaration(
        _ slice: ArraySlice<Token>,
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        let values = Array(slice)
        guard values.count >= 7,
              ["vec4", "float4"].contains(values[0].text),
              values[1].kind == .identifier,
              values[2].text == "=",
              let sample = sampleCall(Array(values.dropFirst(3))),
              fragmentHasSampler(sample.sampler, fragment: fragment)
        else { return nil }
        return (values[1].text, sample.slot)
    }

    private static func auxiliarySampleDeclaration(
        _ slice: ArraySlice<Token>,
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        let values = Array(slice)
        guard values.count >= 10,
              ["vec3", "float3"].contains(values[0].text),
              values[1].kind == .identifier,
              values[2].text == "=",
              values.suffix(2).map(\.text) == [".", "rgb"],
              let sample = sampleCall(Array(values.dropFirst(3).dropLast(2))),
              fragmentHasSampler(sample.sampler, fragment: fragment)
        else { return nil }
        return (values[1].text, sample.slot)
    }

    private static func swizzledAuxiliarySampleDeclaration(
        _ slice: ArraySlice<Token>,
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        let values = Array(slice)
        guard values.count >= 10,
              ["vec3", "float3"].contains(values[0].text),
              values[1].kind == .identifier,
              values[2].text == "=",
              values[values.count - 2].text == ".",
              let swizzle = values.last?.text,
              swizzle.count == 3,
              swizzle.allSatisfy({ "rgb".contains($0) }),
              let sample = sampleCall(Array(values.dropFirst(3).dropLast(2))),
              fragmentHasSampler(sample.sampler, fragment: fragment)
        else { return nil }
        return (values[1].text, sample.slot)
    }

    private static func productSaturateAssignment(
        _ slice: ArraySlice<Token>,
        first: String,
        second: String
    ) -> Bool {
        Array(slice).map(\.text) == [
            first, "=", "saturate", "(", first, "*", second, ")",
        ]
    }

    private static func powerAssignment(
        _ slice: ArraySlice<Token>,
        accumulator: String
    ) -> String? {
        let values = Array(slice).map(\.text)
        guard values.count == 11,
              Array(values.prefix(5))
                == [accumulator, "=", "pow", "(", accumulator],
              Array(values.suffix(5)) == ["CAST3", "(", values[8], ")", ")"],
              values[5] == "," else { return nil }
        return values[8]
    }

    private static func scalarUniformAlias(
        _ slice: ArraySlice<Token>,
        fragment: Unit
    ) -> String? {
        let values = Array(slice)
        guard values.count == 4,
              values[0].text == "float",
              values[1].kind == .identifier,
              values[2].text == "=",
              uniformFloat(values[3].text, fragment: fragment)
        else { return nil }
        return values[1].text
    }

    private static func processedRGBBlendAssignment(
        _ slice: ArraySlice<Token>,
        sourceName: String,
        auxiliaryName: String,
        blendName: String
    ) -> Bool {
        let values = Array(slice)
        guard values.count >= 16,
              Array(values.prefix(4)).map(\.text)
                == [sourceName, ".", "rgb", "="],
              let arguments = callArguments(
                Array(values.dropFirst(4)), name: "ApplyBlending"
              ), arguments.count == 4,
              arguments[0].count == 1,
              Int(arguments[0][0].text) != nil,
              arguments[1].map(\.text) == [sourceName, ".", "rgb"],
              arguments[2].map(\.text) == [auxiliaryName],
              arguments[3].map(\.text) == [blendName]
        else { return false }
        return true
    }

    private static func uniformFloat(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        fragment.declarations.filter {
            $0.name == name && $0.storage == .uniform
                && $0.typeName == "float" && $0.arraySize == nil
        }.count == 1
    }

    private static func rgbMixAssignment(
        _ slice: ArraySlice<Token>,
        sourceName: String,
        auxiliaryName: String,
        fragment: Unit
    ) -> Bool {
        let values = Array(slice)
        guard values.count >= 13,
              Array(values.prefix(4)).map(\.text)
                == [sourceName, ".", "rgb", "="],
              let call = callArguments(Array(values.dropFirst(4)), name: "mix"),
              call.count == 3,
              call[0].map(\.text) == [sourceName, ".", "rgb"],
              call[1].map(\.text) == [auxiliaryName],
              call[2].count == 1,
              let scalar = call[2].first?.text
        else { return false }
        return fragment.declarations.filter {
            $0.name == scalar && $0.storage == .uniform
                && $0.typeName == "float" && $0.arraySize == nil
        }.count == 1
    }

    private static func terminalOutput(
        _ slice: ArraySlice<Token>,
        sourceName: String
    ) -> Bool {
        Array(slice).map(\.text) == ["gl_FragColor", "=", sourceName]
    }

    private static func fragmentHasSampler(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        fragment.declarations.filter {
            $0.name == name && $0.storage == .uniform
                && $0.typeName == "sampler2D" && $0.arraySize == nil
        }.count == 1
    }

    private static func sampleCall(
        _ values: [Token]
    ) -> (sampler: String, slot: Int)? {
        guard let arguments = callArguments(values, names: [
            "texSample2D", "texture2D",
        ]), arguments.count == 2,
              arguments[0].count == 1,
              let sampler = arguments[0].first?.text,
              let slot = textureSlot(sampler)
        else { return nil }
        return (sampler, slot)
    }

    private static func callArguments(
        _ values: [Token],
        name: String
    ) -> [[Token]]? {
        callArguments(values, names: [name])
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

    private static func sampleCallCount(
        in body: Range<Int>,
        tokens: [Token]
    ) -> Int {
        body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }.count
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0..<8).contains(slot) else { return nil }
        return slot
    }
}
