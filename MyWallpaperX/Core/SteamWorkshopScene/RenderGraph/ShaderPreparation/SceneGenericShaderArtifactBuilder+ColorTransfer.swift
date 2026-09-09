import Foundation

extension SceneGenericShaderArtifactBuilder {
    /// Moves exact provider-backed color inputs from the compositor's
    /// premultiplied boundary into the authored shader's straight-color domain.
    /// Output transfer remains owned by the independently proven color profile.
    static func lowerPremultipliedColorInputs(
        _ source: String,
        slots: Set<Int>
    ) -> String? {
        guard !slots.isEmpty,
              slots.allSatisfy({ (0 ..< 8).contains($0) }),
              source.components(
                  separatedBy: "inline float4 mwxGenericUnpremultiply"
              ).count == 2,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source) else { return nil }
        let selected = calls.filter { slots.contains($0.slot) }
        guard !selected.isEmpty, Set(selected.map(\.slot)) == slots else {
            return nil
        }
        var transformed = source
        for call in selected.sorted(by: { $0.range.location > $1.range.location }) {
            guard let sourceRange = Range(call.range, in: source),
                  !source[..<sourceRange.lowerBound].hasSuffix(
                      "mwxGenericUnpremultiply("
                  ), let adjustedRange = Range(call.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                adjustedRange,
                with: "mwxGenericUnpremultiply(\(source[sourceRange]))"
            )
        }
        return transformed
    }

    static func prepareProvenColorTransfer(
        msl source: String,
        authoredSource: String,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer? = nil,
        defaultBoundaryColorSlots: Set<Int> = []
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        if expectedColorTransfer?.usesRGBA8UnormAttachmentBoundary == true {
            guard expectedColorTransfer?.kind
                    == "independent-alpha-signal-preserving",
                  let slot = expectedColorTransfer?.slot,
                  expectedColorTransfer?.accumulatorLoopWork != nil,
                  SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                    .validates(source, expectedSlot: slot) else {
                throw Failure.colorTransfer
            }
            return (
                source,
                artifactTransfer(
                    kind: "independent-alpha-signal-preserving",
                    slot: slot
                )
            )
        }
        switch SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authoredSource
        ) {
        case let .passthrough(textureSlot: slot):
            return (source, artifactTransfer(kind: "passthrough", slot: slot))
        case let .interpolatedColor(textureSlots: slots):
            return (
                source,
                .init(kind: "interpolated-color", slot: nil, slots: slots)
            )
        case let .opaqueFromStraightColor(expectedSlot):
            guard let fact =
                    SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer
                        .analyze(fragmentSource: authoredSource),
                  fact.sourceSlot == expectedSlot,
                  let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerOpaqueFromStraightColor(
                        source,
                        expectedSlot: expectedSlot,
                        sampleCount: fact.sampleCount
                    ) else { throw Failure.colorTransfer }
            return (
                lowered,
                artifactTransfer(
                    kind: "opaque-from-straight-color",
                    slot: expectedSlot
                )
            )
        case .opaque:
            return (source, artifactTransfer(kind: "opaque"))
        case .generatedStraightAlpha:
            guard let prepared = SceneGenericShaderGeneratedStraightRGBALowering
                .prepare(source, authoredSource: authoredSource)
            else { throw Failure.colorTransfer }
            return prepared
        case .premultipliedAlpha:
            return (source, artifactTransfer(kind: "premultiplied"))
        case let .straightAlpha(textureSlot: expectedSlot):
            // A separated generated RGBA carrier may use a replacement alpha
            // helper, which is straight-alpha rather than alpha-preserving.
            // Its narrow compiler proof must run before the generic straight
            // lowerers so unresolved compiler drift remains fail-closed.
            if let fact = SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                .analyzeSourceCarried(fragmentSource: authoredSource),
               fact.shape == .generatedCarrier {
                guard fact.sourceSlot == expectedSlot,
                      fact.transfer == .straight,
                      let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerGeneratedSourceCarried(
                            source,
                            expectedSlot: expectedSlot,
                            expectedTransfer: fact.transfer
                        ) else {
                    throw Failure.colorTransfer
                }
                return (
                    lowered,
                    artifactTransfer(kind: "straight-alpha", slot: expectedSlot)
                )
            }
            if let prepared = try prepareSameSlotColorBlendAlphaUnion(
                msl: source, authoredSource: authoredSource,
                expectedSlot: expectedSlot
            ) {
                return prepared
            }
            if let fact =
                SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer
                    .analyze(fragmentSource: authoredSource),
               !fact.preservesSnapshotAlpha,
               fact.sourceSlot == expectedSlot {
                guard let lowered =
                        SceneGenericShaderSameAlphaReconstructedRGBFilterLowering
                            .lower(source, fact: fact) else {
                    throw Failure.colorTransfer
                }
                return (
                    lowered,
                    artifactTransfer(kind: "straight-alpha", slot: expectedSlot)
                )
            }
            if let fact = SceneAuthoredShaderAssociatedOverBlendAnalyzer
                .analyze(fragmentSource: authoredSource),
                fact.sourceSlot == expectedSlot
            {
                guard let lowered = SceneGenericShaderAssociatedOverBlendLowering
                    .lower(source, fact: fact) else { throw Failure.colorTransfer }
                return (
                    lowered,
                    artifactTransfer(kind: "straight-alpha", slot: expectedSlot)
                )
            }
            if let overlay = SceneAuthoredShaderColorTransferAnalyzer
                .blendSourceSlots(fragmentSource: authoredSource).overlayAlpha,
                overlay.source == expectedSlot
            {
                guard let lowered = SceneGenericShaderAssociatedOverBlendLowering
                    .lower(
                        source,
                        sourceSlot: overlay.source,
                        overlaySlot: overlay.overlay
                    ) else { throw Failure.colorTransfer }
                return (
                    lowered,
                    artifactTransfer(kind: "straight-alpha", slot: expectedSlot)
                )
            }
            let rgbBlendScalarAlphaLowering: String? =
                SceneAuthoredShaderColorTransferAnalyzer
                    .rgbBlendScalarAlphaFact(fragmentSource: authoredSource)
                    .flatMap { fact in
                        guard fact.sourceSlot == expectedSlot else { return nil }
                        return SceneGenericShaderRGBBlendScalarAlphaLowering
                            .lower(source, fact: fact)
                    }
            let weightedAverage = SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer
                .analyze(fragmentSource: authoredSource)
            let weightedLowering: String? = weightedAverage.flatMap { fact in
                guard fact.textureSlot == expectedSlot else { return nil }
                return SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerAlphaWeightedSampleAverage(
                        source,
                        expectedSlot: expectedSlot,
                        sampleCount: fact.sampleCount
                    )
            }
            let scalarAlphaLowering: String? = SceneAuthoredShaderColorTransferAnalyzer
                .straightRGBScalarAlphaFact(fragmentSource: authoredSource)
                .flatMap { fact in
                    guard fact.sourceSlot == expectedSlot else { return nil }
                    return lowerStraightRGBScalarAlpha(source, fact: fact)
                }
            let requiresStraightColorBoundary =
                SceneAuthoredShaderColorTransferAnalyzer
                    .singleSamplerAlphaMutationSourceSlot(
                        fragmentSource: authoredSource
                    ) == expectedSlot
            let directCarrierLowering: String? =
                SceneAuthoredShaderColorTransferAnalyzer
                    .directCarrierSourceSlot(fragmentSource: authoredSource)
                    == expectedSlot
                    && SceneAuthoredShaderColorTransferAnalyzer
                        .directCarrierHasRGBMutation(
                            fragmentSource: authoredSource
                        )
                    ? SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerDirectCarrier(
                            source,
                            expectedSlot: expectedSlot
                        )
                    : nil
            let direct = straightAlphaAttenuation(
                source,
                requiresStraightColorBoundary: requiresStraightColorBoundary
            )
            let lowered = rgbBlendScalarAlphaLowering
                ?? weightedLowering
                ?? scalarAlphaLowering
                ?? (direct?.transfer.slot == expectedSlot ? direct?.msl : nil)
                ?? SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerConditionalUnion(source, expectedSlot: expectedSlot)
                ?? SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerDirectOutputAlphaMutation(source, expectedSlot: expectedSlot)
                ?? directCarrierLowering
                ?? SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerStraightOutput(source, expectedSlot: expectedSlot)
            guard let lowered else { throw Failure.colorTransfer }
            return (lowered, artifactTransfer(kind: "straight-alpha", slot: expectedSlot))
        case let .straightAlphaPreserving(textureSlot: expectedSlot):
            return try prepareStraightAlphaPreservingColorTransfer(
                msl: source,
                authoredSource: authoredSource,
                expectedSlot: expectedSlot
            )
        case let .independentAlphaSignalPreserving(textureSlot: slot):
            return (
                source,
                artifactTransfer(
                    kind: "independent-alpha-signal-preserving",
                    slot: slot
                )
            )
        case let .independentAlphaSignal(textureSlot: slot):
            guard let lowered =
                    SceneGenericShaderIndependentSignalLowering.lowerProducer(
                        source,
                        expectedSlot: slot
                    ) else { throw Failure.colorTransfer }
            return (
                lowered,
                artifactTransfer(kind: "independent-alpha-signal", slot: slot)
            )
        case let .independentAlphaSignalCompositing(signalSlot, colorSlot):
            guard let lowered =
                    SceneGenericShaderIndependentSignalCompositingLowering.lower(
                        source,
                        expectedSignalSlot: signalSlot,
                        expectedColorSlot: colorSlot
                    ) else { throw Failure.colorTransfer }
            return (
                lowered,
                .init(
                    kind: "independent-alpha-signal-compositing",
                    slot: nil,
                    slots: [signalSlot, colorSlot]
                )
            )
        case let .independentAlphaSignalUnderlayCompositing(
            signalSlot, colorSlot, underlaySlot
        ):
            guard let lowered =
                    SceneGenericShaderIndependentSignalCompositingLowering.lower(
                        source,
                        expectedSignalSlot: signalSlot,
                        expectedColorSlot: colorSlot,
                        expectedUnderlaySlot: underlaySlot
                    ) else { throw Failure.colorTransfer }
            return (
                lowered,
                .init(
                    kind: "independent-alpha-signal-underlay-compositing",
                    slot: nil,
                    slots: [signalSlot, colorSlot, underlaySlot]
                )
            )
        case .unresolved, .defaultStraightColorBoundary:
            return try prepareUnresolvedColorTransfer(
                msl: source, boundaryColorSlots: defaultBoundaryColorSlots
            )
        case let .straightAlphaUNorm(textureSlot: expectedSlot):
            let rgbBlend: String? = SceneAuthoredShaderColorTransferAnalyzer
                .rgbBlendScalarAlphaFact(fragmentSource: authoredSource)
                .flatMap { fact in
                    guard fact.sourceSlot == expectedSlot,
                          fact.terminalTransform == .saturateRGBA else {
                        return nil
                    }
                    return SceneGenericShaderRGBBlendScalarAlphaLowering
                        .lower(source, fact: fact)
                }
            let scalarAlpha: String? = SceneAuthoredShaderColorTransferAnalyzer
                .straightRGBScalarAlphaFact(fragmentSource: authoredSource)
                .flatMap { fact in
                    guard fact.sourceSlot == expectedSlot,
                          fact.terminalTransform == .saturateRGBA else {
                        return nil
                    }
                    return lowerStraightRGBScalarAlpha(source, fact: fact)
                }
            guard let lowered = rgbBlend ?? scalarAlpha else {
                throw Failure.colorTransfer
            }
            return (
                lowered,
                artifactTransfer(
                    kind: "straight-alpha-unorm", slot: expectedSlot
                )
            )
        }
    }

    static func prepareCompilerProvenColorTransfer(_ source: String) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        if let straight = straightAlphaAttenuation(source) { return straight }
        let assignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=.*;$"#,
            in: source
        )
        guard assignments.count == 1,
              let assignment = substring(assignments[0].range, in: source) else {
            throw Failure.colorTransfer
        }
        if let slotText = captures(
            #"^\s*out\.mwxFragColor\s*=\s*g_Texture([0-7])\.sample\([^;]+\);\s*$"#,
            in: assignment
        )?.first, let slot = Int(slotText) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "passthrough",
                    slot: slot,
                    slots: nil
                )
            )
        }
        if let interpolated = interpolatedColorTransfer(source, assignment: assignment) {
            return (source, interpolated)
        }
        if regexMatches(
            #"^\s*out\.mwxFragColor\s*=\s*float4\(.+,\s*1(?:\.0+)?\s*\);\s*$"#,
            assignment
        ) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "opaque",
                    slot: nil,
                    slots: nil
                )
            )
        }
        if premultipliedAccumulator(source, assignment: assignment) {
            return (
                source,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "premultiplied",
                    slot: nil,
                    slots: nil
                )
            )
        }
        throw Failure.colorTransfer
    }

    static func colorTransfer(
        _ transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer,
        isBoundBy bindings: [
            SceneGenericShaderProgramArtifact.Program.TextureBinding
        ]
    ) -> Bool {
        let boundSlots = Set(bindings.map(\.slot))
        switch (transfer.kind, transfer.slot, transfer.slots) {
        case let ("passthrough", slot?, nil),
             let ("straight-alpha", slot?, nil),
             let ("straight-alpha-unorm", slot?, nil),
             let ("straight-alpha-preserving", slot?, nil),
             let ("opaque-from-straight-color", slot?, nil),
             let ("independent-alpha-signal", slot?, nil),
             let ("independent-alpha-signal-preserving", slot?, nil):
            return boundSlots.contains(slot)
        case let ("interpolated-color", nil, slots?):
            return slots.count >= 2
                && slots.count <= 8
                && slots == slots.sorted()
                && Set(slots).count == slots.count
                && Set(slots).isSubset(of: boundSlots)
        case let ("independent-alpha-signal-compositing", nil, slots?):
            return slots.count == 2
                && slots[0] != slots[1]
                && slots.allSatisfy(boundSlots.contains)
        case let (
            "independent-alpha-signal-underlay-compositing", nil, slots?
        ):
            return slots.count == 3
                && Set(slots).count == 3
                && slots.allSatisfy(boundSlots.contains)
        case ("opaque", nil, nil), ("premultiplied", nil, nil),
             ("generated-straight-alpha", nil, nil),
             ("red-green-unorm-data", nil, nil),
             ("preserved-rgba-data", nil, nil):
            return true
        default:
            return defaultBoundaryTransfer(transfer, isBoundBy: boundSlots)
        }
    }

    static func interpolatedColorTransfer(
        _ source: String,
        assignment: String
    ) -> SceneGenericShaderProgramArtifact.Program.ColorTransfer? {
        guard let output = captures(
            #"^\s*out\.mwxFragColor\s*=\s*mix\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*([^,)]+)\s*\)\s*;\s*$"#,
            in: assignment
        ), output.count == 3 else { return nil }

        var slots: [Int] = []
        for name in output.prefix(2) {
            let declarations = matches(
                #"(?m)^[ \t]*float4\s+"# + escaped(name)
                    + #"\s*=\s*g_Texture([0-7])\.sample\([^;]+\)\s*;$"#,
                in: source
            )
            guard declarations.count == 1,
                  let slotText = capture(declarations[0], 1, in: source),
                  let slot = Int(slotText),
                  countWord(name, in: source) == 2 else { return nil }
            slots.append(slot)
        }

        let weight = output[2].trimmingCharacters(in: .whitespacesAndNewlines)
        if !regexMatches(#"^[-+]?(?:\d+(?:\.\d*)?|\.\d+)$"#, weight) {
            guard matches(
                #"(?m)^[ \t]*float\s+"# + escaped(weight) + #"\s*=\s*[^;]+;$"#,
                in: source
            ).count == 1 else { return nil }
        }

        slots = Array(Set(slots)).sorted()
        guard slots.count >= 2 else { return nil }
        return .init(kind: "interpolated-color", slot: nil, slots: slots)
    }

    static func straightAlphaAttenuation(
        _ source: String,
        requiresStraightColorBoundary: Bool = false
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        let assignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=.*;$"#,
            in: source
        )
        guard assignments.count == 1,
              let assignment = substring(assignments[0].range, in: source),
              let name = captures(
                #"^[ \t]*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;$"#,
                in: assignment
              )?.first else { return nil }
        let namePattern = escaped(name)
        guard let slotText = captures(
            #"(?m)^[ \t]*float4\s+"# + namePattern
                + #"\s*=\s*g_Texture([0-7])\.sample\([^;]+\)\s*;$"#,
            in: source
        )?.first, let slot = Int(slotText) else { return nil }
        let attenuationPattern = #"(?m)^([ \t]*)"# + namePattern
            + #"\.w\s*\*=\s*([^;]+)\s*;$"#
        let attenuation = matches(attenuationPattern, in: source)
        guard attenuation.count == 1,
              let indent = capture(attenuation[0], 1, in: source),
              let factor = capture(attenuation[0], 2, in: source),
              !containsWord(name, in: factor) else { return nil }
        let writes = capturesAll(
            #"(?m)^\s*"# + namePattern
                + #"(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=)"#,
            in: source,
            group: 1
        )
        guard writes == ["w"],
              countWord(name, in: source) == 3 + matches(
                  #"\b"# + namePattern + #"\.(?:[xyzrgb]{1,3})\b"#, in: source
              ).count,
              straightAlphaAttenuationUsesAreLinear(
                  name: name,
                  source: source,
                  declaration: source.range(
                      of: #"(?m)^\s*float4\s+"# + namePattern + #"\s*="#,
                      options: .regularExpression
                  ),
                  attenuation: attenuation[0].range,
                  output: assignments[0].range
              ),
              let replaceRange = Range(attenuation[0].range, in: source) else { return nil }
        if requiresStraightColorBoundary {
            guard let transformed =
                SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreserving(source, expectedSlot: slot) else {
                return nil
            }
            return (
                transformed,
                SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                    kind: "straight-alpha",
                    slot: slot,
                    slots: nil
                )
            )
        }
        var transformed = source
        transformed.replaceSubrange(replaceRange, with: "\(indent)\(name) *= \(factor);")
        return (
            transformed,
            SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                kind: "straight-alpha",
                slot: slot,
                slots: nil
            )
        )
    }

    /// Verifies the compiler shape before the boundary rewrite. The
    /// alpha-only route may read RGB members while deriving its factor, but a
    /// whole-carrier read, an alpha read, or an RGB mutation changes the
    /// authored color contract and must fall through to a narrower route.
    private static func straightAlphaAttenuationUsesAreLinear(
        name: String,
        source: String,
        declaration: Range<String.Index>?,
        attenuation: NSRange,
        output: NSRange
    ) -> Bool {
        let namePattern = escaped(name)
        let uses = matches(#"\b"# + namePattern + #"\b"#, in: source)
        let sourceNSString = source as NSString
        let declarationRange = declaration.map { NSRange($0, in: source) }
        let allowedRGBMembers: Set<String> = [
            "x", "y", "z", "r", "g", "b", "rgb", "xyz",
        ]
        let assignmentOperators = #"(?:=|\+=|-=|\*=|/=)"#
        for use in uses {
            if declarationRange.map({ NSIntersectionRange($0, use.range).length > 0 }) == true
                || NSIntersectionRange(attenuation, use.range).length > 0
                || NSIntersectionRange(output, use.range).length > 0 {
                continue
            }
            let lineRange = sourceNSString.lineRange(for: use.range)
            let line = sourceNSString.substring(with: lineRange)
            let suffixStart = use.range.location + use.range.length
            guard suffixStart <= sourceNSString.length else { return false }
            let suffix = sourceNSString.substring(
                with: NSRange(
                    location: suffixStart,
                    length: sourceNSString.length - suffixStart
                )
            )
            guard let member = captures(
                #"^\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\b"#,
                in: suffix
            )?.first,
                  allowedRGBMembers.contains(member),
                  !regexMatches(
                      #"\b"# + namePattern + #"\s*\.\s*"# + escaped(member)
                          + #"\s*"# + assignmentOperators,
                      line
                  ) else {
                return false
            }
        }
        return true
    }

    /// SPIRV-Cross samples the host's premultiplied color directly into the
    /// authored local. A source-proven alpha-preserving RGB flow must instead
    /// execute in straight color, then return to the compositor's
    /// premultiplied boundary. Both rewrites are required; emitting only the
    /// artifact tag would silently change translucent RGB math.
    static func straightAlphaPreserving(
        _ source: String,
        expectedSlot: Int
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        guard let transformed = SceneGenericShaderStraightAlphaPreservingLowering
            .lowerPreserving(source, expectedSlot: expectedSlot) else { return nil }
        return (
            transformed,
            SceneGenericShaderProgramArtifact.Program.ColorTransfer(
                kind: "straight-alpha-preserving",
                slot: expectedSlot,
                slots: nil
            )
        )
    }

}
