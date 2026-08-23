import Foundation

/// Proves the fixed compiler shape emitted for a source-proven alpha-weighted
/// same-slot average with lexically isolated immutable sample locals. This is
/// an artifact contract only: the shared color-boundary lowerer consumes its
/// typed replacements after the authored-source analyzer admits the flow.
nonisolated enum SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    struct Fact {
        fileprivate let replacements: [Replacement]

        func applying(to source: String) -> String? {
            var transformed = source
            for replacement in replacements.sorted(by: {
                $0.range.location > $1.range.location
            }) {
                guard let range = Range(replacement.range, in: transformed) else {
                    return nil
                }
                transformed.replaceSubrange(range, with: replacement.value)
            }
            return transformed
        }
    }

    fileprivate struct Replacement {
        let range: NSRange
        let value: String
    }

    static func analyze(
        _ source: String,
        expectedSlot: Int,
        sampleCount: Int
    ) -> Fact? {
        guard (1 ... 16).contains(sampleCount),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              matches(#"\b(if|for|while|do|switch|discard)\b"#, in: source).isEmpty
        else { return nil }

        let normalizedDeclarations = matches(
            #"(?m)^([ \t]*)float3\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.xyz\s*/\s*float3\(\s*fast::max\(\s*([0-9]+(?:\.[0-9]+)?)\s*,\s*([A-Za-z_]\w*)\s*\)\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard normalizedDeclarations.count == 1,
              let normalizedDeclaration = normalizedDeclarations.first,
              let indent = capture(normalizedDeclaration, 1, in: source),
              let normalized = capture(normalizedDeclaration, 2, in: source),
              let accumulator = capture(normalizedDeclaration, 3, in: source),
              let weight = capture(normalizedDeclaration, 5, in: source),
              Double(capture(normalizedDeclaration, 4, in: source) ?? "").map({
                  $0.isFinite && $0 > 0
              }) == true else { return nil }

        let componentWrites = ["x", "y", "z"].compactMap { component in
            matches(
                #"(?m)^[ \t]*out\.mwxFragColor\."# + component
                    + #"\s*=\s*"# + escaped(normalized) + #"\."#
                    + component + #"\s*;[ \t]*$"#,
                in: source
            ).only
        }
        let denominator = String(sampleCount) + #"(?:\.0+)?"#
        let alphaWrites = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\.w\s*=\s*"#
                + escaped(accumulator) + #"\.w\s*/\s*"# + denominator
                + #"\s*;[ \t]*$"#,
            in: source
        )
        guard componentWrites.count == 3, alphaWrites.count == 1,
              let alphaWrite = alphaWrites.first,
              normalizedDeclaration.range.location < componentWrites[0].range.location,
              componentWrites[0].range.location < componentWrites[1].range.location,
              componentWrites[1].range.location < componentWrites[2].range.location,
              componentWrites[2].range.location < alphaWrite.range.location,
              terminalTail(after: alphaWrite.range, in: source),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 4
        else { return nil }

        let outputRange = NSRange(
            location: normalizedDeclaration.range.location,
            length: NSMaxRange(alphaWrite.range)
                - normalizedDeclaration.range.location
        )
        let samplePattern = #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
            + String(expectedSlot) + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#
        let samples = matches(samplePattern, in: source)
        guard samples.count == sampleCount,
              matches(#"\bg_Texture[0-7]\.sample\s*\("#, in: source).count
                == sampleCount,
              Set(samples.compactMap({ capture($0, 2, in: source) })).count
                == sampleCount,
              samples.allSatisfy({ $0.range.location < outputRange.location })
        else { return nil }

        let accumulatorPattern = escaped(accumulator)
        let weightPattern = escaped(weight)
        guard matches(
            #"(?m)^[ \t]*float4\s+"# + accumulatorPattern
                + #"\s*=\s*float4\(\s*0(?:\.0+)?\s*\)\s*;[ \t]*$"#,
            in: source
        ).count == 1,
        matches(
            #"(?m)^[ \t]*float\s+"# + weightPattern
                + #"\s*=\s*0(?:\.0+)?\s*;[ \t]*$"#,
            in: source
        ).count == 1,
        countWord(accumulator, in: source) == sampleCount + 3,
        countWord(weight, in: source) == sampleCount + 2,
        countWord(normalized, in: source) == 4 else { return nil }

        var replacements: [Replacement] = [
            .init(
                range: outputRange,
                value: "\(indent)out.mwxFragColor = \(premultiply)(float4(\(accumulator).xyz, \(accumulator).w / \(sampleCount).0));"
            ),
        ]
        for sampleMatch in samples {
            guard let sample = capture(sampleMatch, 2, in: source),
                  let prefix = capture(sampleMatch, 1, in: source),
                  let arguments = capture(sampleMatch, 3, in: source),
                  let suffix = capture(sampleMatch, 4, in: source) else {
                return nil
            }
            let sampleName = escaped(sample)
            let accumulatorWrites = matches(
                #"(?m)^[ \t]*"# + accumulatorPattern + #"\s*\+=\s*\(\s*"#
                    + sampleName + #"\s*\*\s*"# + sampleName
                    + #"\.w\s*\)\s*;[ \t]*$"#,
                in: source
            )
            let weightWrites = matches(
                #"(?m)^[ \t]*"# + weightPattern + #"\s*\+=\s*"#
                    + sampleName + #"\.w\s*;[ \t]*$"#,
                in: source
            )
            guard accumulatorWrites.count == 1, weightWrites.count == 1,
                  sampleMatch.range.location < accumulatorWrites[0].range.location,
                  accumulatorWrites[0].range.location < weightWrites[0].range.location,
                  weightWrites[0].range.location < outputRange.location,
                  countWord(sample, in: source) == 4 else { return nil }
            replacements.append(.init(
                range: sampleMatch.range,
                value: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
            ))
        }
        return .init(replacements: replacements)
    }

    private static func terminalTail(after output: NSRange, in source: String) -> Bool {
        let tailLocation = NSMaxRange(output)
        guard tailLocation <= (source as NSString).length else { return false }
        let tail = (source as NSString).substring(from: tailLocation)
        return matches(#"^\s*return\s+out\s*;\s*\}\s*$"#, in: tail).count == 1
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String, in source: String
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    private static func capture(
        _ match: NSTextCheckingResult, _ index: Int, in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
