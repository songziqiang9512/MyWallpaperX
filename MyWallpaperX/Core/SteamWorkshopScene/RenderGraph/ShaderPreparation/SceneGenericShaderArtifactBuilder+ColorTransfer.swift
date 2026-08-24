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
