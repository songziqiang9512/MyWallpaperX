import Foundation

/// Proves one source-independent straight RGBA output whose RGB is generated
/// from authored uniforms/varyings and whose alpha is either one independent
/// scalar uniform or one statically bounded max accumulator. Product backends
/// may then premultiply the terminal value at the compositor boundary without
/// selecting by shader, effect, or asset identity.
nonisolated enum SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let rgbName: String
        let alphaName: String
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
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ), let construction =
                SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(expression),
              ["CAST4", "vec4", "float4"].contains(construction.name),
              construction.arguments.count == 2,
              let rgbName = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(construction.arguments[0]),
              let alphaName = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(construction.arguments[1]),
              rgbName != alphaName,
              let rgbDefinition = uniqueRGBDefinition(
                rgbName,
                before: output,
                tokens: tokens,
                body: main.bodyRange
              ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: rgbDefinition,
                    in: tokens,
                    body: main.bodyRange
                ), !initializer.contains(where: { $0.text == alphaName }),
              ((countUses(
                    rgbName,
                    expected: 2,
                    tokens: tokens,
                    range: rgbDefinition..<expression.endIndex
                ) && (directUniformAlpha(
                    alphaName,
                    fragment: fragment,
                    main: main
                ) || boundedMaxAccumulatorAlpha(
                    alphaName,
                    rgbName: rgbName,
                    before: output,
                    fragment: fragment,
                    main: main
                ))) || boundedMutableGeneratedCarriers(
                    rgbName: rgbName,
                    rgbDefinition: rgbDefinition,
                    rgbInitializer: initializer,
                    alphaName: alphaName,
                    output: output,
                    outputExpression: expression,
                    fragment: fragment,
                    main: main
                )), reachableFunctionsAreSourceIndependent(
                fragment,
                startingAt: main,
                alphaName: alphaName
              ) else { return nil }
        return Fact(rgbName: rgbName, alphaName: alphaName)
    }

    /// Admits a bounded procedural straight-RGBA carrier whose RGB is updated
    /// only by self-fed `mix` assignments and whose coverage is updated only
    /// by self-fed `max` assignments. A dead framebuffer sample may coexist in
    /// the active source, but it cannot participate in either carrier or in a
    /// control predicate. This is the common generated-shape form; it is
    /// intentionally narrower than arbitrary mutable shader dataflow.
    private static func boundedMutableGeneratedCarriers(
        rgbName: String,
        rgbDefinition: Int,
        rgbInitializer: ArraySlice<Token>,
        alphaName: String,
        output: Int,
        outputExpression: ArraySlice<Token>,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        // Generated procedural carriers may use bounded constant loops (for
        // example orbit/ring sampling).  The frontend has already accounted
        // for their work in `staticLoopWork`; reject only unbounded/runtime
        // loop forms and retain the existing conservative budget.
        guard fragment.staticLoopWork > 0,
              fragment.staticLoopWork <= 256,
              fragment.exactRuntimeLoopUniformArrays.isEmpty,
              !containsSampling(rgbInitializer),
              !rgbInitializer.contains(where: { $0.text == alphaName })
        else { return false }

        let alphaDefinitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index + 1 < output
                && tokens[index].text == alphaName
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
        }
        guard alphaDefinitions.count == 1,
              let alphaDefinition = alphaDefinitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  alphaDefinition, tokens: tokens, body: main.bodyRange
              ), let alphaInitializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: alphaDefinition,
                    in: tokens,
                    body: main.bodyRange
                ), isZero(alphaInitializer) else { return false }

        let rgbWrites = assignmentWrites(
            to: rgbName,
            after: rgbDefinition,
            before: output,
            tokens: tokens,
            body: main.bodyRange
        )
        let alphaWrites = assignmentWrites(
            to: alphaName,
            after: alphaDefinition,
            before: output,
            tokens: tokens,
            body: main.bodyRange
        )
        guard (1 ... 8).contains(rgbWrites.count),
              (1 ... 8).contains(alphaWrites.count) else { return false }

        var allowedRGBUses = Set([rgbDefinition])
        var allowedAlphaUses = Set([alphaDefinition])
        for write in rgbWrites {
            guard let value = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: write,
                    in: tokens,
                    body: main.bodyRange
                ), let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(value), call.name == "mix", call.arguments.count == 3,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.identifier(
                  call.arguments[0]
              ) == rgbName,
              value.filter({ $0.text == rgbName }).count == 1,
              !value.contains(where: { $0.text == alphaName }),
              !containsSampling(value) else { return false }
            allowedRGBUses.insert(write)
            allowedRGBUses.formUnion(value.indices.filter {
                tokens[$0].text == rgbName
            })
        }
        for write in alphaWrites {
            guard let value = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: write,
                    in: tokens,
                    body: main.bodyRange
                ), let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(value), call.name == "max", call.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.identifier(
                  call.arguments[0]
              ) == alphaName,
              value.filter({ $0.text == alphaName }).count == 1,
              !value.contains(where: { $0.text == rgbName }),
              !containsSampling(value) else { return false }
            allowedAlphaUses.insert(write)
            allowedAlphaUses.formUnion(value.indices.filter {
                tokens[$0].text == alphaName
            })
        }
        allowedRGBUses.formUnion(outputExpression.indices.filter {
            tokens[$0].text == rgbName
        })
        allowedAlphaUses.formUnion(outputExpression.indices.filter {
            tokens[$0].text == alphaName
        })
        return Set(main.bodyRange.filter { tokens[$0].text == rgbName })
                == allowedRGBUses
            && Set(main.bodyRange.filter { tokens[$0].text == alphaName })
                == allowedAlphaUses
    }

    private static func assignmentWrites(
        to name: String,
        after lowerBound: Int,
        before upperBound: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [Int] {
        body.filter { index in
            index > lowerBound && index + 1 < upperBound
                && tokens[index].text == name
                && tokens[index + 1].text == "="
        }
    }

    private static func containsSampling(
        _ expression: ArraySlice<Token>
    ) -> Bool {
        expression.contains {
            [
                "texSample2D", "texture2D", "texSample2DLod",
                "texture2DLod", "texture", "textureLod",
            ].contains($0.text)
        }
    }

    private static func directUniformAlpha(
        _ name: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        fragment.declarations.contains(where: {
            $0.storage == .uniform && $0.typeName == "float"
                && $0.arraySize == nil && $0.name == name
        }) && countUses(
            name,
            expected: 1,
            tokens: fragment.tokens,
            range: main.bodyRange
        )
    }

    /// Conservatively admits a generated coverage signal. The syntax owner has
    /// already proven every loop is statically bounded; this color proof further
    /// requires one loop, one root-local zero seed, and one unconditional
    /// `alpha = max(alpha, candidate)` update inside that loop.
    private static func boundedMaxAccumulatorAlpha(
        _ name: String,
        rgbName: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard let rgbUniform = directUniformRGB(
            rgbName,
            before: output,
            fragment: fragment,
            main: main
        ) else { return false }
        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index + 1 < output
                && tokens[index].text == name
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1, let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition, tokens: tokens, body: main.bodyRange
              ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition,
                    in: tokens,
                    body: main.bodyRange
                ), isZero(initializer),
              countUses(
                  name,
                  expected: 4,
                  tokens: tokens,
                  range: main.bodyRange
              ), fragment.exactRuntimeLoopUniformArrays.isEmpty,
              fragment.staticLoopWork > 0,
              fragment.staticLoopWork <= 256 else { return false }

        let loopMarkers = main.bodyRange.filter { tokens[$0].text == "for" }
        guard loopMarkers.count == 1,
              tokens.indices.filter({ tokens[$0].text == "for" }) == loopMarkers,
              let loopBody = loopBody(
                  at: loopMarkers[0],
                  within: main.bodyRange,
                  tokens: tokens
              ), definition < loopMarkers[0], loopBody.upperBound <= output,
              !loopBody.contains(where: {
                  ["break", "continue"].contains(tokens[$0].text)
              }) else {
            return false
        }

        let writes = main.bodyRange.filter { index in
            index + 1 < main.bodyRange.upperBound
                && tokens[index].text == name
                && tokens[index + 1].text == "="
        }
        guard writes.count == 2, writes.first == definition,
              let update = writes.last,
              loopBody.contains(update),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  update, tokens: tokens, body: loopBody
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: update,
                    in: tokens,
                    body: loopBody
                ), let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(expression), call.name == "max",
              call.arguments.count == 2,
              SceneAuthoredShaderConditionalStraightUnionAnalyzer.identifier(
                  call.arguments[0]
              ) == name,
              let candidate = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[1]),
              candidate != name, candidate != rgbName else { return false }

        let candidateDefinitions = loopBody.filter { index in
            index > loopBody.lowerBound && index + 1 < update
                && tokens[index].text == candidate
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
        }
        guard candidateDefinitions.count == 1,
              let candidateDefinition = candidateDefinitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  candidateDefinition, tokens: tokens, body: loopBody
              ), let candidateExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: candidateDefinition,
                    in: tokens,
                    body: loopBody
                ), !candidateExpression.contains(where: {
                    [name, rgbName, rgbUniform].contains($0.text)
                }), countUses(
                    candidate,
                    expected: 2,
                    tokens: tokens,
                    range: loopBody
                ) else { return false }
        return true
    }

    private static func directUniformRGB(
        _ name: String,
        before output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> String? {
        let tokens = fragment.tokens
        guard let definition = uniqueRGBDefinition(
            name,
            before: output,
            tokens: tokens,
            body: main.bodyRange
        ), let initializer = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(
                after: definition,
                in: tokens,
                body: main.bodyRange
            ), let uniform = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(initializer) else { return nil }
        return fragment.declarations.contains {
            $0.storage == .uniform && $0.arraySize == nil
                && ["vec3", "float3"].contains($0.typeName)
                && $0.name == uniform
        } ? uniform : nil
    }

    private static func isZero(
        _ expression: ArraySlice<Token>
    ) -> Bool {
        expression.count == 1
            && expression.first?.kind == .number
            && Double(expression.first?.text ?? "") == 0
    }

    private static func loopBody(
        at marker: Int,
        within functionBody: Range<Int>,
        tokens: [Token]
    ) -> Range<Int>? {
        guard marker + 1 < functionBody.upperBound,
              tokens[marker + 1].text == "(",
              let headerClose = matchingDelimiter(
                  at: marker + 1,
                  tokens: tokens
              ), headerClose + 1 < functionBody.upperBound,
              tokens[headerClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  at: headerClose + 1,
                  tokens: tokens
              ), bodyClose < functionBody.upperBound else { return nil }
        return (headerClose + 1)..<(bodyClose + 1)
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

    private static func uniqueRGBDefinition(
        _ name: String,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec3", "float3"].contains(tokens[index - 1].text)
                && index + 1 < boundary && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let match = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                match, tokens: tokens, body: body
              ) else { return nil }
        return match
    }

    private static func countUses(
        _ name: String,
        expected: Int,
        tokens: [Token],
        range: some Sequence<Int>
    ) -> Bool {
        range.filter { tokens[$0].text == name }.count == expected
    }

    private static func reachableFunctionsAreSourceIndependent(
        _ fragment: Unit,
        startingAt main: Unit.Function,
        alphaName: String
    ) -> Bool {
        let functions = Dictionary(uniqueKeysWithValues: fragment.functions.map {
            ($0.name, $0)
        })
        var pending = [main.name]
        var visited = Set<String>()
        while let name = pending.popLast() {
            guard visited.insert(name).inserted,
                  let function = functions[name] else { continue }
            let body = fragment.tokens[function.bodyRange]
            guard !body.contains(where: { token in
                token.text == "gl_FragData"
            }), (name != main.name || deadLocalSamplesAreIsolated(
                fragment,
                function: function
            )), (name == main.name || !containsSampling(body)),
              name == main.name || !body.contains(where: {
                $0.text == "gl_FragColor" || $0.text == alphaName
            }) else { return false }
            for index in function.bodyRange where index + 1 < function.bodyRange.upperBound {
                let candidate = fragment.tokens[index]
                if candidate.kind == .identifier,
                   fragment.tokens[index + 1].text == "(",
                   functions[candidate.text] != nil {
                    pending.append(candidate.text)
                }
            }
        }
        return true
    }

    /// Allows compiler-visible framebuffer declarations that are sampled into
    /// one unused local. Any direct sample, reused sample result, or sample in
    /// a helper remains rejected.
    private static func deadLocalSamplesAreIsolated(
        _ fragment: Unit,
        function: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let sampleIndices = function.bodyRange.filter {
            containsSampling(tokens[$0...$0])
        }
        for sample in sampleIndices {
            var cursor = sample
            while cursor > function.bodyRange.lowerBound,
                  ![";", "{"].contains(tokens[cursor - 1].text) {
                cursor -= 1
            }
            let statement = cursor..<min(
                function.bodyRange.upperBound,
                (sample..<function.bodyRange.upperBound).first(where: {
                    tokens[$0].text == ";"
                }).map { $0 + 1 } ?? function.bodyRange.upperBound
            )
            guard statement.count >= 5,
                  tokens[statement.lowerBound].text == "float"
                    || ["vec2", "vec3", "vec4", "float2", "float3", "float4"]
                        .contains(tokens[statement.lowerBound].text),
                  tokens[statement.lowerBound + 1].kind == .identifier,
                  tokens[statement.lowerBound + 2].text == "=",
                  sample > statement.lowerBound + 2 else { return false }
            let local = tokens[statement.lowerBound + 1].text
            guard function.bodyRange.filter({ tokens[$0].text == local }).count == 1
            else { return false }
        }
        return true
    }
}
