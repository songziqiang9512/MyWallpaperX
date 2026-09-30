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
            ?? directCarrierFact(
                outputUses: outputUses,
                fragment: fragment,
                main: main
            )?.slot
    }

    /// Returns the sampled slot for the deliberately narrow direct-carrier
    /// grammar.  A direct carrier is a single sampled vec4 local written to
    /// the sole fragment output; only its `rgb`/`a` members may be mutated,
    /// and every mutation must remain an unconditional, non-sampled scalar or
    /// color expression.  This fact is intentionally structural and carries
    /// no effect, path, asset, or shader identity.
    static func directCarrierSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return nil
        }
        return directCarrierFact(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )?.slot
    }

    /// Returns true only when the authored direct-carrier proof includes an
    /// unconditional RGB member mutation.  The compiler-side direct-carrier
    /// lowering uses this narrower provenance so an alpha-only source cannot
    /// silently accept a compiler drift that introduces a new RGB write.
    static func directCarrierHasRGBMutation(
        fragmentSource source: String
    ) -> Bool {
        guard let (fragment, main, outputUses) = analyzedMain(source) else {
            return false
        }
        return directCarrierFact(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )?.rgbWrites ?? 0 > 0
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
        if let fact = SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(
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
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer.analyzeWithIndependentAlpha(
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
            logUnresolved(
                site: "output-shape",
                outputUses: outputUses,
                tokens: tokens,
                main: main,
                outcome: "unresolved"
            )
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
        if let fact = directCarrierFact(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        ) {
            return fact.alphaWrites > 0
                ? .straightAlpha(textureSlot: fact.slot)
                : .straightAlphaPreserving(textureSlot: fact.slot)
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
        if let slot = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeScalarOpacitySampledBaseBlend(
                outputUses: outputUses,
                fragment: fragment,
                main: main
            ) {
            return .straightAlphaPreserving(textureSlot: slot)
        }
        if let transfer = SceneAuthoredShaderIndependentAlphaAnalyzer.analyze(
            outputUses: outputUses, fragment: fragment, main: main
        ) {
            return transfer
        }
        if let fact = SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyzeSourceCarried(fragment) {
            return fact.colorTransfer
        }
        let outcome: String = isOpaqueVectorConstruction(expression)
            ? "opaque" : "unresolved"
        logUnresolved(
            site: "prover-chain",
            outputUses: outputUses,
            tokens: tokens,
            main: main,
            outcome: outcome
        )
        return isOpaqueVectorConstruction(expression) ? .opaque : .unresolved
    }

    /// Forensics-only characterization for the registered colorTransfer
    /// residual: emits which exit rejected and how the output is used, so an
    /// evidence replay can name the unproven shape without a code change.
    /// Gated on the same evidence flag as the compiler's normalized-source
    /// dumps; silent in product.
    private static func logUnresolved(
        site: String,
        outputUses: [Int],
        tokens: [SceneAuthoredShaderToken],
        main: SceneAuthoredShaderSyntaxUnit.Function,
        outcome: String
    ) {
        guard ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-evidence-dir"
        ) else { return }
        let details = outputUses.map { index -> String in
            let next = index + 1 < tokens.count ? tokens[index + 1].text : "?"
            // isUnconditionalWrite scans backwards from the use to the body
            // start; a use outside main (a helper writing gl_FragColor)
            // would invert that range, so containment gates the call.
            let inMain = main.bodyRange.contains(index)
            let unconditional = inMain
                && isUnconditionalWrite(index, tokens: tokens, body: main.bodyRange)
            return "at=\(index) next=\(next) unconditional=\(unconditional) inMain=\(inMain)"
        }
        NSLog(
            "MWX DEBUG SCENE: phase=color-transfer-unresolved site=%@ outcome=%@ useDetails=%@",
            site,
            outcome,
            details.joined(separator: ";")
        )
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
              let slot = SceneShaderSourceTextFacts.textureSlot(tokens[2].text) else {
            return nil
        }
        return slot
    }

}
