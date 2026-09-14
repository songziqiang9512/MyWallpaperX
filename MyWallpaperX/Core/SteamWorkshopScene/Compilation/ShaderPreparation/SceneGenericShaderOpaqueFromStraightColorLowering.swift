import Foundation

extension SceneGenericShaderStraightAlphaPreservingLowering {
    /// Conserves a source-proven opaque transform whose sampled RGB math is
    /// authored in straight color. The semantic analyzer owns the dataflow;
    /// this pass independently verifies the compiler's exact sample count and
    /// slot before inserting the boundary. Opaque output is left untouched.
    static func lowerOpaqueFromStraightColor(
        _ source: String,
        expectedSlot: Int,
        sampleCount: Int
    ) -> String? {
        guard (1 ... 16).contains(sampleCount),
              !source.contains("mwxGenericUnpremultiply"),
              !source.contains("mwxGenericPremultiply"),
              loweringMatches(
                #"\busing\s+namespace\s+metal\s*;"#,
                in: source
              ).count == 1,
              loweringMatches(
                #"\bout\.mwxFragColor\b"#,
                in: source
              ).count == 1,
              loweringMatches(
                #"(?m)^[ \t]*out\.mwxFragColor\s*=\s*float4\(.+,\s*1(?:\.0+)?\s*\);[ \t]*$"#,
                in: source
              ).count == 1,
              loweringMatches(
                #"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#,
                in: source
              ).count == 1,
              let calls = compilerTextureSampleCalls(in: source),
              calls.count == sampleCount,
              calls.allSatisfy({ $0.slot == expectedSlot }),
              let output = loweringMatches(
                #"(?m)^[ \t]*out\.mwxFragColor\s*="#,
                in: source
              ).first,
              calls.allSatisfy({ $0.range.location < output.range.location }) else {
            return nil
        }
        var transformed = source
        for call in calls.sorted(by: { $0.range.location > $1.range.location }) {
            guard let text = unionSubstring(call.range, in: source),
                  let range = Range(call.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                range,
                with: "mwxGenericUnpremultiply(\(text))"
            )
        }
        return insertingBoundaryHelpers(into: transformed)
    }

    private static func loweringMatches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }
}
