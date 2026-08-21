import Foundation

nonisolated enum SceneGenericShaderStraightAlphaPreservingLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    /// SPIRV-Cross samples the host's premultiplied color directly into the
    /// authored local. A source-proven alpha-preserving RGB flow must instead
    /// execute in straight color, then return to the compositor boundary.
    static func lowerPreserving(_ source: String, expectedSlot: Int) -> String? {
        guard !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source) else { return nil }
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard declarations.count == 1 else {
            return lowerDirectComponentReconstruction(
                source,
                expectedSlot: expectedSlot
            ) ?? lowerComposed(source, expectedSlot: expectedSlot)
        }
        guard let prefix = capture(declarations[0], 1, in: source),
              let local = capture(declarations[0], 2, in: source),
              let arguments = capture(declarations[0], 3, in: source),
              let suffix = capture(declarations[0], 4, in: source),
              !prefix.isEmpty, !local.isEmpty,
              !arguments.isEmpty, !suffix.isEmpty else { return nil }
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*"#
                + escaped(local) + #"\s*;[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              declarations[0].range.location < outputs[0].range.location,
              let outputRange = Range(outputs[0].range, in: source),
              let indent = capture(outputs[0], 1, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(local));"
        )
        guard let adjustedDeclarationRange = Range(
            declarations[0].range,
            in: transformed
        ) else { return nil }
        transformed.replaceSubrange(
            adjustedDeclarationRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
        )
        return insertingBoundaryHelpers(into: transformed)
    }

    /// Conserves a source-proven, same-slot RGB component reconstruction
    /// through SPIRV-Cross. The authored analyzer owns the semantic proof; this
    /// pass independently verifies the corresponding compiler shape before
    /// moving all samples into straight color and restoring the one compositor
    /// boundary at output.
    static func lowerDirectComponentReconstruction(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        guard !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
        else { return nil }
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let allSampleCalls = matches(
            #"\bg_Texture[0-7]\.sample\s*\("#,
            in: source
        )
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard declarations.count >= 2,
              allSampleCalls.count == declarations.count,
              outputs.count == 1,
              let output = outputs.first,
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let carrier = capture(output, 2, in: source),
              declarations.allSatisfy({ $0.range.location < output.range.location })
        else { return nil }

        let sampledNames = declarations.compactMap { capture($0, 2, in: source) }
        guard sampledNames.count == declarations.count,
              Set(sampledNames).count == sampledNames.count else { return nil }
        let carrierPattern = escaped(carrier)
        let carrierDefinitions = matches(
            #"(?m)^[ \t]*float4\s+"# + carrierPattern
                + #"\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard carrierDefinitions.count == 1,
              let base = capture(carrierDefinitions[0], 1, in: source),
              sampledNames.contains(base),
              carrierDefinitions[0].range.location < output.range.location else {
            return nil
        }
        let writes = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\.([xyz])\s*=\s*([A-Za-z_]\w*)\.([xyz])\s*;[ \t]*$"#,
            in: source
        )
        let writeComponents = writes.compactMap { capture($0, 1, in: source) }
        let writeSources = writes.compactMap { capture($0, 2, in: source) }
        let sourceComponents = writes.compactMap { capture($0, 3, in: source) }
        guard !writes.isEmpty,
              writeComponents.count == writes.count,
              writeSources.count == writes.count,
              sourceComponents.count == writes.count,
              writeComponents == sourceComponents,
              Set(writeComponents).count == writes.count,
              Set(writeSources).count == writes.count,
              !writeSources.contains(base),
              Set(sampledNames) == Set(writeSources + [base]),
              writes.allSatisfy({
                  carrierDefinitions[0].range.location < $0.range.location
                      && $0.range.location < output.range.location
              }),
              countWord(base, in: source) == 2,
              writeSources.allSatisfy({ countWord($0, in: source) == 2 }),
              countWord(carrier, in: source) == writes.count + 2,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1 else {
            return nil
        }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(carrier));"
        )
        for declaration in declarations.sorted(by: { $0.range.location > $1.range.location }) {
            guard let prefix = capture(declaration, 1, in: source),
                  let arguments = capture(declaration, 3, in: source),
                  let suffix = capture(declaration, 4, in: source),
                  let range = Range(declaration.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                range,
                with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            )
        }
        return insertingBoundaryHelpers(into: transformed)
    }

    static func lowerComposed(_ source: String, expectedSlot: Int) -> String? {
        guard !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source) else { return nil }
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*float4\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)(?:\.w)?\s*\);[ \t]*$"#,
            in: source
        )
        guard !declarations.isEmpty, outputs.count == 1,
              let output = outputs.first,
              let outputRange = Range(output.range, in: source),
              let colorName = capture(output, 2, in: source),
              let alphaName = capture(output, 3, in: source),
              let indent = capture(output, 1, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1 else {
            return nil
        }
        let sampledNames = declarations.compactMap { capture($0, 2, in: source) }
        guard sampledNames.count == declarations.count,
              Set(sampledNames).count == sampledNames.count,
              colorName != alphaName,
              declarations.allSatisfy({ $0.range.location < output.range.location }),
              sampledNames.contains(where: { sampled in
                  source.range(of: "float \(alphaName) = \(sampled).w;") != nil
              }) else {
            return nil
        }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(float4(\(colorName), \(alphaName)));"
        )
        for declaration in declarations.sorted(by: { $0.range.location > $1.range.location }) {
            guard let prefix = capture(declaration, 1, in: source),
                  let arguments = capture(declaration, 3, in: source),
                  let suffix = capture(declaration, 4, in: source),
                  let declarationRange = Range(declaration.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                declarationRange,
                with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            )
        }
        let helpers = """

inline float4 \(unpremultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}

inline float4 \(premultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    return float4(color.xyz * alpha, alpha);
}
"""
        guard let namespace = transformed.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        transformed.insert(contentsOf: helpers, at: namespace.upperBound)
        return transformed
    }

    /// Applies one straight-color boundary to a source-proven conditional
    /// union whose terminal branches either forward the base sample or write
    /// RGB and alpha independently. The source analyzer owns branch semantics;
    /// this verifier only accepts the corresponding bounded compiler shape.
    static func lowerConditionalUnion(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        guard !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1 else {
            return nil
        }
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let outputWrites = matches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\.([xyzwrgba]{1,4}))?\s*="#,
            in: source
        )
        let wholeWrites = outputWrites.filter {
            capture($0, 1, in: source) == nil
        }
        let componentWrites = outputWrites.compactMap {
            capture($0, 1, in: source)
        }.sorted()
        let completeColorWrite = componentWrites == ["w", "xyz"]
            || componentWrites == ["w", "x", "y", "z"]
        let returns = matches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: source
        )
        guard declarations.count == 2,
              wholeWrites.count == 2,
              completeColorWrite,
              returns.count == 1,
              let terminalReturn = returns.first,
              let returnIndent = capture(terminalReturn, 1, in: source),
              declarations.allSatisfy({ $0.range.location < terminalReturn.range.location }),
              outputWrites.allSatisfy({ $0.range.location < terminalReturn.range.location }),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count
                == outputWrites.count else {
            return nil
        }

        var transformed = source
        guard let returnRange = Range(terminalReturn.range, in: transformed) else {
            return nil
        }
        transformed.replaceSubrange(
            returnRange,
            with: "\(returnIndent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                + "\(returnIndent)return out;"
        )
        for declaration in declarations.sorted(by: { $0.range.location > $1.range.location }) {
            guard let prefix = capture(declaration, 1, in: source),
                  let arguments = capture(declaration, 3, in: source),
                  let suffix = capture(declaration, 4, in: source),
                  let range = Range(declaration.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                range,
                with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            )
        }
        return insertingBoundaryHelpers(into: transformed)
    }

    /// The authored analyzer may prove a complete straight-alpha output whose
    /// alpha is produced independently of the sampled scene. Verify the
    /// corresponding bounded compiler shape, then apply the same
    /// unpremultiply/premultiply compositor boundary. The analyzer remains the
    /// semantic authority; this pass only conserves that fact through MSL.
    static func lowerStraightOutput(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        guard !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1 else {
            return nil
        }
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*float4\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\);[ \t]*$"#,
            in: source
        )
        guard !declarations.isEmpty, outputs.count == 1,
              let output = outputs.first,
              let outputRange = Range(output.range, in: source),
              let colorName = capture(output, 2, in: source),
              let alphaName = capture(output, 3, in: source),
              let indent = capture(output, 1, in: source),
              colorName != alphaName,
              declarations.allSatisfy({ $0.range.location < output.range.location }),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1 else {
            return nil
        }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(float4(\(colorName), \(alphaName)));"
        )
        for declaration in declarations.sorted(by: { $0.range.location > $1.range.location }) {
            guard let prefix = capture(declaration, 1, in: source),
                  let arguments = capture(declaration, 3, in: source),
                  let suffix = capture(declaration, 4, in: source),
                  let range = Range(declaration.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                range,
                with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            )
        }
        return insertingBoundaryHelpers(into: transformed)
    }

    /// Conserves a source-proven alpha-weighted same-slot sample average
    /// through the fixed SPIRV-Cross shape. Every sample enters authored math
    /// as straight color and the one terminal result returns to premultiplied
    /// compositor storage. The source analyzer owns the semantic proof; this
    /// verifier rejects compiler drift, hidden samples, and count mismatch.
    static func lowerAlphaWeightedSampleAverage(
        _ source: String,
        expectedSlot: Int,
        sampleCount: Int
    ) -> String? {
        guard (1 ... 16).contains(sampleCount),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              matches(#"\b(if|for|while|do|switch|discard)\b"#, in: source).isEmpty
        else { return nil }

        let denominator = String(sampleCount) + #"(?:\.0+)?"#
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*float4\(\s*([A-Za-z_]\w*)\.xyz\s*,\s*\2\.w\s*/\s*"#
                + denominator + #"\s*\);[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              let output = outputs.first,
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let accumulator = capture(output, 2, in: source),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1 else {
            return nil
        }

        let firstSamples = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard firstSamples.count == 1,
              let firstSample = firstSamples.first,
              let sample = capture(firstSample, 2, in: source) else { return nil }
        let repeatedSamples = matches(
            #"(?m)^([ \t]*"# + escaped(sample)
                + #"\s*=\s*)g_Texture"# + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let sampleStatements = firstSamples + repeatedSamples
        guard sampleStatements.count == sampleCount,
              matches(#"\bg_Texture[0-7]\.sample\s*\("#, in: source).count
                == sampleCount,
              sampleStatements.allSatisfy({ $0.range.location < output.range.location })
        else { return nil }

        let accumulatorPattern = escaped(accumulator)
        let samplePattern = escaped(sample)
        let accumulatorDeclarations = matches(
            #"(?m)^[ \t]*float4\s+"# + accumulatorPattern
                + #"\s*=\s*float4\(\s*0(?:\.0+)?\s*\)\s*;[ \t]*$"#,
            in: source
        )
        let accumulatorWrites = matches(
            #"(?m)^[ \t]*"# + accumulatorPattern + #"\s*\+=\s*\(\s*"#
                + samplePattern + #"\s*\*\s*"# + samplePattern
                + #"\.w\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard accumulatorDeclarations.count == 1,
              accumulatorWrites.count == sampleCount else { return nil }

        let weightDeclarations = matches(
            #"(?m)^[ \t]*float\s+([A-Za-z_]\w*)\s*=\s*0(?:\.0+)?\s*;[ \t]*$"#,
            in: source
        ).filter { match in
            guard let name = capture(match, 1, in: source) else { return false }
            return matches(
                #"(?m)^[ \t]*"# + escaped(name) + #"\s*\+=\s*"#
                    + samplePattern + #"\.w\s*;[ \t]*$"#,
                in: source
            ).count == sampleCount
        }
        guard weightDeclarations.count == 1,
              let weight = capture(weightDeclarations[0], 1, in: source) else {
            return nil
        }
        let weightPattern = escaped(weight)

        let accumulatorCopies = matches(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                + accumulatorPattern + #"\s*;[ \t]*$"#,
            in: source
        )
        guard accumulatorCopies.count == 1,
              let copy = capture(accumulatorCopies[0], 1, in: source) else {
            return nil
        }
        let normalizedDeclarations = matches(
            #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(copy)
                + #"\.xyz\s*/\s*float3\(\s*fast::max\(\s*[0-9]+(?:\.[0-9]+)?\s*,\s*"#
                + weightPattern + #"\s*\)\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard normalizedDeclarations.count == 1,
              let normalized = capture(normalizedDeclarations[0], 1, in: source),
              ["x", "y", "z"].allSatisfy({ component in
                  matches(
                      #"(?m)^[ \t]*"# + accumulatorPattern + #"\."#
                          + component + #"\s*=\s*"# + escaped(normalized)
                          + #"\."# + component + #"\s*;[ \t]*$"#,
                      in: source
                  ).count == 1
              }),
              countWord(accumulator, in: source) == sampleCount + 7,
              countWord(sample, in: source) == sampleCount * 4,
              countWord(weight, in: source) == sampleCount + 2,
              countWord(copy, in: source) == 2,
              countWord(normalized, in: source) == 4 else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(float4(\(accumulator).xyz, \(accumulator).w / \(sampleCount).0));"
        )
        for statement in sampleStatements.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            let isDeclaration = statement.numberOfRanges == 5
            let prefixIndex = 1
            let argumentsIndex = isDeclaration ? 3 : 2
            let suffixIndex = isDeclaration ? 4 : 3
            guard let prefix = capture(statement, prefixIndex, in: source),
                  let arguments = capture(statement, argumentsIndex, in: source),
                  let suffix = capture(statement, suffixIndex, in: source),
                  let range = Range(statement.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                range,
                with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            )
        }
        return insertingBoundaryHelpers(into: transformed)
    }

    private static func insertingBoundaryHelpers(into source: String) -> String? {
        let helpers = """

inline float4 \(unpremultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}

inline float4 \(premultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    return float4(color.xyz * alpha, alpha);
}
"""
        guard let namespace = source.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        var transformed = source
        transformed.insert(contentsOf: helpers, at: namespace.upperBound)
        return transformed
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
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

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }
}
