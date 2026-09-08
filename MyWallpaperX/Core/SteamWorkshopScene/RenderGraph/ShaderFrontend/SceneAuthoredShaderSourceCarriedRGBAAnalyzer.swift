import Foundation

/// Proves the remaining source-backed straight RGBA shapes after the exact
/// analyzers decline them. The proof separates one color source from auxiliary
/// scalar/data samplers and never selects by effect or shader identity.
nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    enum SourceCarriedTransfer: Equatable {
        case preserving
        case straight
    }

    struct SourceCarriedFact: Equatable {
        let sourceSlot: Int
        let transfer: SourceCarriedTransfer

        var colorTransfer: SceneShaderColorTransfer {
            switch transfer {
            case .preserving:
                .straightAlphaPreserving(textureSlot: sourceSlot)
            case .straight:
                .straightAlpha(textureSlot: sourceSlot)
            }
        }
    }

    static func analyzeSourceCarried(
        fragmentSource source: String
    ) -> SourceCarriedFact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source, stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyzeSourceCarried(fragment)
    }

    static func analyzeSourceCarried(_ fragment: Unit) -> SourceCarriedFact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1, let output = outputs.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let sampled = sampledColorLocals(
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return nil }

        if let carrier = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(expression), let slot = sampled[carrier],
           carrierPreservesAlpha(
            carrier, before: output, tokens: tokens, body: main.bodyRange
           ), auxiliaryColorsRemainScalarData(
            excluding: slot, sampled: sampled,
            before: output, tokens: tokens, body: main.bodyRange
           ) {
            return .init(sourceSlot: slot, transfer: .preserving)
        }

        guard let outputCall = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .call(expression),
              ["CAST4", "vec4", "float4"].contains(outputCall.name),
              outputCall.arguments.count == 2 else { return nil }
        return proceduralSourceRGBA(
            outputCall.arguments, sampled: sampled, output: output,
            fragment: fragment, main: main
        ) ?? conditionalGeneratedRGBA(
            outputCall.arguments, sampled: sampled, output: output,
            fragment: fragment, main: main
        ) ?? uniformSeededBlendRGBA(
            outputCall.arguments, sampled: sampled, output: output,
            fragment: fragment, main: main
        )
    }

    /// A sampled straight RGB/coverage pair may be passed to a procedural
    /// helper which only mixes RGB and unions coverage. All uses of both
    /// carriers are accounted for, including helper parameters and zero resets.
    private static func proceduralSourceRGBA(
        _ arguments: [ArraySlice<Token>], sampled: [String: Int], output: Int,
        fragment: Unit, main: Unit.Function
    ) -> SourceCarriedFact? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let tokens = fragment.tokens
        guard sampled.count == 1, let source = sampled.first,
              let rgb = Calls.identifier(arguments[0]),
              let alpha = Calls.identifier(arguments[1]), rgb != alpha,
              // Syntax admission owns both per-loop and expanded call-work
              // budgets; expanded work is not a single loop iteration count.
              fragment.staticLoopWork > 0,
              fragment.exactRuntimeLoopUniformArrays.isEmpty,
              !tokens.contains(where: { ["gl_FragData", "discard"].contains($0.text) })
        else { return nil }
        var allowed = Set<Int>()
        var seeds: [String: Int] = [:]
        for (name, type, member) in [(rgb, "vec3", "rgb"), (alpha, "float", "a")] {
            let definitions = main.bodyRange.filter {
                $0 > main.bodyRange.lowerBound && $0 + 1 < output
                    && tokens[$0].text == name && tokens[$0 - 1].text == type
                    && tokens[$0 + 1].text == "="
            }
            guard definitions.count == 1, let index = definitions.first,
                  SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                    index, tokens: tokens, body: main.bodyRange
                  ), let rhs = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                    after: index, in: tokens, body: main.bodyRange
                  ), Calls.member(rhs, name: source.key, component: member)
            else { return nil }
            seeds[name] = index
            allowed.insert(index)
        }
        guard let lastSeed = seeds.values.max(),
              main.bodyRange.filter({ tokens[$0].text == source.key }).count == 3,
              tokens.indices.filter({
                ["texSample2D", "texture2D", "texture", "textureLod", "texture2DLod", "texSample2DLod"]
                    .contains(tokens[$0].text)
              }).count == 1 else { return nil }
        var helperCalls = 0
        for index in (lastSeed + 1)..<output {
            if [rgb, alpha].contains(tokens[index].text),
               index + 1 < output, tokens[index + 1].text == "=" {
                guard let rhs = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                    after: index, in: tokens, body: main.bodyRange
                ), proceduralZero(rhs, vector: tokens[index].text == rgb)
                else { return nil }
                allowed.insert(index)
            }
            guard tokens[index].kind == .identifier, index + 1 < output,
                  tokens[index + 1].text == "(",
                  let helper = fragment.functions.first(where: { $0.name == tokens[index].text }),
                  let close = proceduralClose(index + 1, tokens: tokens), close < output,
                  let call = Calls.call(tokens[index...close]),
                  call.arguments.contains(where: { arg in
                    arg.contains { $0.text == rgb || $0.text == alpha }
                  }) else { continue }
            guard tokens[index - 1].text == ";" || tokens[index - 1].text == "{",
                  tokens[close + 1].text == ";",
                  proceduralHelper(helper, arguments: call.arguments,
                    rgb: rgb, alpha: alpha, fragment: fragment) else { return nil }
            helperCalls += 1
            allowed.formUnion((index...close).filter {
                tokens[$0].text == rgb || tokens[$0].text == alpha
            })
        }
        guard let terminal = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
            after: output, in: tokens, body: main.bodyRange
        ) else { return nil }
        allowed.formUnion(terminal.indices.filter {
            tokens[$0].text == rgb || tokens[$0].text == alpha
        })
        guard (1...8).contains(helperCalls),
              Set(main.bodyRange.filter {
                tokens[$0].text == rgb || tokens[$0].text == alpha
              }) == allowed else { return nil }
        return .init(sourceSlot: source.value, transfer: .straight)
    }

    private static func proceduralHelper(
        _ helper: Unit.Function, arguments: [ArraySlice<Token>],
        rgb: String, alpha: String, fragment: Unit
    ) -> Bool {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let tokens = fragment.tokens
        var parameters: [[Token]] = [[]]
        for token in tokens[helper.parameterRange] {
            if token.text == "," { parameters.append([]) }
            else { parameters[parameters.count - 1].append(token) }
        }
        guard parameters.count == arguments.count else { return false }
        var carriers: [String: String] = [:]
        for (parameter, argument) in zip(parameters, arguments) {
            if let name = Calls.identifier(argument), name == rgb || name == alpha {
                guard parameter.count == 3, parameter[0].text == "inout",
                      parameter[1].text == (name == rgb ? "vec3" : "float"),
                      parameter[2].kind == .identifier, carriers[name] == nil
                else { return false }
                carriers[name] = parameter[2].text
            } else if parameter.contains(where: { ["out", "inout"].contains($0.text) }) {
                return false
            }
        }
        guard let color = carriers[rgb], let coverage = carriers[alpha], color != coverage
        else { return false }
        for (name, operation, count) in [(color, "mix", 3), (coverage, "max", 2)] {
            let writes = helper.bodyRange.filter {
                $0 + 1 < helper.bodyRange.upperBound && tokens[$0].text == name
                    && tokens[$0 + 1].text == "="
            }
            guard writes.count == 1, let write = writes.first,
                  let rhs = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                    after: write, in: tokens, body: helper.bodyRange
                  ), let call = Calls.call(rhs), call.name == operation,
                  call.arguments.count == count,
                  Calls.identifier(call.arguments[0]) == name,
                  !call.arguments.dropFirst().contains(where: { arg in
                    arg.contains { $0.text == color || $0.text == coverage }
                  }), Set(helper.bodyRange.filter { tokens[$0].text == name })
                    == Set([write] + rhs.indices.filter { tokens[$0].text == name })
            else { return false }
        }
        // No shadowed arithmetic builtins or secondary writes to either
        // carrier through calls/aliases can escape the exact-use proof above.
        return !fragment.functions.contains { ["mix", "max"].contains($0.name) }
    }

    private static func proceduralZero(_ value: ArraySlice<Token>, vector: Bool) -> Bool {
        if !vector { return value.count == 1 && Double(value.first!.text) == 0 }
        guard let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(value),
              call.name == "vec3", call.arguments.count == 1 || call.arguments.count == 3
        else { return false }
        return call.arguments.allSatisfy { $0.count == 1 && Double($0.first!.text) == 0 }
    }

    private static func proceduralClose(_ open: Int, tokens: [Token]) -> Int? {
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

    private static func sampledColorLocals(
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [String: Int]? {
        var resolved: [String: Int] = [:]
        for index in body where index > body.lowerBound && index < boundary {
            guard index + 1 < boundary,
                  ["vec4", "float4"].contains(tokens[index - 1].text),
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "=",
                  let initializer = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: index, in: tokens, body: body)
            else { continue }
            if let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer) {
                resolved[tokens[index].text] = slot
            } else if let alias = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(initializer), let slot = resolved[alias] {
                resolved[tokens[index].text] = slot
            }
        }
        return resolved.isEmpty ? nil : resolved
    }

    private static func carrierPreservesAlpha(
        _ carrier: String,
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let definitions = body.filter { index in
            index > body.lowerBound && index + 1 < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1, let definition = definitions.first else {
            return false
        }
        for index in (definition + 1)..<output where tokens[index].text == carrier {
            if index + 1 < output,
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 1].text) {
                return false
            }
            if index + 3 < output, tokens[index + 1].text == ".",
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text),
               !["rgb", "xyz"].contains(tokens[index + 2].text) {
                return false
            }
        }
        return true
    }

    private static func auxiliaryColorsRemainScalarData(
        excluding sourceSlot: Int,
        sampled: [String: Int],
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        for (name, slot) in sampled where slot != sourceSlot {
            let uses = body.filter { $0 < output && tokens[$0].text == name }
            guard uses.dropFirst().allSatisfy({ index in
                index + 2 < output && tokens[index + 1].text == "."
                    && ["r", "g", "b", "a", "x", "y", "z", "w"]
                        .contains(tokens[index + 2].text)
            }) else { return false }
        }
        return true
    }

}
