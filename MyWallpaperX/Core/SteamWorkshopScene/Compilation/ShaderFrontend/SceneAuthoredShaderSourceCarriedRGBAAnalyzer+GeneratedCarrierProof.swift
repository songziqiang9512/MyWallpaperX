import Foundation

nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    static func generatedRGB(
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

    static func generatedRGBSeed(
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

    static func alphaSeedAndReplacements(
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

    static func uniformSeededRGBBlend(
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
              let modeValue = SceneAuthoredShaderConditionalStraightUnionAnalyzer.number(
                call.arguments[0]
              ), let mode = Int(exactly: modeValue),
              normalBlendBase(call.arguments[1], rgb: name, source: source),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.member(
                call.arguments[2], name: name, component: "rgb"
              ), !call.arguments[3].contains(where: { $0.text == source }),
              validatedRGBBlendHelper(fragment, mode: mode),
              !hasOtherMutation(
                name, permittedWrites: Set(values),
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return false }
        return true
    }

    static func normalBlendBase(
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

    static func validatedRGBBlendHelper(_ fragment: Unit, mode: Int) -> Bool {
        if mode != 0 {
            return SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.validBlendHelper(
                fragment, mode: mode
            )
        }
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

    static func boundedTerminalAlpha(
        _ name: String,
        source: String,
        rgb: String,
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
        // The already validated RGB blend can publish its same scalar weight
        // as replacement coverage. This is not source-alpha preservation:
        // the existing straight-output boundary must still premultiply once.
        if !value.contains(where: { $0.text == source }),
           let blendWrite = writes(
               rgb, typeNames: ["vec3", "float3"], before: output,
               tokens: tokens, body: main.bodyRange
           ).last,
           let expression = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
               after: blendWrite, in: tokens, body: main.bodyRange
           ), let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(expression),
           call.name == "ApplyBlending", call.arguments.count == 4,
           value.map(\.text) == call.arguments[3].map(\.text) {
            return true
        }
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

    static func writes(
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

    static func hasOtherMutation(
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

    static func noWholeSampleFlowsIntoRGB(
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
            if isSourceDeclaration { continue }
            // Another sampled carrier may exist only as a declared auxiliary
            // data source (`vec4 X = texSample2D(...)`): its variable must be
            // read exclusively per scalar component before the terminal
            // write, or it could smuggle whole-sample color into the RGB
            // flow. Inline whole samples stay rejected.
            guard index >= 2, tokens[index - 1].text == "=",
                  tokens[index - 2].kind == .identifier else {
                return false
            }
            let carrier = tokens[index - 2].text
            let uses = body.filter { $0 < output && tokens[$0].text == carrier }
            guard uses.dropFirst().allSatisfy({ use in
                use + 2 < output && tokens[use + 1].text == "."
                    && ["r", "g", "b", "a", "x", "y", "z", "w"]
                        .contains(tokens[use + 2].text)
            }) else { return false }
        }
        return true
    }

    static func matchingParenthesis(
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

    static func uniform(
        _ name: String, types: Set<String>, fragment: Unit
    ) -> Bool {
        let matches = fragment.declarations.filter { $0.name == name }
        return matches.count == 1 && matches[0].storage == .uniform
            && matches[0].arraySize == nil && types.contains(matches[0].typeName)
    }

    static func uniqueRGBADefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < boundary && tokens[index + 1].text == "="
                && rootLevel(index, tokens: tokens, body: body)
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func uniqueMemberAssignment(
        _ name: String,
        component: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> (index: Int, rhs: ArraySlice<Token>)? {
        let matches = body.filter { index in
            index > body.lowerBound && index + 3 < boundary
                && tokens[index].text == name
                && tokens[index + 1].text == "."
                && tokens[index + 2].text == component
                && tokens[index + 3].text == "="
                && rootLevel(index, tokens: tokens, body: body)
        }
        guard matches.count == 1, let index = matches.first,
              let rhs = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                  after: index + 2,
                  in: tokens,
                  body: body
              ) else { return nil }
        return (index, rhs)
    }

    static func rootLevel(
        _ index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        var depth = 0
        for cursor in body.lowerBound..<index {
            if tokens[cursor].text == "{" { depth += 1 }
            if tokens[cursor].text == "}" { depth -= 1 }
        }
        return depth == 1
    }

    static func totalTextureSampleCount(in fragment: Unit) -> Int {
        let names: Set<String> = [
            "texSample2D", "texture2D", "texSample2DLod", "texture2DLod",
            "texture", "textureLod", "texelFetch",
        ]
        return fragment.tokens.filter { names.contains($0.text) }.count
    }

    static func generatedRGBASeed(
        _ expression: ArraySlice<Token>,
        fragment: Unit,
        source: String,
        carrier: String
    ) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        guard let construction = Calls.call(expression),
              ["vec4", "float4", "CAST4"].contains(construction.name),
              construction.arguments.count == 2,
              uniformVector(construction.arguments[0], fragment: fragment),
              uniformScalar(construction.arguments[1], fragment: fragment),
              !expression.contains(where: {
                  $0.text == source || $0.text == carrier
                      || textureSampleNames.contains($0.text)
              }) else { return false }
        return true
    }

    static func uniformVector(
        _ expression: ArraySlice<Token>, fragment: Unit
    ) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        if let name = Calls.identifier(expression) {
            return uniform(name, types: ["vec3", "float3"], fragment: fragment)
        }
        let values = Array(Calls.strippingParentheses(expression))
        guard values.count == 3, values[1].text == ".",
              ["rgb", "xyz"].contains(values[2].text),
              values[0].kind == .identifier else { return false }
        return uniform(values[0].text, types: ["vec3", "float3"], fragment: fragment)
    }

    static func uniformScalar(
        _ expression: ArraySlice<Token>, fragment: Unit
    ) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        guard let name = Calls.identifier(expression) else { return false }
        return uniform(name, types: ["float"], fragment: fragment)
    }

    static let textureSampleNames: Set<String> = [
        "texSample2D", "texture2D", "texSample2DLod", "texture2DLod",
        "texture", "textureLod", "texelFetch",
    ]

    /// Returns the scalar tail after `carrier.a *` when the tail is a finite,
    /// statically scalar expression.  Returning normalized token text keeps
    /// the RGB and alpha weights comparable without accepting algebraic
    /// rewrites that the typed boundary cannot independently prove.
    static func carrierWeightedScalar(
        _ expression: ArraySlice<Token>,
        carrier: String,
        fragment: Unit,
        source: String,
        main: Unit.Function
    ) -> [String]? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let values = Array(Calls.strippingParentheses(expression))
        guard values.count >= 5,
              values[0].text == carrier,
              values[1].text == ".",
              values[2].text == "a",
              values[3].text == "*" else { return nil }
        let tail = Array(values.dropFirst(4))
        guard !tail.isEmpty,
              scalarExpression(
                  tail[tail.startIndex..<tail.endIndex],
                  fragment: fragment,
                  source: source,
                  carrier: carrier,
                  main: main
              ) else { return nil }
        return tail.map(\.text)
    }

    static func scalarValue(
        _ expression: ArraySlice<Token>,
        fragment: Unit,
        source: String,
        carrier: String,
        main: Unit.Function
    ) -> [String]? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let values = Array(Calls.strippingParentheses(expression))
        guard !values.isEmpty,
              scalarExpression(
                  values[values.startIndex..<values.endIndex],
                  fragment: fragment,
                  source: source,
                  carrier: carrier,
                  main: main
              ) else { return nil }
        return values.map(\.text)
    }

    static func scalarExpression(
        _ expression: ArraySlice<Token>,
        fragment: Unit,
        source: String,
        carrier: String,
        main: Unit.Function
    ) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let values = Array(Calls.strippingParentheses(expression))
        guard !values.isEmpty,
              !values.contains(where: { textureSampleNames.contains($0.text) }),
              !values.contains(where: { token in
                  let lower = token.text.lowercased()
                  return lower.contains("nan") || lower.contains("inf")
              }),
              !values.contains(where: { ["?", ":", "++", "--"].contains($0.text) })
        else { return false }

        let scalarTypes: Set<String> = ["float", "int", "uint", "bool"]
        var scalarNames = Set(
            fragment.declarations.filter {
                scalarTypes.contains($0.typeName) && $0.arraySize == nil
            }.map(\.name)
        )
        // Local scalar declarations in the active main body are safe values;
        // their own initializers are still constrained by the surrounding
        // source proof and cannot introduce a texture sample here.
        for index in main.bodyRange where index + 1 < main.bodyRange.upperBound {
            if scalarTypes.contains(valuesSafeToken(index, in: fragment.tokens)) {
                let next = fragment.tokens[index + 1]
                if next.kind == .identifier { scalarNames.insert(next.text) }
            }
        }

        let scalarBuiltins: Set<String> = [
            "abs", "atan", "atan2", "ceil", "clamp", "cos", "exp", "floor",
            "fract", "length", "log", "max", "min", "mix", "mod", "pow",
            "round", "saturate", "sign", "sin", "smoothstep", "sqrt", "step",
            "tan", "float", "int", "uint",
        ]
        let vectorTypes: Set<String> = [
            "vec2", "vec3", "vec4", "float2", "float3", "float4",
            "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
        ]
        var index = 0
        while index < values.count {
            let token = values[index]
            if token.kind == .number {
                guard let value = Double(token.text), value.isFinite else { return false }
                index += 1
                continue
            }
            guard token.kind == .identifier else {
                index += 1
                continue
            }
            let name = token.text
            if name == source || name == carrier { return false }
            if index + 1 < values.count, values[index + 1].text == "(" {
                guard scalarBuiltins.contains(name) else { return false }
                index += 1
                continue
            }
            if index + 2 < values.count, values[index + 1].text == "." {
                let component = values[index + 2].text
                guard ["r", "g", "b", "a", "x", "y", "z", "w"].contains(component),
                      fragment.declarations.contains(where: {
                          $0.name == name && !scalarTypes.contains($0.typeName)
                      }) else { return false }
                index += 3
                continue
            }
            guard scalarNames.contains(name), !vectorTypes.contains(name) else {
                return false
            }
            index += 1
        }
        return true
    }

    static func valuesSafeToken(_ index: Int, in tokens: [Token]) -> String {
        guard tokens.indices.contains(index) else { return "" }
        return tokens[index].text
    }

    /// Validates the optional one-branch carrier update and returns every
    /// carrier token accounted for by that branch.  A nil result means the
    /// control-flow shape is unsafe; an empty set means no branch is present.
}
