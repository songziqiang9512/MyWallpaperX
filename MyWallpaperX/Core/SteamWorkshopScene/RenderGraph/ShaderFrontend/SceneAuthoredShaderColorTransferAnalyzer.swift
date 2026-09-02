import Foundation

/// Derives a deliberately small color transfer fact from the same active
/// syntax unit that the authored frontend emits. It does not inspect paths,
/// effect identities, render state, or shader fingerprints.
nonisolated enum SceneAuthoredShaderColorTransferAnalyzer {
    /// Derives the shared material color contract directly from one prepared
    /// authored fragment source. Compiler backends may translate more syntax,
    /// but they may not contradict a fact proven here.
    static func analyze(
        fragmentSource source: String,
        provenRuntimeLoopBounds: [
            String: SceneAuthoredShaderExactScalarFact
        ] = [:]
    ) -> SceneShaderColorTransfer {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return .unresolved
        }
        return analyze(fragment)
    }

    /// Returns the source slot only when the prepared fragment proves the
    /// bounded conditional straight-color union. This provenance is narrower
    /// than the resulting `.straightAlpha` color representation and can own a
    /// route without broadening every straight-alpha shader.
    static func conditionalStraightUnionSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let outputUses = fragment.tokens.indices.filter {
            fragment.tokens[$0].text == "gl_FragColor"
        }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    /// Returns the source slot only when one sampled color is preserved in RGB
    /// and receives exactly one unconditional alpha mutation before output or
    /// directly on the root output.
    /// This provenance is deliberately narrower than `.straightAlpha`: it can
    /// own a route without upgrading conditional, reconstructed, or auxiliary
    /// sampler forms that merely share the same compositor representation.
    static func singleSamplerAlphaMutationSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return nil
        }
        return mutatedStraightAlphaSlot(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) ?? SceneAuthoredShaderAlphaAttenuationAnalyzer
            .directOutputFact(fragment)?.sourceSlot
    }

    /// Returns the source slot only for a bounded same-slot channel
    /// reconstruction: either the existing composed RGB proof or a base sample
    /// with one or more distinct shifted RGB component writes. Both shapes
    /// preserve the base alpha and reject hidden samples and control flow, so
    /// the fact remains independent of effect identity or variable spelling.
    static func sameSlotChannelReconstructionSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return nil
        }
        return SceneAuthoredShaderSameSlotChannelReconstructionAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    /// Returns the source slot only for the linear carrier variant whose RGB
    /// combines same-slot projected channel reads with one same-slot blend.
    static func sameSlotCarrierBlendSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return nil
        }
        return SceneAuthoredShaderSameSlotCarrierBlendAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    /// Returns the carrier and direct scalar-data slots only when RGB remains
    /// unchanged and one bounded scalar graph multiplies the carrier alpha.
    static func straightRGBScalarAlphaFact(
        fragmentSource source: String
    ) -> SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.Fact? {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return nil
        }
        return SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    /// Returns the carrier and scalar-data slots only when one final scalar
    /// drives both an authored RGB blend and multiplicative carrier alpha.
    static func rgbBlendScalarAlphaFact(
        fragmentSource source: String
    ) -> SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact? {
        guard let (fragment, _, _) = analyzedMain(source) else { return nil }
        return SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.analyze(fragment)
    }

    /// Returns source-proven slots for the two bounded blend dataflows that
    /// need narrower route authority than their resulting color contract.
    static func blendSourceSlots(
        fragmentSource source: String
    ) -> (
        auxiliaryRGB: Int?,
        overlayAlpha: (source: Int, overlay: Int)?,
        overlayAlphaPreserving: (source: Int, overlay: Int)?
    ) {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return (nil, nil, nil)
        }
        return (
            SceneAuthoredShaderAuxiliaryRGBMixAnalyzer.analyze(
                outputUses: outputUses, fragment: fragment, main: main
            ),
            SceneAuthoredShaderOverlayAlphaBlendAnalyzer.analyze(
                outputUses: outputUses, fragment: fragment, main: main
            ),
            SceneAuthoredShaderOverlayAlphaBlendAnalyzer.analyzeAlphaPreserving(
                outputUses: outputUses, fragment: fragment, main: main
            )
        )
    }

    static func analyze(
        _ fragment: SceneAuthoredShaderSyntaxUnit
    ) -> SceneShaderColorTransfer {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return .unresolved
        }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        if outputUses.count != 1,
           let transfer = SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return transfer
        }
        if let slot = SceneAuthoredShaderConditionalAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderConditionalStraightUnionAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotMixAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotMixAnalyzer.analyzeAliasReplacement(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let slots = SceneAuthoredShaderOverlayAlphaBlendAnalyzer
            .analyzeAlphaPreserving(
                outputUses: outputUses,
                fragment: fragment,
                main: main
            ) {
            return .straightAlphaPreserving(textureSlot: slots.source)
        }
        if let slots = SceneAuthoredShaderColorMixGraphAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            if slots.count == 1, let slot = slots.first {
                return .passthrough(textureSlot: slot)
            }
            return .interpolatedColor(textureSlots: slots)
        }
        if let slot = SceneAuthoredShaderNormalizedSampleSumAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .passthrough(textureSlot: slot)
        }
        if let fact = SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
            fragment
        ) {
            return .straightAlpha(textureSlot: fact.textureSlot)
        }
        if let fact = SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer
            .analyze(fragment) {
            return .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.analyze(
            fragment
        ) {
            return fact.terminalTransform == .saturateRGBA
                ? .straightAlphaUNorm(textureSlot: fact.sourceSlot)
                : .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer.analyze(
            fragment
        ) {
            return .straightAlphaPreserving(textureSlot: fact.blurredSlot)
        }
        if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
            fragment
        ) {
            return .straightAlphaPreserving(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(fragment) {
            return .straightAlphaPreserving(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer
            .analyze(fragment) {
            return fact.preservesSnapshotAlpha
                ? .straightAlphaPreserving(textureSlot: fact.sourceSlot)
                : .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
            fragment
        ) {
            return .straightAlphaPreserving(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
            fragment
        ) {
            switch fact.alphaOutput {
            case .preserved:
                return .straightAlphaPreserving(textureSlot: fact.sourceSlot)
            case .opaque:
                return .opaque
            }
        }
        if let fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
            fragment
        ) {
            return .straightAlphaPreserving(
                textureSlot: fact.alphaCarrierSlot
            )
        }
        if let fact =
            SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer
                .analyze(fragment) {
            return .opaqueFromStraightColor(textureSlot: fact.sourceSlot)
        }
        if let slot = SceneAuthoredShaderOpaqueInputAlphaAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer
            .directOutputFact(fragment) {
            return .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderStraightColorOverlayAnalyzer.analyze(
            fragment
        ) {
            return .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let slot = SceneAuthoredShaderUniformRGBMixAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderSameSlotChannelReconstructionAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(
                outputUses: outputUses,
                fragment: fragment,
                main: main
            ) {
            return .straightAlphaPreserving(textureSlot: slot.sourceSlot)
        }
        if let fact = SceneAuthoredShaderGeneratedUnderlayBlendAnalyzer.analyze(
            fragment
        ) {
            return .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let fact = SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(
            fragment
        ) {
            return .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyze(fragment) != nil {
            return .generatedStraightAlpha
        }
        if SceneAuthoredShaderPremultipliedOutputAnalyzer.analyze(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .premultipliedAlpha
        }
        if isOpaqueCarrierOutput(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return .opaque
        }
        guard outputUses.count == 1,
              let assignment = outputUses.first,
              assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              main.bodyRange.contains(assignment),
              isUnconditionalWrite(assignment, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) else {
            return .unresolved
        }
        if let slot = directTextureSampleSlot(expression) {
            return .passthrough(textureSlot: slot)
        }
        if let slot = preservedAlphaRGBMutationSlot(
            expression,
            outputAssignment: assignment,
            tokens: tokens,
            body: main.bodyRange
        ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let slot = straightAlphaSlot(
            expression,
            outputAssignment: assignment,
            tokens: tokens,
            body: main.bodyRange
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = mutatedStraightAlphaSlot(
            expression,
            outputAssignment: assignment,
            tokens: tokens,
            body: main.bodyRange
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let slot = SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlpha(textureSlot: slot)
        }
        if let fact = SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return fact.terminalTransform == .saturateRGBA
                ? .straightAlphaUNorm(textureSlot: fact.sourceSlot)
                : .straightAlpha(textureSlot: fact.sourceSlot)
        }
        if let slot = SceneAuthoredShaderStraightWholeColorFilterAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return .straightAlphaUNorm(textureSlot: slot)
        }
        if let transfer = SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return transfer
        }
        if let fact = SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyzeSourceCarried(fragment) {
            return fact.colorTransfer
        }
        return isOpaqueVectorConstruction(expression) ? .opaque : .unresolved
    }

    /// Proves one sampled carrier whose RGB is transformed in place while its
    /// alpha is copied unchanged to the sole output. Every replacement RGB
    /// assignment must still read the carrier RGB, and no other texture sample
    /// may participate, so arbitrary uniform/helper math cannot invent a
    /// second color source.
    private static func preservedAlphaRGBMutationSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count >= 9,
              ["vec4", "float4"].contains(output[0].text),
              output[1].text == "(",
              output.last?.text == ")",
              outerCallClosesAtEnd(output),
              topLevelCommas(output).count == 1,
              let comma = topLevelCommas(output).first else { return nil }
        let rgb = Array(output[2..<comma])
        let alpha = Array(output[(comma + 1)..<(output.count - 1)])
        guard alpha.count == 3,
              alpha[0].kind == .identifier,
              alpha[1].text == ".",
              alpha[2].text == "a" else { return nil }
        let carrier = alpha[0].text
        let rgbUses = rgb.indices.filter { rgb[$0].text == carrier }
        guard !rgbUses.isEmpty,
              rgbUses.allSatisfy({ index in
                  index + 2 < rgb.count
                      && rgb[index + 1].text == "."
                      && rgb[index + 2].text == "rgb"
              }) else { return nil }

        let definitions = body.filter { index in
            index > body.lowerBound
                && index + 1 < outputAssignment
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ), let slot = directTextureSampleSlot(initializer),
              textureSampleSlots(in: body, tokens: tokens) == [slot] else {
            return nil
        }

        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for use in tokens.indices where use > definition && use < outputAssignment
            && tokens[use].text == carrier {
            guard use + 2 < outputAssignment,
                  tokens[use + 1].text == ".",
                  tokens[use + 2].text == "rgb" else { return nil }
            guard use + 3 < outputAssignment,
                  operators.contains(tokens[use + 3].text) else { continue }
            if tokens[use + 3].text == "=" {
                guard let semicolon = (use + 4..<outputAssignment).first(
                    where: { tokens[$0].text == ";" }
                ), (use + 4..<semicolon).contains(where: { index in
                    index + 2 < semicolon
                        && tokens[index].text == carrier
                        && tokens[index + 1].text == "."
                        && tokens[index + 2].text == "rgb"
                }) else { return nil }
            }
        }
        return slot
    }

    /// Proves a sampled local with no RGB writes and one root alpha write.
    /// The emitter applies the straight-color boundary around authored math.
    private static func mutatedStraightAlphaSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count == 1, output[0].kind == .identifier else {
            return nil
        }
        let colorName = output[0].text
        let definitions = body.filter { index in
            index + 1 < outputAssignment
                && tokens[index].text == colorName
                && index > body.lowerBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ),
              let slot = directTextureSampleSlot(initializer) else {
            return nil
        }
        guard let sampleSlots = textureSampleSlots(in: body, tokens: tokens),
              sampleSlots.filter({ $0 == slot }).count == 1,
              Set(sampleSlots.filter({ $0 != slot })).count == sampleSlots.count - 1
        else { return nil }

        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        var alphaWrites = 0
        for use in tokens.indices where use > definition && use < outputAssignment
            && tokens[use].text == colorName {
            guard use + 2 < outputAssignment,
                  tokens[use + 1].text == ".",
                  ["rgb", "a"].contains(tokens[use + 2].text) else {
                return nil
            }
            let member = tokens[use + 2].text
            let next = use + 3 < outputAssignment ? tokens[use + 3].text : ""
            guard !assignmentOperators.contains(next) || member == "a" else {
                return nil
            }
            if member == "a", assignmentOperators.contains(next) {
                guard isUnconditionalWrite(use, tokens: tokens, body: body) else {
                    return nil
                }
                alphaWrites += 1
            }
        }
        return alphaWrites == 1 ? slot : nil
    }

    private static func mutatedStraightAlphaSlot(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < fragment.tokens.count,
              fragment.tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(
                  output,
                  tokens: fragment.tokens,
                  body: main.bodyRange
              ),
              let expression = assignmentExpression(
                  after: output,
                  in: fragment.tokens,
                  body: main.bodyRange
              ) else {
            return nil
        }
        return mutatedStraightAlphaSlot(
            expression,
            outputAssignment: output,
            tokens: fragment.tokens,
            body: main.bodyRange
        )
    }

    private static func analyzedMain(
        _ source: String
    ) -> (
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function,
        outputUses: [Int]
    )? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        return (
            fragment,
            main,
            fragment.tokens.indices.filter {
                fragment.tokens[$0].text == "gl_FragColor"
            }
        )
    }

    private static func textureSampleSlots(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Int]? {
        var slots: [Int] = []
        for index in range where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 2 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text) else {
                return nil
            }
            slots.append(slot)
        }
        return slots
    }

    private static func straightAlphaSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        outputAssignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let output = Array(expression)
        guard output.count >= 9,
              ["vec4", "float4"].contains(output[0].text),
              output[1].text == "(",
              output.last?.text == ")",
              outerCallClosesAtEnd(output),
              topLevelCommas(output).count == 1,
              let comma = topLevelCommas(output).first,
              comma == 5,
              output[2].kind == .identifier,
              output[3].text == ".",
              output[4].text == "rgb" else {
            return nil
        }
        let colorName = output[2].text
        let alpha = Array(output[(comma + 1)..<(output.count - 1)])
        let colorUses = alpha.indices.filter { index in
            alpha[index].text == colorName
        }
        let alphaMembers = alpha.indices.filter { index in
            guard index + 2 < alpha.count else { return false }
            return alpha[index].kind == .identifier
                && alpha[index + 1].text == "."
                && alpha[index + 2].text == "a"
        }
        guard colorUses.count == 1,
              let alphaUse = colorUses.first,
              alphaUse + 2 < alpha.count,
              alpha[alphaUse + 1].text == ".",
              alpha[alphaUse + 2].text == "a",
              alphaMembers.allSatisfy({ alpha[$0].text == colorName }) else {
            return nil
        }

        let definitions = body.filter { index in
            index + 1 < outputAssignment
                && tokens[index].text == colorName
                && index > body.lowerBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: body),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: body
              ),
              let slot = directTextureSampleSlot(initializer) else {
            return nil
        }
        let sampleCalls = body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        guard sampleCalls.count == 1 else { return nil }
        let intermediateUses = tokens.indices.filter {
            $0 > definition && $0 < outputAssignment && tokens[$0].text == colorName
        }
        return intermediateUses.isEmpty ? slot : nil
    }

    static func isUnconditionalWrite(
        _ assignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let functionExits: Set<String> = ["discard", "return"]
        guard !body.contains(where: {
            tokens[$0].kind == .identifier && functionExits.contains(tokens[$0].text)
        }) else {
            return false
        }
        var braceDepth = 0
        var parenthesisDepth = 0
        var bracketDepth = 0
        var statementStart = body.lowerBound + 1
        for index in body.lowerBound..<assignment {
            switch tokens[index].text {
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
                if braceDepth == 1 && parenthesisDepth == 0 && bracketDepth == 0 {
                    statementStart = index + 1
                }
            case "(": parenthesisDepth += 1
            case ")": parenthesisDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case ";" where braceDepth == 1 && parenthesisDepth == 0 && bracketDepth == 0:
                statementStart = index + 1
            default: break
            }
        }
        guard braceDepth == 1, parenthesisDepth == 0, bracketDepth == 0 else {
            return false
        }
        let directControllers: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
        ]
        return !tokens[statementStart..<assignment].contains {
            $0.kind == .identifier && directControllers.contains($0.text)
        }
    }

    static func assignmentExpression(
        after assignment: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> ArraySlice<SceneAuthoredShaderToken>? {
        let start = assignment + 2
        guard assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              body.contains(start) else {
            return nil
        }
        var stack: [String] = []
        let closing: [String: String] = [")": "(", "]": "[", "}": "{"]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "[", "{"].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                guard index > start else { return nil }
                return tokens[start..<index]
            }
        }
        return nil
    }

    static func directTextureSampleSlot(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Int? {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              topLevelCommas(tokens) == [3],
              let slot = textureSlot(tokens[2].text) else {
            return nil
        }
        return slot
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0...7).contains(slot) else {
            return nil
        }
        return slot
    }
}
