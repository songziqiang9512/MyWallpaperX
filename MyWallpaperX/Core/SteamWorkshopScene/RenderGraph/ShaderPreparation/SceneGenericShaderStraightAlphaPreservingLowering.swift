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
            return lowerComposed(source, expectedSlot: expectedSlot)
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
