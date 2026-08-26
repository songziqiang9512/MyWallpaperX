import Foundation

extension SceneGenericShaderArtifactBuilder {
    static func prepareColorTransfer(
        msl source: String,
        authoredSource: String
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
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
        case .premultipliedAlpha:
            return (source, artifactTransfer(kind: "premultiplied"))
        case let .straightAlpha(textureSlot: expectedSlot):
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
            let lowered = weightedLowering
                ?? scalarAlphaLowering
                ?? (direct?.transfer.slot == expectedSlot ? direct?.msl : nil)
                ?? SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerConditionalUnion(source, expectedSlot: expectedSlot)
                    ?? SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerStraightOutput(source, expectedSlot: expectedSlot)
            guard let lowered else { throw Failure.colorTransfer }
            return (lowered, artifactTransfer(kind: "straight-alpha", slot: expectedSlot))
        case let .straightAlphaPreserving(textureSlot: expectedSlot):
            let preserving: (
                msl: String,
                transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
            )?
            if let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
                .analyze(fragmentSource: authoredSource) {
                guard fact.blurredSlot == expectedSlot,
                      let lowered =
                        SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                            source,
                            expectedBlurredSlot: expectedSlot,
                            expectedPreviousSlot: fact.previousSlot,
                            expectedMaskSlot: fact.maskSlot
                        ) else { throw Failure.colorTransfer }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
                .analyzeAny(fragmentSource: authoredSource) {
                guard fact.sourceSlot == expectedSlot,
                      let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                        .lowerPreservedAlphaRGBFilter(
                            source,
                            sourceSlot: fact.sourceSlot,
                            fullColorSampleCallCounts:
                                fact.fullColorSampleCallCounts,
                            rgbColorSampleCallCounts:
                                fact.rgbColorSampleCallCounts,
                            dataSampleCallCounts: fact.dataSampleCallCounts
                        ) else { throw Failure.colorTransfer }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer
                .analyze(fragmentSource: authoredSource) {
                guard fact.sourceSlot == expectedSlot,
                      let lowered = SceneGenericShaderTypedDataRGBFilterLowering
                        .lower(source, fact: fact) else {
                    throw Failure.colorTransfer
                }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else if let fact =
                SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer
                    .analyze(fragmentSource: authoredSource) {
                guard fact.sourceSlot == expectedSlot,
                      let lowered =
                        SceneGenericShaderSameAlphaReconstructedRGBFilterLowering
                            .lower(source, fact: fact) else {
                    throw Failure.colorTransfer
                }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else if let fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer
                .analyze(fragmentSource: authoredSource) {
                guard fact.alphaCarrierSlot == expectedSlot,
                      let lowered = SceneGenericShaderConditionalGeneratedRGBLowering
                        .lower(source, fact: fact) else {
                    throw Failure.colorTransfer
                }
                preserving = (
                    msl: lowered,
                    transfer: artifactTransfer(
                        kind: "straight-alpha-preserving",
                        slot: expectedSlot
                    )
                )
            } else {
                preserving = straightAlphaPreserving(
                    source,
                    expectedSlot: expectedSlot
                )
            }
            guard let preserving else {
                throw Failure.colorTransfer
            }
            return preserving
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
        case .straightAlphaUNorm:
            throw Failure.colorTransfer
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

    static func artifactTransfer(
        kind: String,
        slot: Int? = nil
    ) -> SceneGenericShaderProgramArtifact.Program.ColorTransfer {
        .init(kind: kind, slot: slot, slots: nil)
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
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
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
              }) else { return nil }

        let carrierDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(fact.sourceSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let carrierDeclaration = carrierDeclarations.first,
              let carrier = capture(carrierDeclaration, 2, in: source)
        else { return nil }

        let aliases = matches(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(carrier) + #"\s*;[ \t]*$"#,
            in: source
        )
        guard aliases.count == 1,
              let alias = aliases.first,
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
              colorWrites.count == 1,
              capture(colorWrites[0], 1, in: source) == "w",
              let alphaWrite = alphaWrites.first,
              let factor = capture(alphaWrite, 1, in: source),
              !containsWord(color, in: factor) else { return nil }

        let outputPatterns = [
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*float3\(\s*0(?:\.0+)?\s*\)\s*,\s*([A-Za-z_]\w*)\.xyz\s*\)\s*,\s*([A-Za-z_]\w*)\.w\s*\))\s*;[ \t]*$"#,
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*([A-Za-z_]\w*)\.xyz\s*,\s*float3\(\s*0(?:\.0+)?\s*\)\s*\)\s*,\s*([A-Za-z_]\w*)\.w\s*\))\s*;[ \t]*$"#,
        ]
        let outputs = outputPatterns.flatMap { matches($0, in: source) }
        let returns = matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source)
        guard outputs.count == 1,
              returns.count == 1,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let output = outputs.first,
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let outputValue = capture(output, 2, in: source),
              capture(output, 3, in: source) == color,
              capture(output, 4, in: source) == color,
              countWord(carrier, in: source) == 2,
              countWord(color, in: source) == 4,
              carrierDeclaration.range.location < alias.range.location,
              alias.range.location < alphaWrite.range.location,
              alphaWrite.range.location < output.range.location,
              output.range.location < returns[0].range.location,
              sampleCalls.allSatisfy({ $0.range.location < output.range.location })
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
