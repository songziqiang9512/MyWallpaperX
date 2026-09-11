import Foundation

/// The approved product default for an authored color pass that neither the
/// shared source analyzer nor the compiler-artifact analyzer could classify.
/// Every sampled color input in the boundary set enters authored math as
/// straight color and every terminal `return out;` premultiplies the output
/// once, matching the compositor's premultiplied publication. The authored
/// math itself is not proven here; a visual verdict on the real sample, not a
/// per-shape analyzer, accepts or rejects the result.
extension SceneGenericShaderArtifactBuilder {
    static let defaultStraightColorBoundaryKind = "default-straight-color-boundary"

    /// Proven shapes keep their exact lowering. When that lowering rejects the
    /// compiler output for a straight-color classification, the product
    /// default boundary takes over instead of failing the whole effect.
    static func prepareColorTransfer(
        msl source: String,
        authoredSource: String,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer? = nil,
        defaultBoundaryColorSlots: Set<Int> = []
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        do {
            return try prepareProvenColorTransfer(
                msl: source,
                authoredSource: authoredSource,
                expectedColorTransfer: expectedColorTransfer,
                defaultBoundaryColorSlots: defaultBoundaryColorSlots
            )
        } catch Failure.colorTransfer {
            // A profile that expects an independent signal describes a
            // non-color output; only straight-color expectations may fall
            // back to the default boundary.
            guard expectedColorTransfer == nil
                    || expectedColorTransfer?.kind == "straight-alpha-preserving",
                  SceneAuthoredShaderColorTransferAnalyzer.analyze(
                      fragmentSource: authoredSource
                  ).permitsDefaultStraightColorBoundary,
                  !hasStrictCompilerOwner(authoredSource),
                  compilerPreservedAlphaRGBFilterContractIsValid(
                      msl: source,
                      authoredSource: authoredSource
                  ),
                  let lowered = SceneGenericShaderDefaultStraightColorBoundaryLowering
                    .lower(source, colorSlots: defaultBoundaryColorSlots) else {
                throw Failure.colorTransfer
            }
            return (
                lowered.msl,
                .init(
                    kind: defaultStraightColorBoundaryKind,
                    slot: nil,
                    slots: lowered.appliedSlots
                )
            )
        }
    }

    /// A product default may recover a color pass whose exact compiler shape
    /// is not owned. It must not turn a rejected artifact into a successful
    /// result after the authored source has selected a narrower owner whose
    /// slot roles and terminal data flow are part of the contract.
    private static func hasStrictCompilerOwner(_ authoredSource: String) -> Bool {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: authoredSource, stage: .fragment
            ),
            stage: .fragment
        )
        if syntax.diagnostics.isEmpty, let fragment = syntax.unit,
           SceneAuthoredShaderAlphaAttenuationAnalyzer
            .directOutputFact(fragment) != nil {
            return true
        }
        if SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer
            .analyze(fragmentSource: authoredSource) != nil {
            return true
        }
        if let fact = SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
            .analyzeSourceCarried(fragmentSource: authoredSource),
           fact.shape == .generatedCarrier {
            return true
        }
        if SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        let blendSlots = SceneAuthoredShaderColorTransferAnalyzer
            .blendSourceSlots(fragmentSource: authoredSource)
        if blendSlots.overlayAlpha != nil
            || blendSlots.overlayAlphaPreserving != nil {
            return true
        }
        if SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        if SceneAuthoredShaderColorTransferAnalyzer.straightRGBScalarAlphaFact(
            fragmentSource: authoredSource
        ) != nil {
            return true
        }
        return SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil
    }

    /// The default straight-color boundary may cover an unclassified output
    /// shape, but it cannot hide a compiler change to a source-proven
    /// preserved-alpha RGB filter. Keep the sample count and projection
    /// contract from the authored fact in force before allowing that fallback.
    private static func compilerPreservedAlphaRGBFilterContractIsValid(
        msl source: String,
        authoredSource: String
    ) -> Bool {
        if case .generatedStraightAlpha =
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: authoredSource
            ) {
            return SceneGenericShaderGeneratedStraightRGBALowering
                .compilerContractMatches(source)
        }
        guard case let .straightAlphaPreserving(expectedSlot) =
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: authoredSource
            ) else {
            return true
        }
        if let slot = SceneAuthoredShaderColorTransferAnalyzer
            .sameSlotCarrierBlendSourceSlot(fragmentSource: authoredSource) {
            return SceneGenericShaderSameSlotCarrierBlendLowering
                .compilerContractMatches(source, expectedSlot: slot)
        }
        if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
            .analyzeAny(fragmentSource: authoredSource) {
            return SceneGenericShaderStraightAlphaPreservingLowering
                .preservedAlphaRGBFilterCompilerSamplesMatch(
                    in: source,
                    sourceSlot: fact.sourceSlot,
                    fullColorSampleCallCounts: fact.fullColorSampleCallCounts,
                    rgbColorSampleCallCounts: fact.rgbColorSampleCallCounts,
                    dataSampleCallCounts: fact.dataSampleCallCounts
                )
        }
        if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
            fragmentSource: authoredSource
        ) {
            return SceneGenericShaderTypedDataRGBFilterLowering
                .compilerContractMatches(source, fact: fact)
        }
        if let fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(
                fragmentSource: authoredSource
            ) {
            return SceneGenericShaderGeneratedRGBPreservedAlphaLowering
                .compilerContractMatches(source, fact: fact)
        }
        if let match = SceneGenericShaderScalarizedRGBPreservedAlphaLowering
            .compilerContractMatchIfCandidate(
                source,
                expectedSlot: expectedSlot
            ) {
            return match
        }
        return true
    }

    static func prepareUnresolvedColorTransfer(
        msl source: String,
        boundaryColorSlots: Set<Int>
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        do {
            return try prepareCompilerProvenColorTransfer(source)
        } catch {
            guard let lowered = SceneGenericShaderDefaultStraightColorBoundaryLowering
                .lower(source, colorSlots: boundaryColorSlots) else {
                throw Failure.colorTransfer
            }
            return (
                lowered.msl,
                .init(
                    kind: defaultStraightColorBoundaryKind,
                    slot: nil,
                    slots: lowered.appliedSlots
                )
            )
        }
    }

    static func defaultBoundaryTransfer(
        _ transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer,
        isBoundBy boundSlots: Set<Int>
    ) -> Bool {
        guard transfer.kind == defaultStraightColorBoundaryKind,
              transfer.slot == nil,
              let slots = transfer.slots else { return false }
        return slots == slots.sorted()
            && Set(slots).count == slots.count
            && Set(slots).isSubset(of: boundSlots)
    }
}

nonisolated enum SceneGenericShaderDefaultStraightColorBoundaryLowering {
    struct Lowered: Equatable {
        let msl: String
        /// Sorted color slots whose sample calls were unpremultiplied. Slots
        /// in the boundary set that the fragment never samples are omitted.
        let appliedSlots: [Int]
    }

    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(_ source: String, colorSlots: Set<Int>) -> Lowered? {
        guard colorSlots.allSatisfy({ (0 ..< 8).contains($0) }),
              !source.contains(unpremultiply),
              !source.contains(premultiply),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              !matches(#"\bout\.mwxFragColor\b"#, in: source).isEmpty,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source) else { return nil }
        let returns = matches(#"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#, in: source)
        guard !returns.isEmpty else { return nil }

        var edits: [(range: NSRange, replacement: String)] = []
        for match in returns {
            let indent = capture(match, 1, in: source) ?? ""
            edits.append((
                match.range,
                "\(indent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                    + "\(indent)return out;"
            ))
        }
        var applied = Set<Int>()
        for call in calls where colorSlots.contains(call.slot) {
            guard let range = Range(call.range, in: source) else { return nil }
            edits.append((call.range, "\(unpremultiply)(\(source[range]))"))
            applied.insert(call.slot)
        }
        // Every edit range is disjoint; apply from the end so earlier
        // UTF-16 offsets stay valid in the transformed string.
        var transformed = source
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(edit.range, in: transformed) else { return nil }
            transformed.replaceSubrange(range, with: edit.replacement)
        }
        guard let withHelpers = SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed) else { return nil }
        return Lowered(msl: withHelpers, appliedSlots: applied.sorted())
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        try! NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}
