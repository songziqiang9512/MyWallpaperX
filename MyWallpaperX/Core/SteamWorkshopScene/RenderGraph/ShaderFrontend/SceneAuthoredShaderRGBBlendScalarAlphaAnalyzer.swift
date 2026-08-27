import Foundation

/// Proves one bounded straight-color carrier whose final scalar drives both
/// an authored RGB blend and multiplicative alpha. The proof is independent
/// of effect/path identity and admits at most one distinct red-channel data
/// sample in the scalar graph.
nonisolated enum SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let auxiliarySlots: Set<Int>
        let blendMode: Int
        let baseMultiplier: String
        let blendMultiplier: String
        let factorName: String
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (7 ... 20).contains(statements.count),
              noControlFlow(main, tokens: fragment.tokens),
              noShadowedBuiltins(fragment),
              let source = sourceDeclaration(
                Array(fragment.tokens[statements[0]]), fragment: fragment
              ), let carrier = carrierAlias(
                Array(fragment.tokens[statements[1]]), sourceName: source.name
              ) else { return nil }

        let globals = Dictionary(uniqueKeysWithValues:
            fragment.declarations.compactMap { declaration in
                declaration.arraySize == nil
                    ? (declaration.name, declaration.typeName) : nil
            }
        )
        var scalarDependencies: [String: Set<String>] = [:]
        var auxiliarySlots: [Int] = []
        var blend: RGBBlend?
        var sawAlphaMutation = false

        for range in statements.dropFirst(2).dropLast() {
            let statement = Array(fragment.tokens[range])
            if blend == nil,
               let declaration = SceneAuthoredShaderUniformRGBMixAnalyzer
                .scalarDeclaration(statement) {
                guard scalarDependencies[declaration.name] == nil,
                      let slots = scalarExpression(
                        declaration.expression,
                        globals: globals,
                        scalarNames: Set(scalarDependencies.keys),
                        scalarDependencies: scalarDependencies,
                        sourceName: source.name,
                        carrierName: carrier,
                        sourceSlot: source.slot
                      ) else { return nil }
                scalarDependencies[declaration.name] = slots.dependencies
                auxiliarySlots.append(contentsOf: slots.auxiliarySlots)
                continue
            }
            if blend == nil,
               let assignment = scalarAssignment(statement),
               let previous = scalarDependencies[assignment.name],
               let slots = scalarExpression(
                assignment.expression,
                globals: globals,
                scalarNames: Set(scalarDependencies.keys),
                scalarDependencies: scalarDependencies,
                sourceName: source.name,
                carrierName: carrier,
                sourceSlot: source.slot
               ) {
                guard ["=", "+="].contains(assignment.operation) else { return nil }
                scalarDependencies[assignment.name] = assignment.operation == "+="
                    ? previous.union(slots.dependencies) : slots.dependencies
                auxiliarySlots.append(contentsOf: slots.auxiliarySlots)
                continue
            }
            if blend == nil,
               let candidate = rgbBlendFactor(
                statement,
                carrierName: carrier,
                fragment: fragment
               ) {
                guard scalarDependencies[candidate.factorName] != nil,
                      validBlendHelper(fragment, blend: candidate)
                else { return nil }
                blend = candidate
                continue
            }
            guard let blend,
                  !sawAlphaMutation,
                  alphaMultiplication(
                    statement,
                    carrierName: carrier,
                    factorName: blend.factorName
                  ) else { return nil }
            sawAlphaMutation = true
        }

        guard let blend,
              sawAlphaMutation,
              terminalOutput(
                Array(fragment.tokens[statements.last!]),
                carrierName: carrier
              ), auxiliarySlots.count <= 1,
              Set(auxiliarySlots).count == auxiliarySlots.count,
              !auxiliarySlots.contains(source.slot),
              allScalarLocalsReachFactor(
                blend.factorName,
                scalarDependencies: scalarDependencies
              ), sampleSlots(in: fragment.tokens)
                == [source.slot] + auxiliarySlots else { return nil }
        return .init(
            sourceSlot: source.slot,
            auxiliarySlots: Set(auxiliarySlots),
            blendMode: blend.mode,
            baseMultiplier: blend.baseMultiplier,
            blendMultiplier: blend.blendMultiplier,
            factorName: blend.factorName
        )
    }

    private static func sourceDeclaration(
        _ tokens: [Token], fragment: Unit
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(tokens[3...]),
              fragment.declarations.filter({
                  $0.storage == .uniform && $0.arraySize == nil
                      && $0.typeName == "sampler2D"
                      && $0.name == "g_Texture\(slot)"
              }).count == 1 else { return nil }
        return (tokens[1].text, slot)
    }

    private static func carrierAlias(
        _ tokens: [Token], sourceName: String
    ) -> String? {
        guard tokens.count == 4,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[1].text != sourceName,
              tokens[2].text == "=",
              tokens[3].text == sourceName else { return nil }
        return tokens[1].text
    }

    private static func scalarAssignment(
        _ tokens: [Token]
    ) -> (name: String, operation: String, expression: [Token])? {
        guard tokens.count >= 3,
              tokens[0].kind == .identifier,
              ["=", "+="].contains(tokens[1].text) else { return nil }
        return (tokens[0].text, tokens[1].text, Array(tokens.dropFirst(2)))
    }

    private struct ScalarExpression {
        let dependencies: Set<String>
        let auxiliarySlots: [Int]
    }

    private static func scalarExpression(
        _ tokens: [Token],
        globals: [String: String],
        scalarNames: Set<String>,
        scalarDependencies: [String: Set<String>],
        sourceName: String,
        carrierName: String,
        sourceSlot: Int
    ) -> ScalarExpression? {
        let context = SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer
            .ScalarContext(
                globals: globals,
                locals: scalarNames,
                colorNames: [sourceName, carrierName],
                colorSlot: sourceSlot
            )
        guard let slots = SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer
            .scalarExpression(tokens, context: context) else { return nil }
        var dependencies: Set<String> = []
        for token in tokens
        where token.kind == .identifier && scalarNames.contains(token.text) {
            dependencies.insert(token.text)
            dependencies.formUnion(scalarDependencies[token.text] ?? [])
        }
        return .init(dependencies: dependencies, auxiliarySlots: slots)
    }

    private struct RGBBlend {
        let mode: Int
        let baseMultiplier: String
        let blendMultiplier: String
        let factorName: String
    }

    private static func rgbBlendFactor(
        _ tokens: [Token], carrierName: String, fragment: Unit
    ) -> RGBBlend? {
        guard tokens.count >= 16,
              Array(tokens.prefix(4)).map(\.text)
                == [carrierName, ".", "rgb", "="],
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(tokens[4...]),
              call.name == "ApplyBlending",
              call.arguments.count == 4,
              let mode = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(call.arguments[0]),
              mode.rounded() == mode,
              let integerMode = Int(exactly: mode),
              let baseMultiplier = carrierRGBMultiplier(
                call.arguments[1], carrierName: carrierName, fragment: fragment
              ), let blendMultiplier = carrierRGBMultiplier(
                call.arguments[2], carrierName: carrierName, fragment: fragment
              ), let factor = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[3]),
              baseMultiplier != blendMultiplier else { return nil }
        return .init(
            mode: integerMode,
            baseMultiplier: baseMultiplier,
            blendMultiplier: blendMultiplier,
            factorName: factor
        )
    }

    private static func carrierRGBMultiplier(
        _ expression: ArraySlice<Token>, carrierName: String, fragment: Unit
    ) -> String? {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(expression)
        guard let multiplication = soleTopLevelOperator("*", in: value) else {
            return nil
        }
        let left = value[..<multiplication]
        let right = value[value.index(after: multiplication)...]
        if SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            left, name: carrierName, component: "rgb"
        ) { return uniformRGBName(right, fragment: fragment) }
        guard SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            right, name: carrierName, component: "rgb"
        ) else { return nil }
        return uniformRGBName(left, fragment: fragment)
    }

    private static func uniformRGBName(
        _ expression: ArraySlice<Token>, fragment: Unit
    ) -> String? {
        guard let name = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(expression) else { return nil }
        let matches = fragment.declarations.filter { $0.name == name }
        return matches.count == 1
            && matches[0].storage == .uniform
            && matches[0].arraySize == nil
            && ["vec3", "float3"].contains(matches[0].typeName)
            ? name : nil
    }

    private static func alphaMultiplication(
        _ tokens: [Token], carrierName: String, factorName: String
    ) -> Bool {
        tokens.map(\.text) == [carrierName, ".", "a", "*=", factorName]
    }

    private static func terminalOutput(
        _ tokens: [Token], carrierName: String
    ) -> Bool {
        guard tokens.count >= 12,
              Array(tokens.prefix(2)).map(\.text) == ["gl_FragColor", "="],
              let output = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(tokens[2...]),
              ["vec4", "float4"].contains(output.name),
              output.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                output.arguments[1], name: carrierName, component: "a"
              ), let maximum = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(output.arguments[0]), maximum.name == "max",
              maximum.arguments.count == 2 else { return false }
        return zeroVector(maximum.arguments[0])
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                maximum.arguments[1], name: carrierName, component: "rgb"
            ) || zeroVector(maximum.arguments[1])
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                maximum.arguments[0], name: carrierName, component: "rgb"
            )
    }

    private static func zeroVector(_ expression: ArraySlice<Token>) -> Bool {
        guard let vector = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .call(expression),
              ["CAST3", "vec3", "float3"].contains(vector.name),
              vector.arguments.count == 1,
              let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(vector.arguments[0]) else { return false }
        return value == 0
    }

    private static func allScalarLocalsReachFactor(
        _ factorName: String,
        scalarDependencies: [String: Set<String>]
    ) -> Bool {
        guard let dependencies = scalarDependencies[factorName] else { return false }
        return dependencies.union([factorName]) == Set(scalarDependencies.keys)
    }

    private static func noControlFlow(
        _ main: Unit.Function, tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "break", "continue", "return", "?",
        ]
        return !main.bodyRange.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func noShadowedBuiltins(_ fragment: Unit) -> Bool {
        let protected: Set<String> = [
            "CAST3", "float3", "float4", "lerp", "max", "min", "mix",
            "pow", "sin",
            "smoothstep", "texSample2D", "texture2D", "vec3", "vec4",
        ]
        return fragment.functions.allSatisfy {
            $0.name == "main" || $0.name == "ApplyBlending"
                || !protected.contains($0.name)
        }
    }

    private static func validBlendHelper(
        _ fragment: Unit,
        blend: RGBBlend
    ) -> Bool {
        let helpers = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard helpers.count == 1, let helper = helpers.first,
              blend.mode == 9,
              let names = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .blendParameterNames(helper, fragment: fragment),
              let returns = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .rootReturnExpressions(helper, fragment: fragment),
              returns.count == 2 else { return false }
        return modeNineAddBlend(returns[0], names: names)
            && normalFallback(returns[1], names: names)
    }

    private static func modeNineAddBlend(
        _ expression: ArraySlice<Token>,
        names: [String]
    ) -> Bool {
        guard let mix = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(expression),
              ["mix", "lerp"].contains(mix.name),
              mix.arguments.count == 3,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(mix.arguments[0]) == names[1],
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(mix.arguments[2]) == names[3],
              let minimum = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(mix.arguments[1]),
              minimum.name == "min",
              minimum.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.texts(
                SceneAuthoredShaderConditionalStraightUnionAnalyzer
                    .strippingParentheses(minimum.arguments[0])
              ) == [names[1], "+", names[2]],
              oneVector(minimum.arguments[1]) else { return false }
        return true
    }

    private static func normalFallback(
        _ expression: ArraySlice<Token>,
        names: [String]
    ) -> Bool {
        guard let mix = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(expression),
              ["mix", "lerp"].contains(mix.name),
              mix.arguments.count == 3 else { return false }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(mix.arguments[0]) == names[1]
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer.identifier(
                SceneAuthoredShaderConditionalStraightUnionAnalyzer
                    .strippingParentheses(mix.arguments[1])
            ) == names[2]
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(mix.arguments[2]) == names[3]
    }

    private static func oneVector(_ expression: ArraySlice<Token>) -> Bool {
        guard let vector = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(expression),
              ["CAST3", "vec3", "float3"].contains(vector.name),
              vector.arguments.count == 1,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(vector.arguments[0]) == 1 else { return false }
        return true
    }

    private static func sampleSlots(in tokens: [Token]) -> [Int]? {
        var slots: [Int] = []
        for index in tokens.indices where ["texSample2D", "texture2D"]
            .contains(tokens[index].text) {
            guard index + 2 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer
                    .textureSlot(tokens[index + 2].text) else { return nil }
            slots.append(slot)
        }
        return slots
    }

    private static func soleTopLevelOperator(
        _ value: String, in tokens: ArraySlice<Token>
    ) -> Int? {
        var matches: [Int] = []
        var depth = 0
        for index in tokens.indices {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, tokens[index].text == value { matches.append(index) }
        }
        return depth == 0 && matches.count == 1 ? matches[0] : nil
    }
}
