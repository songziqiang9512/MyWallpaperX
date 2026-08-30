import Foundation

/// Conserves a source-proven generated straight-RGBA terminal through the
/// fixed SPIRV-Cross output shape. No texture boundary is introduced because
/// the authored proof requires the complete reachable source to be sample-free.
nonisolated enum SceneGenericShaderGeneratedStraightRGBALowering {
    static func prepare(
        _ source: String,
        authoredSource: String
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        guard SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil, let lowered = lower(source) else { return nil }
        return (
            lowered,
            .init(kind: "generated-straight-alpha", slot: nil, slots: nil)
        )
    }

    static func lower(_ source: String) -> String? {
        guard !containsWord("mwxGenericUnpremultiply", in: source),
              !containsWord("mwxGenericPremultiply", in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              matches(#"\b[A-Za-z_]\w*\.sample\s*\("#, in: source).isEmpty,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1
        else { return nil }
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\([^;]+\))\s*;[ \t]*$"#,
            in: source
        )
        let returns = matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source)
        guard outputs.count == 1, returns.count == 1,
              let output = outputs.first,
              output.range.location < returns[0].range.location,
              let range = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let value = capture(output, 2, in: source) else { return nil }
        var transformed = source
        transformed.replaceSubrange(
            range,
            with: "\(indent)out.mwxFragColor = mwxGenericPremultiply(\(value));"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#,
            in: source
        ).isEmpty
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )) ?? []
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}
