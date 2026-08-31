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

    static func prepareColorTransfer(
        msl source: String,
        authoredSource: String,
        expectedColorTransfer: SceneGenericShaderExpectedColorTransfer? = nil
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
        case .unresolved:
            // A compiler artifact may prove a form outside the bounded source
            // analyzer. The cache consumer still rejects any artifact that
            // contradicts a source fact that the shared analyzer did prove.
            return try prepareCompilerProvenColorTransfer(source)
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
        case ("opaque", nil, nil), ("premultiplied", nil, nil),
             ("generated-straight-alpha", nil, nil),
             ("red-green-unorm-data", nil, nil),
             ("preserved-rgba-data", nil, nil):
            return true
        default:
            return false
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

    /// Conserves the source-proven straight-RGB/scalar-alpha shape through
    /// SPIRV-Cross without treating auxiliary data textures as color. The
    /// authored analyzer owns the semantic proof; this only verifies the
    /// corresponding compiler shape before inserting compositor boundaries.
    static func lowerStraightRGBScalarAlpha(
        _ source: String,
        fact: SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer.Fact
    ) -> String? {
        guard !containsWord("mwxGenericUnpremultiply", in: source),
              !containsWord("mwxGenericPremultiply", in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = straightRGBScalarAlphaFragmentBodyRange(in: source),
              straightRGBScalarAlphaCompilerBodyIsLinear(body, source: source)
        else { return nil }

        let expectedSlots = fact.auxiliarySlots.union([fact.sourceSlot])
        let sampleCalls = matches(#"\bg_Texture([0-7])\.sample\("#, in: source)
        let sampledSlots = sampleCalls.compactMap {
            capture($0, 1, in: source).flatMap(Int.init)
        }
        guard sampledSlots.count == sampleCalls.count,
              sampledSlots.count == expectedSlots.count,
              Set(sampledSlots) == expectedSlots,
              Set(sampledSlots).allSatisfy({ slot in
                  sampledSlots.filter({ $0 == slot }).count == 1
              }),
              sampleCalls.allSatisfy({
                  straightRGBScalarAlphaRange(body, contains: $0.range)
              }) else { return nil }

        let carrierDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(fact.sourceSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let carrierDeclaration = carrierDeclarations.first,
              straightRGBScalarAlphaRange(
                  body, contains: carrierDeclaration.range
              ),
              let carrier = capture(carrierDeclaration, 2, in: source)
        else { return nil }

        let aliases = matches(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(carrier) + #"\s*;[ \t]*$"#,
            in: source
        )
        guard aliases.count == 1,
              let alias = aliases.first,
              straightRGBScalarAlphaRange(body, contains: alias.range),
              let color = capture(alias, 1, in: source),
              color != carrier else { return nil }

        let alphaWrites = matches(
            #"(?m)^[ \t]*"# + escaped(color)
                + #"\.w\s*\*=\s*([^;]+)\s*;[ \t]*$"#,
            in: source
        )
        let colorWrites = matches(
            #"(?m)^[ \t]*"# + escaped(color)
                + #"(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=)"#,
            in: source
        )
        guard alphaWrites.count == 1,
              let alphaWrite = alphaWrites.first,
              straightRGBScalarAlphaRange(body, contains: alphaWrite.range),
              let factor = capture(alphaWrite, 1, in: source),
              !containsWord(color, in: factor) else { return nil }

        let maskMix: StraightRGBScalarAlphaMaskMix?
        if let slot = fact.maskSlot, let maskFactor = fact.maskFactorName {
            guard let proven = straightRGBScalarAlphaMaskMix(
                source: source,
                sourceCarrier: carrier,
                transformedCarrier: color,
                slot: slot,
                factor: maskFactor
            ), straightRGBScalarAlphaRange(
                body, contains: proven.declarationRange
            ), straightRGBScalarAlphaRange(
                body, contains: proven.assignmentRange
            ), alphaWrite.range.location < proven.declarationRange.location,
               proven.declarationRange.location < proven.assignmentRange.location
            else { return nil }
            maskMix = proven
        } else {
            guard fact.maskSlot == nil, fact.maskFactorName == nil else {
                return nil
            }
            maskMix = nil
        }
        guard colorWrites.count == 1 + (maskMix == nil ? 0 : 1),
              colorWrites.allSatisfy({ write in
                  straightRGBScalarAlphaRange(
                      alphaWrite.range, contains: write.range
                  )
                    || maskMix.map {
                        straightRGBScalarAlphaRange(
                            $0.assignmentRange, contains: write.range
                        )
                    } == true
              }) else { return nil }

        let outputPatterns: [String]
        switch fact.terminalTransform {
        case .nonNegativeRGBPreservedAlpha:
            outputPatterns = [
                #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*float3\(\s*0(?:\.0+)?\s*\)\s*,\s*([A-Za-z_]\w*)\.xyz\s*\)\s*,\s*([A-Za-z_]\w*)\.w\s*\))\s*;[ \t]*$"#,
                #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*([A-Za-z_]\w*)\.xyz\s*,\s*float3\(\s*0(?:\.0+)?\s*\)\s*\)\s*,\s*([A-Za-z_]\w*)\.w\s*\))\s*;[ \t]*$"#,
            ]
        case .saturateRGBA:
            outputPatterns = [
                #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*((?:fast::)?clamp\(\s*([A-Za-z_]\w*)\s*,\s*float4\(\s*0(?:\.0+)?f?\s*\)\s*,\s*float4\(\s*1(?:\.0+)?f?\s*\)\s*\))\s*;[ \t]*$"#,
            ]
        }
        let outputs = outputPatterns.flatMap { matches($0, in: source) }
        let returns = matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source)
        guard outputs.count == 1,
              returns.count == 1,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let output = outputs.first,
              straightRGBScalarAlphaRange(body, contains: output.range),
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let outputValue = capture(output, 2, in: source),
              capture(output, 3, in: source) == color,
              fact.terminalTransform == .saturateRGBA
                || capture(output, 4, in: source) == color,
              countWord(carrier, in: source) == (maskMix == nil ? 2 : 3),
              countWord(color, in: source)
                == (maskMix == nil ? 4 : 6)
                    - (fact.terminalTransform == .saturateRGBA ? 1 : 0),
              carrierDeclaration.range.location < alias.range.location,
              alias.range.location < alphaWrite.range.location,
              alphaWrite.range.location < output.range.location,
              maskMix.map({
                  $0.assignmentRange.location < output.range.location
              }) ?? true,
              output.range.location < returns[0].range.location,
              sampleCalls.allSatisfy({ $0.range.location < output.range.location }),
              straightRGBScalarAlphaTerminalTail(
                  after: output.range, within: body, source: source
              )
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = mwxGenericPremultiply(\(outputValue));"
        )
        guard let prefix = capture(carrierDeclaration, 1, in: source),
              let arguments = capture(carrierDeclaration, 3, in: source),
              let suffix = capture(carrierDeclaration, 4, in: source),
              let adjustedCarrierRange = Range(carrierDeclaration.range, in: transformed)
        else { return nil }
        transformed.replaceSubrange(
            adjustedCarrierRange,
            with: "\(prefix)mwxGenericUnpremultiply(g_Texture\(fact.sourceSlot).sample(\(arguments)))\(suffix)"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private struct StraightRGBScalarAlphaMaskMix {
        let declarationRange: NSRange
        let assignmentRange: NSRange
    }

    private static func straightRGBScalarAlphaRange(
        _ outer: NSRange,
        contains inner: NSRange
    ) -> Bool {
        outer.location <= inner.location
            && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func straightRGBScalarAlphaFragmentBodyRange(
        in source: String
    ) -> NSRange? {
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
        guard signatures.count == 1,
              let signature = signatures.first,
              let signatureRange = Range(signature.range, in: source),
              let open = source[..<signatureRange.upperBound].lastIndex(of: "{")
        else { return nil }
        var depth = 0
        var cursor = open
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return NSRange(source.index(after: open) ..< cursor, in: source)
                }
                if depth < 0 { return nil }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func straightRGBScalarAlphaCompilerBodyIsLinear(
        _ body: NSRange,
        source: String
    ) -> Bool {
        let text = (source as NSString).substring(with: body)
        return matches(
            #"\b(?:if|else|for|while|do|switch|discard)\b"#,
            in: text
        ).isEmpty && matches(#"\breturn\b"#, in: text).count == 1
    }

    private static func straightRGBScalarAlphaTerminalTail(
        after output: NSRange,
        within body: NSRange,
        source: String
    ) -> Bool {
        guard NSMaxRange(output) <= NSMaxRange(body) else { return false }
        let tail = (source as NSString).substring(with: NSRange(
            location: NSMaxRange(output),
            length: NSMaxRange(body) - NSMaxRange(output)
        ))
        return matches(#"^\s*return\s+out\s*;\s*$"#, in: tail).count == 1
    }

    private static func straightRGBScalarAlphaMaskMix(
        source: String,
        sourceCarrier: String,
        transformedCarrier: String,
        slot: Int,
        factor: String
    ) -> StraightRGBScalarAlphaMaskMix? {
        let declarations = matches(
            #"(?m)^[ \t]*float\s+"# + escaped(factor)
                + #"\s*=\s*g_Texture"# + String(slot)
                + #"\.sample\([^;]+\)\.(?:x|r)\s*;[ \t]*$"#,
            in: source
        )
        let assignments = matches(
            #"(?m)^[ \t]*"# + escaped(transformedCarrier)
                + #"\s*=\s*(?:fast::)?(?:mix|lerp)\(\s*"#
                + escaped(sourceCarrier) + #"\s*,\s*"#
                + escaped(transformedCarrier)
                + #"\s*,\s*(?:(?:float4|half4)\(\s*"#
                + escaped(factor) + #"\s*\)|"#
                + escaped(factor) + #")\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard declarations.count == 1,
              assignments.count == 1,
              let declaration = declarations.first,
              let assignment = assignments.first,
              countWord(factor, in: source) == 2 else { return nil }
        return .init(
            declarationRange: declaration.range,
            assignmentRange: assignment.range
        )
    }

    static func premultipliedAccumulator(_ source: String, assignment: String) -> Bool {
        guard let name = captures(
            #"^\s*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;$"#,
            in: assignment
        )?.first else { return false }
        let n = escaped(name)
        guard regexMatches(#"float4\s+"# + n + #"\s*=\s*float4\(\s*0(?:\.0+)?\s*\)\s*;"#, source),
              regexMatches(
                #"float3\s+[A-Za-z_]\w*\s*\([^)]*thread\s+const\s+float3&[^)]*thread\s+const\s+float3&[^)]*thread\s+const\s+float&[^)]*\)\s*\{\s*return\s+([A-Za-z_]\w*)\s*\+\s*\(\s*([A-Za-z_]\w*)\s*\*\s*([A-Za-z_]\w*)\s*\)\s*;\s*\}"#,
                source
              ),
              regexMatches(#"\(\s*31\s*,"#, source),
              regexMatches(n + #"\.w\s*=\s*fast::max\(\s*"# + n + #"\.w\s*,"#, source) else {
            return false
        }
        return capturesAll(
            #"(?m)^\s*"# + n + #"\.([xyzw])\s*="#,
            in: source,
            group: 1
        ) == ["x", "y", "z", "w"]
    }
}
