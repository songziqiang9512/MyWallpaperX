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

    private struct DirectCarrierFact {
        let slot: Int
        let rgbWrites: Int
        let alphaWrites: Int
    }

    /// The direct-carrier proof is intentionally stricter than the historical
    /// independent-alpha fallback.  It accepts only one sampled local and
    /// unconditional member writes; aliases, whole-vector writes, swizzles,
    /// extra samples, control flow, and alpha resets after RGB mutation are
    /// rejected so ordinary framebuffer colors cannot be promoted to an
    /// independent signal contract.
    private static func directCarrierFact(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> DirectCarrierFact? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output, in: tokens, body: main.bodyRange
              ),
              expression.count == 1,
              let carrier = expression.first,
              carrier.kind == .identifier,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                  .topLevelStatements(in: main.bodyRange, tokens: tokens),
              !statements.isEmpty,
              statements.last?.contains(output) == true,
              !containsForbiddenDirectCarrierControlFlow(
                  main.bodyRange, tokens: tokens
              ) else { return nil }

        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index < output
                && tokens[index].text == carrier.text
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(definition, tokens: tokens, body: main.bodyRange),
              let initializer = assignmentExpression(
                  after: definition, in: tokens, body: main.bodyRange
              ),
              let slot = directTextureSampleSlot(initializer),
              let sampleSlots = textureSampleSlots(
                  in: main.bodyRange, tokens: tokens
              ),
              sampleSlots == [slot],
              carrierDefinitionIsTopLevel(
                  definition, statements: statements
              ),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: statements
                      .filter { $0.lowerBound > definition && $0.upperBound <= output }
              ) else { return nil }

        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        var rgbWrites = 0
        var alphaWrites = 0
        var rgbWasWritten = false
        var alphaResetToOne = false

        for use in (definition + 1)..<output where tokens[use].text == carrier.text {
            guard use + 2 < output,
                  tokens[use + 1].text == ".",
                  ["rgb", "a"].contains(tokens[use + 2].text) else {
                // A bare carrier use is an alias/escape.  The sole output
                // expression was checked above and is outside this range.
                return nil
            }
            let member = tokens[use + 2].text
            let operatorIndex = use + 3
            guard operatorIndex < output else { return nil }
            let operation = tokens[operatorIndex].text
            guard assignmentOperators.contains(operation) else { continue }
            guard isUnconditionalWrite(
                use, tokens: tokens, body: main.bodyRange
            ), let rhs = memberAssignmentExpression(
                after: operatorIndex, tokens: tokens, body: main.bodyRange,
                boundary: output
            ) else { return nil }

            switch member {
            case "rgb":
                guard !expressionContainsTextureSample(rhs),
                      directCarrierRGBExpressionIsSafe(
                          rhs,
                          carrier: carrier.text,
                          operation: operation,
                          fragment: fragment
                      ) else { return nil }
                rgbWrites += 1
                rgbWasWritten = true
            case "a":
                guard directCarrierAlphaExpressionIsSafe(
                    rhs,
                    carrier: carrier.text,
                    fragment: fragment
                ) else { return nil }
                if expressionIsOne(rhs) { alphaResetToOne = true }
                alphaWrites += 1
            default:
                return nil
            }
        }

        // A one-valued alpha reset following a color mutation is the bounded
        // independent-signal producer shape, not ordinary framebuffer
        // coverage.  Leave it to the typed independent analyzer (or reject).
        guard !(rgbWasWritten && alphaResetToOne),
              rgbWrites > 0 || alphaWrites > 0 else { return nil }
        return DirectCarrierFact(
            slot: slot,
            rgbWrites: rgbWrites,
            alphaWrites: alphaWrites
        )
    }

    private static func carrierDefinitionIsTopLevel(
        _ definition: Int,
        statements: [Range<Int>]
    ) -> Bool {
        statements.contains { $0.contains(definition) }
    }

    private static func containsForbiddenDirectCarrierControlFlow(
        _ body: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue", "goto", "?",
        ]
        return body.contains { forbidden.contains(tokens[$0].text) }
    }

    private static func memberAssignmentExpression(
        after operatorIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        boundary: Int
    ) -> ArraySlice<SceneAuthoredShaderToken>? {
        let start = operatorIndex + 1
        guard start < boundary, body.contains(start) else { return nil }
        var parentheses = 0
        var brackets = 0
        var braces = 0
        for index in start..<min(boundary, body.upperBound) {
            switch tokens[index].text {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "{": braces += 1
            case "}": braces -= 1
            case ";" where parentheses == 0 && brackets == 0 && braces == 0:
                return start < index ? tokens[start..<index] : nil
            default: break
            }
            guard parentheses >= 0, brackets >= 0, braces >= 0 else {
                return nil
            }
        }
        return nil
    }

    private static func expressionContainsTextureSample(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.contains {
            ["texSample2D", "texture2D"].contains($0.text)
        }
    }

    private static func directCarrierRGBExpressionIsSafe(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        carrier: String,
        operation: String,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard !expression.contains(where: { $0.text == "?" }),
              !containsBareIdentifier(carrier, in: expression),
              !containsMember(carrier, member: "a", in: expression),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: [expression.startIndex..<expression.endIndex]
              ) else { return false }
        if operation == "=" {
            return containsMember(carrier, member: "rgb", in: expression)
        }
        return true
    }

    private static func directCarrierAlphaExpressionIsSafe(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        carrier: String,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard !expression.contains(where: { $0.text == "?" }),
              !containsBareIdentifier(carrier, in: expression),
              !containsMember(carrier, member: "rgb", in: expression),
              !containsOtherMemberAccess(
                  expression, excluding: (carrier, "a")
              ),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: [expression.startIndex..<expression.endIndex]
              ) else { return false }
        return true
    }

    private static func expressionIsOne(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let values = expression.filter { $0.text != "(" && $0.text != ")" }
        guard values.count == 1, values[0].kind == .number else { return false }
        return Double(values[0].text) == 1
    }

    private static func containsBareIdentifier(
        _ name: String,
        in expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.indices.contains { index in
            expression[index].text == name
                && !(index + 2 < expression.endIndex
                    && expression[index + 1].text == "."
                    && ["rgb", "a"].contains(expression[index + 2].text))
        }
    }

    private static func containsMember(
        _ name: String,
        member: String,
        in expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.indices.contains { index in
            index + 2 < expression.endIndex
                && expression[index].text == name
                && expression[index + 1].text == "."
                && expression[index + 2].text == member
        }
    }

    private static func containsOtherMemberAccess(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        excluding allowed: (String, String)
    ) -> Bool {
        expression.indices.contains { index in
            guard index + 2 < expression.endIndex,
                  expression[index + 1].text == ".",
                  expression[index].kind == .identifier,
                  expression[index + 2].kind == .identifier else {
                return false
            }
            return (expression[index].text, expression[index + 2].text)
                != allowed
        }
    }

    private static func helperCallsArePureAndUnsampled(
        fragment: SceneAuthoredShaderSyntaxUnit,
        expressionRanges: [Range<Int>]
    ) -> Bool {
        let tokens = fragment.tokens
        let builtins: Set<String> = [
            "abs", "ceil", "clamp", "cos", "dot", "exp", "floor",
            "fract", "length", "log", "max", "min", "mix", "mod",
            "normalize", "pow", "round", "sin", "smoothstep", "sqrt",
            "step", "tan", "saturate", "sign", "vec2", "vec3", "vec4",
            "float2", "float3", "float4", "int2", "int3", "int4",
            "uint2", "uint3", "uint4", "fast", "CAST3",
        ]
        var names: Set<String> = []
        for range in expressionRanges {
            for index in range where index + 1 < range.upperBound {
                guard tokens[index].kind == .identifier,
                      tokens[index + 1].text == "(",
                      index == range.lowerBound || tokens[index - 1].text != "."
                else { continue }
                names.insert(tokens[index].text)
            }
        }
        for name in names {
            guard let function = fragment.functions.first(where: {
                $0.name == name
            }) else {
                // ApplyBlending is a canonical authored include.  Some
                // prepared sources retain the include directive instead of
                // inlining its helper body, so absence of that declaration is
                // allowed.  Every other unknown call must fail closed.
                guard builtins.contains(name) || name == "ApplyBlending" else {
                    return false
                }
                continue
            }
            // A user declaration shadows even a built-in spelling (for
            // example `mix`).  Validate that body through the same pure,
            // read-only helper closure instead of trusting the built-in name.
            guard function.name != "main",
                  !tokens[function.parameterRange].contains(where: {
                      ["out", "inout"].contains($0.text)
                  }), let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                      .safeReadOnlyHelperClosure(
                          rootName: name, fragment: fragment
                      ), closure.allSatisfy({ helper in
                          !tokens[helper.bodyRange].contains(where: {
                              ["texSample2D", "texture2D", "gl_FragColor", "discard",
                               "imageStore"].contains($0.text)
                          })
                      }) else { return false }
        }
        return true
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
