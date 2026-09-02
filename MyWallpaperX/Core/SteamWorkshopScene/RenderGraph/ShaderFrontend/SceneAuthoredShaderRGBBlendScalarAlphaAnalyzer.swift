import Foundation

/// Proves one bounded straight-color carrier whose final scalar drives both
/// an authored RGB blend and multiplicative alpha. The proof is independent
/// of effect/path identity and admits distinct, single-sample red-channel data
/// slots from the bounded authored slot space plus one optional post-transform
/// opacity mask.
nonisolated enum SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let scalarAuxiliarySlots: Set<Int>
        let maskSlot: Int?
        let blendMode: Int
        let baseMultiplier: String
        let blendMultiplier: String
        let factorName: String
        let maskFactorName: String?
        let terminalTransform: SceneAuthoredShaderStraightColorTerminalTransform

        var auxiliarySlots: Set<Int> {
            scalarAuxiliarySlots.union(maskSlot.map { [$0] } ?? [])
        }
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
        var pendingMask: MaskBlend?
        var sawMaskMix = false

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
                      validBlendHelper(fragment, mode: candidate.mode)
                else { return nil }
                blend = candidate
                continue
            }
            if let blend,
               !sawAlphaMutation,
               alphaMultiplication(
                   statement,
                   carrierName: carrier,
                   factorName: blend.factorName
               ) {
                sawAlphaMutation = true
                continue
            }
            if sawAlphaMutation,
               pendingMask == nil,
               !sawMaskMix,
               let mask = maskDeclaration(
                   statement,
                   fragment: fragment,
                   scalarDependencies: scalarDependencies,
                   sourceName: source.name,
                   carrierName: carrier
               ) {
                pendingMask = mask
                continue
            }
            guard let mask = pendingMask,
                  !sawMaskMix,
                  maskMix(
                      statement,
                      sourceName: source.name,
                      carrierName: carrier,
                      factorName: mask.factorName
                  ) else { return nil }
            sawMaskMix = true
        }

        let maskSlots = pendingMask.map { [$0.slot] } ?? []
        guard let blend,
              sawAlphaMutation,
              (pendingMask == nil && !sawMaskMix)
                || (pendingMask != nil && sawMaskMix),
              let terminalTransform = terminalOutput(
                Array(fragment.tokens[statements.last!]),
                carrierName: carrier
              ), Set(auxiliarySlots).count == auxiliarySlots.count,
              !auxiliarySlots.contains(source.slot),
              pendingMask?.slot != source.slot,
              pendingMask.map({ !auxiliarySlots.contains($0.slot) }) ?? true,
              allScalarLocalsReachFactor(
                blend.factorName,
                scalarDependencies: scalarDependencies
              ), sampleSlots(in: fragment.tokens) == [source.slot]
                + auxiliarySlots + maskSlots
        else { return nil }
        return .init(
            sourceSlot: source.slot,
            scalarAuxiliarySlots: Set(auxiliarySlots),
            maskSlot: pendingMask?.slot,
            blendMode: blend.mode,
            baseMultiplier: blend.baseMultiplier,
            blendMultiplier: blend.blendMultiplier,
            factorName: blend.factorName,
            maskFactorName: pendingMask?.factorName,
            terminalTransform: terminalTransform
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

    private struct MaskBlend {
        let slot: Int
        let factorName: String
    }

    private static func maskDeclaration(
        _ tokens: [Token],
        fragment: Unit,
        scalarDependencies: [String: Set<String>],
        sourceName: String,
        carrierName: String
    ) -> MaskBlend? {
        guard let declaration = SceneAuthoredShaderUniformRGBMixAnalyzer
                .scalarDeclaration(tokens),
              scalarDependencies[declaration.name] == nil,
              declaration.name != sourceName,
              declaration.name != carrierName,
              declaration.expression.count >= 8,
              declaration.expression.suffix(2).map(\.text) == [".", "r"],
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(declaration.expression.dropLast(2)),
              fragment.declarations.filter({
                  $0.storage == .uniform && $0.arraySize == nil
                      && $0.typeName == "sampler2D"
                      && $0.name == "g_Texture\(slot)"
              }).count == 1 else { return nil }
        return .init(slot: slot, factorName: declaration.name)
    }

    private static func maskMix(
        _ tokens: [Token],
        sourceName: String,
        carrierName: String,
        factorName: String
    ) -> Bool {
        guard tokens.count >= 8,
              tokens[0].text == carrierName,
              tokens[1].text == "=",
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(tokens[2...]),
              ["mix", "lerp"].contains(call.name),
              call.arguments.count == 3 else { return false }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(call.arguments[0]) == sourceName
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[1]) == carrierName
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[2]) == factorName
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
    ) -> SceneAuthoredShaderStraightColorTerminalTransform? {
        guard Array(tokens.prefix(2)).map(\.text) == ["gl_FragColor", "="],
              let output = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(tokens[2...]) else { return nil }
        if output.name == "saturate",
           output.arguments.count == 1,
           SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(output.arguments[0]) == carrierName {
            return .saturateRGBA
        }
        guard tokens.count >= 12,
              ["vec4", "float4"].contains(output.name),
              output.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                output.arguments[1], name: carrierName, component: "a"
              ), let maximum = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(output.arguments[0]), maximum.name == "max",
              maximum.arguments.count == 2 else { return nil }
        return (zeroVector(maximum.arguments[0])
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                maximum.arguments[1], name: carrierName, component: "rgb"
            ) || zeroVector(maximum.arguments[1])
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                maximum.arguments[0], name: carrierName, component: "rgb"
            )) ? .nonNegativeRGBPreservedAlpha : nil
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
            "pow", "saturate", "sin",
            "smoothstep", "texSample2D", "texture2D", "vec3", "vec4",
        ]
        return fragment.functions.allSatisfy {
            $0.name == "main" || $0.name == "ApplyBlending"
                || !protected.contains($0.name)
        }
    }

    static func validBlendHelper(
        _ fragment: Unit,
        mode: Int
    ) -> Bool {
        let helpers = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard helpers.count == 1, let helper = helpers.first,
              let names = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .blendParameterNames(helper, fragment: fragment),
              let returns = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .rootReturnExpressions(helper, fragment: fragment),
              returns.count == 2 else { return false }
        let selectedModeIsProven = switch mode {
        case 3: modeThreeColorBurnBlend(returns[0], names: names)
        case 9: modeNineAddBlend(returns[0], names: names)
        case 31: modeThirtyOneAdditiveBlend(returns[0], names: names)
        default: false
        }
        return selectedModeIsProven
            && normalFallback(returns[1], names: names)
    }

    private static func modeThreeColorBurnBlend(
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
              let colorBurn = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(mix.arguments[1]),
              ["CAST3", "vec3", "float3"].contains(colorBurn.name),
              colorBurn.arguments.count == 3 else { return false }
        return zip(colorBurn.arguments, ["r", "g", "b"]).allSatisfy {
            colorBurnComponent(
                $0.0,
                baseName: names[1],
                blendName: names[2],
                component: $0.1
            )
        }
    }

    private static func colorBurnComponent(
        _ expression: ArraySlice<Token>,
        baseName: String,
        blendName: String,
        component: String
    ) -> Bool {
        guard let branches = rootTernary(expression),
              let equality = binary(branches.condition, operator: "=="),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                equality.left, name: blendName, component: component
              ), SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(equality.right) == 0,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                branches.trueValue, name: blendName, component: component
              ), let maximum = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(branches.falseValue),
              maximum.name == "max", maximum.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(maximum.arguments[1]) == 0,
              let outer = binary(maximum.arguments[0], operator: "-"),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(outer.left) == 1,
              let division = binary(outer.right, operator: "/"),
              let inner = binary(division.left, operator: "-"),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(inner.left) == 1,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                inner.right, name: baseName, component: component
              ), SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                division.right, name: blendName, component: component
              ) else { return false }
        return true
    }

    private static func rootTernary(
        _ expression: ArraySlice<Token>
    ) -> (
        condition: ArraySlice<Token>,
        trueValue: ArraySlice<Token>,
        falseValue: ArraySlice<Token>
    )? {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(expression)
        var depth = 0
        var question: Int?
        var colon: Int?
        for index in value.indices {
            if ["(", "["].contains(value[index].text) { depth += 1 }
            if [")", "]"].contains(value[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, value[index].text == "?" {
                guard question == nil, colon == nil else { return nil }
                question = index
            } else if depth == 0, value[index].text == ":" {
                guard question != nil, colon == nil else { return nil }
                colon = index
            }
        }
        guard depth == 0, let question, let colon,
              value.startIndex < question, question + 1 < colon,
              colon + 1 < value.endIndex else { return nil }
        return (
            value[..<question],
            value[(question + 1)..<colon],
            value[(colon + 1)...]
        )
    }

    private static func binary(
        _ expression: ArraySlice<Token>,
        operator operation: String
    ) -> (left: ArraySlice<Token>, right: ArraySlice<Token>)? {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(expression)
        guard let index = soleTopLevelOperator(operation, in: value),
              value.startIndex < index, index + 1 < value.endIndex else {
            return nil
        }
        return (value[..<index], value[(index + 1)...])
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

    private static func modeThirtyOneAdditiveBlend(
        _ expression: ArraySlice<Token>,
        names: [String]
    ) -> Bool {
        guard let addition = binary(expression, operator: "+"),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(addition.left) == names[1],
              let product = binary(addition.right, operator: "*") else {
            return false
        }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(product.left) == names[2]
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(product.right) == names[3]
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
