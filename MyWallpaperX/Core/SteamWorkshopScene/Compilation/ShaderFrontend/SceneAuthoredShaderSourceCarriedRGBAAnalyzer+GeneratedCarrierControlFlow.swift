import Foundation

nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    static func generatedCarrierControlFlowUses(
        carrier: String,
        source: String,
        carrierDefinition: Int,
        rgbIndex: Int,
        alphaIndex: Int,
        output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Set<Int>? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let tokens = fragment.tokens
        let body = main.bodyRange
        let rootIfs = body.filter {
            tokens[$0].text == "if"
                && braceDepthBefore($0, tokens: tokens, body: body) == 1
        }
        guard rootIfs.count <= 1 else { return nil }
        let controlWords: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "return",
            "discard", "break", "continue",
        ]
        let controls = body.filter { controlWords.contains(tokens[$0].text) }
        guard controls == rootIfs else { return nil }
        guard let ifIndex = rootIfs.first else { return [] }
        guard ifIndex + 1 < body.upperBound,
              tokens[ifIndex + 1].text == "(",
              let conditionClose = generatedCarrierMatchingDelimiter(
                  at: ifIndex + 1, tokens: tokens
              ),
              conditionClose + 1 < body.upperBound,
              tokens[conditionClose + 1].text == "{",
              let branchClose = generatedCarrierMatchingDelimiter(
                  at: conditionClose + 1, tokens: tokens
              ),
              branchClose < body.upperBound,
              branchClose < rgbIndex,
              branchClose + 1 >= body.upperBound
                  || tokens[branchClose + 1].text != "else",
              constantTrue(
                  tokens[(ifIndex + 2)..<conditionClose]
              ) else { return nil }
        let branchBody = (conditionClose + 2)..<branchClose
        guard !branchBody.contains(where: { tokens[$0].text == source }),
              !branchBody.contains(where: {
                  textureSampleNames.contains(tokens[$0].text)
              }),
              !branchBody.contains(where: { tokens[$0].text == "gl_FragColor" }),
              branchBody.allSatisfy({ index in
                  guard tokens[index].kind == .identifier,
                        index + 1 < branchBody.upperBound,
                        tokens[index + 1].text == "(" else { return true }
                  return generatedPureCallNames.contains(tokens[index].text)
              }) else { return nil }

        let wholeWrites = branchBody.filter {
            tokens[$0].text == carrier && $0 + 1 < branchBody.upperBound
                && tokens[$0 + 1].text == "="
                && ($0 == branchBody.lowerBound || tokens[$0 - 1].text != ".")
        }
        guard wholeWrites.count == 1, let write = wholeWrites.first,
              let rhs = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                  after: write, in: tokens, body: body
              ), let update = Calls.call(rhs),
              ["mix", "lerp"].contains(update.name),
              update.arguments.count == 3,
              Calls.identifier(update.arguments[0]) == carrier,
              generatedRGBASeed(
                  update.arguments[1],
                  fragment: fragment,
                  source: source,
                  carrier: carrier
              ),
              scalarValue(
                  update.arguments[2],
                  fragment: fragment,
                  source: source,
                  carrier: carrier,
                  main: main
              ) != nil else { return nil }
        guard !branchBody.contains(where: { index in
            tokens[index].text == carrier && index + 3 < branchBody.upperBound
                && tokens[index + 1].text == "."
                && ["rgb", "a", "xyz", "w"].contains(tokens[index + 2].text)
                && ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text)
        }) else { return nil }
        var uses = Set([write])
        uses.formUnion(rhs.indices.filter { tokens[$0].text == carrier })
        return uses
    }

    static let generatedPureCallNames: Set<String> = [
        "abs", "atan", "atan2", "ceil", "clamp", "cos", "dot", "exp", "floor",
        "fract", "length", "log", "max", "min", "mix", "mod", "normalize",
        "pow", "round", "saturate", "sign", "sin", "smoothstep", "sqrt", "step",
        "tan", "float", "int", "uint", "vec2", "vec3", "vec4", "float2",
        "float3", "float4", "CAST2", "CAST3", "CAST4",
    ]

    static func braceDepthBefore(
        _ index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int {
        var depth = 0
        for cursor in body.lowerBound..<index {
            if tokens[cursor].text == "{" { depth += 1 }
            if tokens[cursor].text == "}" { depth -= 1 }
        }
        return depth
    }

    static func constantTrue(_ expression: ArraySlice<Token>) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let values = Array(Calls.strippingParentheses(expression))
        if values.count == 1 { return values[0].text == "true" }
        guard values.count == 3,
              let lhs = Double(values[0].text), lhs.isFinite,
              let rhs = Double(values[2].text), rhs.isFinite else { return false }
        switch values[1].text {
        case ">": return lhs > rhs
        case "<": return lhs < rhs
        case ">=": return lhs >= rhs
        case "<=": return lhs <= rhs
        case "==": return lhs == rhs
        case "!=": return lhs != rhs
        default: return false
        }
    }

    static func generatedCarrierMatchingDelimiter(
        at open: Int,
        tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(open),
              ["(", "{"].contains(tokens[open].text) else { return nil }
        let opening = tokens[open].text
        let closing = opening == "(" ? ")" : "}"
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == opening { depth += 1 }
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    static func validatedTransparencyHelper(
        _ fragment: Unit
    ) -> SourceCarriedTransfer? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let helpers = fragment.functions.filter { $0.name == "BlendTransparency" }
        guard helpers.count == 1, let helper = helpers.first,
              helper.returnType == "float",
              let parameters = Calls.commaSeparated(
                  fragment.tokens[helper.parameterRange]
              ), parameters.count == 3 else { return nil }
        let normalized = parameters.map {
            $0.filter { !["const", "in"].contains($0.text) }
        }
        guard normalized.allSatisfy({
                  $0.count == 2 && $0[0].text == "float"
                      && $0[1].kind == .identifier
              }) else { return nil }
        let names = normalized.map { $0[1].text }
        guard Set(names).count == 3 else { return nil }
        let tokens = fragment.tokens
        let body = helper.bodyRange
        let controls: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "discard",
            "break", "continue",
        ]
        guard !body.contains(where: { controls.contains(tokens[$0].text) }) else {
            return nil
        }
        let returns = body.filter { tokens[$0].text == "return" }
        guard returns.count == 1, let returnIndex = returns.first,
              let returned = returnExpression(
                  after: returnIndex, tokens: tokens, body: body
              ), let call = Calls.call(returned),
              ["mix", "lerp"].contains(call.name), call.arguments.count == 3,
              Calls.identifier(call.arguments[0]) == names[0],
              Calls.identifier(call.arguments[2]) == names[2] else { return nil }

        let localDefinitions = body.filter { index in
            index > body.lowerBound && index + 1 < returnIndex
                && tokens[index - 1].text == "float"
                && tokens[index].kind == .identifier
                && tokens[index + 1].text == "="
        }
        guard localDefinitions.count <= 1 else { return nil }
        let second = Calls.identifier(call.arguments[1])
        if second == names[1] {
            // A direct replacement/mix helper is a straight-alpha contract.
            guard localDefinitions.isEmpty else { return nil }
            return .straight
        }
        guard let local = second,
              let definition = localDefinitions.first,
              tokens[definition].text == local,
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: definition, in: tokens, body: body),
              let seed = Calls.identifier(initializer),
              seed == names[0] || seed == names[1],
              local != names[0], local != names[1], local != names[2] else {
            return nil
        }
        // Only a source-alpha copy is preserving.  A blend-alpha copy is a
        // proven straight transfer and therefore must not be routed through
        // the preserving classification.
        return seed == names[0] ? .preserving : .straight
    }

    static func returnExpression(
        after returnIndex: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> ArraySlice<Token>? {
        let start = returnIndex + 1
        guard start < body.upperBound else { return nil }
        var parentheses = 0
        var brackets = 0
        for index in start..<body.upperBound {
            switch tokens[index].text {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case ";" where parentheses == 0 && brackets == 0:
                return start < index ? tokens[start..<index] : nil
            default: break
            }
            guard parentheses >= 0, brackets >= 0 else { return nil }
        }
        return nil
    }

    static func exactGeneratedCarrierUses(
        carrier: String,
        source: String,
        sourceDefinition: Int,
        carrierDefinition: Int,
        rgb: (index: Int, rhs: ArraySlice<Token>),
        alpha: (index: Int, rhs: ArraySlice<Token>),
        output: Int,
        fragment: Unit,
        main: Unit.Function,
        controlUses: Set<Int>
    ) -> Bool {
        let tokens = fragment.tokens
        let sourceUses = Set(main.bodyRange.filter {
            $0 < output && tokens[$0].text == source
        })
        var allowedSource = Set([sourceDefinition])
        allowedSource.formUnion(rgb.rhs.indices.filter { tokens[$0].text == source })
        allowedSource.formUnion(alpha.rhs.indices.filter { tokens[$0].text == source })
        guard sourceUses == allowedSource, sourceUses.count == 3 else { return false }

        let carrierUses = Set(main.bodyRange.filter {
            $0 < output && tokens[$0].text == carrier
        })
        var allowedCarrier = Set([carrierDefinition])
        allowedCarrier.formUnion(controlUses)
        allowedCarrier.insert(rgb.index)
        allowedCarrier.insert(alpha.index)
        allowedCarrier.formUnion(rgb.rhs.indices.filter { tokens[$0].text == carrier })
        allowedCarrier.formUnion(alpha.rhs.indices.filter { tokens[$0].text == carrier })
        guard carrierUses == allowedCarrier else { return false }

        // The only output use after the assignment is the complete carrier;
        // member/alias escapes are therefore already excluded by the exact
        // pre-output use set above.
        guard output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              let terminal = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                  .identifier(terminal) == carrier else { return false }
        return true
    }
}
