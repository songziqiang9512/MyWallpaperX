import Foundation

extension SceneGenericShaderArtifactBuilder {
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
