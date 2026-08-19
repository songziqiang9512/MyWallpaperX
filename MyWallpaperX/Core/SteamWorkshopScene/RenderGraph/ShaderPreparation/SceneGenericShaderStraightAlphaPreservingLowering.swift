import Foundation

nonisolated enum SceneGenericShaderStraightAlphaPreservingLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

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
