import Foundation

nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    /// Generated text-like color with a source-alpha seed and conditional,
    /// source-independent alpha replacements.
    static func conditionalGeneratedRGBA(
        _ arguments: [ArraySlice<Token>],
        sampled: [String: Int],
        output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> SourceCarriedFact? {
        guard sampled.count == 1, let source = sampled.first,
              let rgb = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[0]),
              let alpha = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[1]),
              generatedRGB(
                rgb, before: output, fragment: fragment, main: main
              ), alphaSeedAndReplacements(
                alpha, source: source.key,
                before: output, fragment: fragment, main: main
              ), noWholeSampleFlowsIntoRGB(
                sourceDeclaration: source.key,
                before: output, tokens: fragment.tokens, body: main.bodyRange
              ) else { return nil }
        return .init(sourceSlot: source.value, transfer: .straight)
    }

    /// Audio-bar-like generated RGB: one uniform seed is blended with one
    /// sampled scene color and terminal alpha follows a bounded whitelist.
    static func uniformSeededBlendRGBA(
        _ arguments: [ArraySlice<Token>],
        sampled: [String: Int],
        output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> SourceCarriedFact? {
        guard sampled.count == 1, let source = sampled.first,
              let rgb = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[0]),
              let alpha = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[1]),
              uniformSeededRGBBlend(
                rgb, source: source.key,
                before: output, fragment: fragment, main: main
              ), boundedTerminalAlpha(
                alpha, source: source.key,
                before: output, fragment: fragment, main: main
              ), noWholeSampleFlowsIntoRGB(
                sourceDeclaration: source.key,
                before: output, tokens: fragment.tokens, body: main.bodyRange
              ) else { return nil }
        return .init(sourceSlot: source.value, transfer: .straight)
    }

    private static func generatedRGB(
        _ name: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index + 1 < output
                && tokens[index].text == name
                && ["vec3", "float3"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        let values = writes(
            name, typeNames: ["vec3", "float3"], before: output,
            tokens: tokens, body: main.bodyRange
        )
        guard definitions.count == 1, let definition = definitions.first,
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
              let seed = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(initializer),
              generatedRGBSeed(
                seed, before: definition, fragment: fragment, main: main
              ), values.allSatisfy({ write in
                if write == definition { return true }
                guard let rhs = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: write, in: tokens, body: main.bodyRange),
                      let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                        .identifier(rhs) else { return false }
                return uniform(
                    value, types: ["vec3", "float3"], fragment: fragment
                )
              }), !hasOtherMutation(
                name, permittedWrites: Set(values),
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return false }
        return true
    }

    private static func generatedRGBSeed(
        _ name: String,
        before boundary: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let definitions = writes(
            name, typeNames: ["vec3", "float3"], before: boundary,
            tokens: tokens, body: main.bodyRange
        )
        guard definitions.count == 1, let definition = definitions.first,
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(expression),
              ["mix", "lerp"].contains(call.name), call.arguments.count == 3
        else { return false }
        return call.arguments.prefix(2).allSatisfy { argument in
            guard let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(argument) else { return false }
            return uniform(value, types: ["vec3", "float3"], fragment: fragment)
        } && !call.arguments[2].contains {
            ["texSample2D", "texture2D"].contains($0.text)
        }
    }

    private static func alphaSeedAndReplacements(
        _ name: String,
        source: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let values = writes(
            name, typeNames: ["float"], before: output,
            tokens: tokens, body: main.bodyRange
        )
        guard let seed = values.first, tokens[seed - 1].text == "float",
              let initial = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: seed, in: tokens, body: main.bodyRange),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                initial, name: source, component: "a"
              ), values.dropFirst().allSatisfy({ write in
                guard let rhs = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: write, in: tokens, body: main.bodyRange),
                      let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                        .identifier(rhs) else { return false }
                return uniform(value, types: ["float"], fragment: fragment)
              }), !hasOtherMutation(
                name, permittedWrites: Set(values),
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return false }
        return true
    }

    private static func uniformSeededRGBBlend(
        _ name: String,
        source: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let values = writes(
            name, typeNames: ["vec3", "float3"], before: output,
            tokens: tokens, body: main.bodyRange
        )
        guard values.count == 2, let definition = values.first,
              let seed = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
              let seedName = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(seed),
              uniform(seedName, types: ["vec3", "float3"], fragment: fragment),
              let blend = values.last,
              let rhs = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: blend, in: tokens, body: main.bodyRange),
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(rhs),
              call.name == "ApplyBlending", call.arguments.count == 4,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.number(
                call.arguments[0]
              ) == 0,
              normalBlendBase(call.arguments[1], rgb: name, source: source),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                call.arguments[2], name: name, component: "rgb"
              ), !call.arguments[3].contains(where: { $0.text == source }),
              normalBlendHelper(fragment),
              !hasOtherMutation(
                name, permittedWrites: Set(values),
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return false }
        return true
    }

    private static func normalBlendBase(
        _ expression: ArraySlice<Token>, rgb: String, source: String
    ) -> Bool {
        guard let mix = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(expression),
              ["mix", "lerp"].contains(mix.name), mix.arguments.count == 3
        else { return false }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            mix.arguments[0], name: rgb, component: "rgb"
        ) && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            mix.arguments[1], name: source, component: "rgb"
        ) && SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            mix.arguments[2], name: source, component: "a"
        )
    }

    private static func normalBlendHelper(_ fragment: Unit) -> Bool {
        let helpers = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard helpers.count == 1, let helper = helpers.first,
              let names = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .blendParameterNames(helper, fragment: fragment),
              let output = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .rootReturnExpressions(helper, fragment: fragment)?.last,
              let mix = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(output),
              ["mix", "lerp"].contains(mix.name), mix.arguments.count == 3
        else { return false }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(mix.arguments[0]) == names[1]
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(SceneAuthoredShaderConditionalStraightUnionAnalyzer
                    .strippingParentheses(mix.arguments[1])) == names[2]
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(mix.arguments[2]) == names[3]
    }

    private static func boundedTerminalAlpha(
        _ name: String,
        source: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let values = writes(
            name, typeNames: ["float"], before: output,
            tokens: tokens, body: main.bodyRange
        )
        guard values.count == 1, let definition = values.first,
              let value = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: definition, in: tokens, body: main.bodyRange),
              !hasOtherMutation(
                name, permittedWrites: Set(values),
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return false }
        if SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
            value, name: source, component: "a"
        ) { return true }
        guard let maximum = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(value),
              maximum.name == "max", maximum.arguments.count == 2 else { return false }
        return maximum.arguments.contains {
            SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                $0, name: source, component: "a"
            )
        } && maximum.arguments.contains {
            !$0.contains(where: { $0.text == source })
        }
    }

    private static func writes(
        _ name: String,
        typeNames: Set<String>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [Int] {
        body.filter { index in
            index > body.lowerBound && index + 1 < boundary
                && tokens[index].text == name && tokens[index + 1].text == "="
                && (typeNames.contains(tokens[index - 1].text)
                    || tokens[index - 1].text != ".")
        }
    }

    private static func hasOtherMutation(
        _ name: String,
        permittedWrites: Set<Int>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        body.contains { index in
            guard index < boundary, tokens[index].text == name else { return false }
            if index + 1 < boundary,
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 1].text) {
                return !permittedWrites.contains(index)
            }
            return index + 3 < boundary && tokens[index + 1].text == "."
                && ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text)
        }
    }

    private static func noWholeSampleFlowsIntoRGB(
        sourceDeclaration name: String,
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        for index in body where index < output
            && ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard let close = matchingParenthesis(at: index + 1, tokens: tokens),
                  close < output else { return false }
            if close + 1 < output, tokens[close + 1].text == "." { continue }
            let isSourceDeclaration = index >= 3
                && tokens[index - 2].text == name
                && ["vec4", "float4"].contains(tokens[index - 3].text)
            if !isSourceDeclaration { return false }
        }
        return true
    }

    private static func matchingParenthesis(
        at open: Int, tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(open), tokens[open].text == "(" else { return nil }
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func uniform(
        _ name: String, types: Set<String>, fragment: Unit
    ) -> Bool {
        let matches = fragment.declarations.filter { $0.name == name }
        return matches.count == 1 && matches[0].storage == .uniform
            && matches[0].arraySize == nil && types.contains(matches[0].typeName)
    }
}
