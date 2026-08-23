import Foundation

/// Restores the compositor's premultiplied boundary for the exact authored
/// unit composite proved by
/// `SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer`. The compiler
/// shape is checked independently so a source fact cannot authorize a rewrite
/// after SPIRV-Cross output drifts.
nonisolated enum SceneGenericShaderUnitPreviousBlurredCompositeLowering {
    private struct Match {
        let range: NSRange
        let captures: [String]
    }

    static func lower(
        _ source: String,
        expectedBlurredSlot: Int,
        expectedPreviousSlot: Int
    ) -> String? {
        guard (0 ..< 8).contains(expectedBlurredSlot),
              (0 ..< 8).contains(expectedPreviousSlot),
              expectedBlurredSlot != expectedPreviousSlot,
              !source.contains("mwxGenericPremultiply"),
              !source.contains("mwxGenericUnpremultiply") else { return nil }

        let blurredPattern = #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*g_Texture"#
            + String(expectedBlurredSlot)
            + #"\.sample\([^;]+\)\s*;\s*$"#
        let previousPattern = #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*g_Texture"#
            + String(expectedPreviousSlot)
            + #"\.sample\([^;]+\)\s*;\s*$"#
        guard let blurredSample = unique(blurredPattern, in: source),
              let previousSample = unique(previousPattern, in: source),
              let blurred = blurredSample.captures.first,
              let previous = previousSample.captures.first,
              blurred != previous,
              sampleCalls(in: source) == [
                  expectedBlurredSlot: 1, expectedPreviousSlot: 1,
              ], safeFragmentBody(in: source) else { return nil }

        let b = escaped(blurred), p = escaped(previous)
        guard let mask = unique(
            #"(?m)^[ \t]*float\s+([A-Za-z_]\w*)\s*=\s*1(?:\.0+)?\s*;\s*$"#,
            in: source
        ), let maskName = mask.captures.first,
              let divisor = unique(
                #"(?m)^[ \t]*float\s+([A-Za-z_]\w*)\s*=\s*mix\(\s*"# + b
                    + #"\.w\s*,\s*1(?:\.0+)?\s*,\s*step\(\s*"# + b
                    + #"\.w\s*,\s*0(?:\.0+)?\s*\)\s*\)\s*;\s*$"#,
                in: source
              ), let divisorName = divisor.captures.first else { return nil }
        let m = escaped(maskName), d = escaped(divisorName)

        guard let previousParameter = unique(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"# + p + #"\s*;\s*$"#,
            in: source
        ), let previousParameterName = previousParameter.captures.first,
              let straightParameter = unique(
                #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*float4\(\s*"# + b
                    + #"\.xyz\s*/\s*float3\(\s*"# + d + #"\s*\)\s*,\s*"#
                    + b + #"\.w\s*\)\s*;\s*$"#,
                in: source
              ), let straightParameterName = straightParameter.captures.first else {
            return nil
        }
        let old = escaped(previousParameterName)
        let straight = escaped(straightParameterName)
        guard let invocation = unique(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\(\s*"#
                + old + #"\s*,\s*"# + straight
                + #"\s*,\s*([A-Za-z_]\w*)\s*\)\s*;\s*$"#,
            in: source
        ), invocation.captures.count == 3 else { return nil }
        let resultName = invocation.captures[0]
        let helperName = invocation.captures[1]
        let uniformName = invocation.captures[2]
        let result = escaped(resultName)

        guard let helper = validateHelper(
            named: helperName,
            uniformArgument: uniformName,
            in: source
        ), let resultAssignment = unique(
            #"(?m)^[ \t]*"# + b + #"\s*=\s*"# + result + #"\s*;\s*$"#,
            in: source
        ), let mix = unique(
            #"(?m)^[ \t]*"# + b + #"\s*=\s*mix\(\s*"# + p
                + #"\s*,\s*"# + b + #"\s*,\s*float4\(\s*"# + m
                + #"\s*\)\s*\)\s*;\s*$"#,
            in: source
        ), let output = unique(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*"# + b + #"\s*;\s*$"#,
            in: source
        ), let outputIndent = output.captures.first,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              wordCount("g_CompositeColor", in: source) == 2 else { return nil }

        let mainFlow = [
            blurredSample, previousSample, mask, divisor, previousParameter,
            straightParameter, invocation, resultAssignment, mix, output,
        ]
        guard zip(mainFlow, mainFlow.dropFirst()).allSatisfy({ pair in
            pair.0.range.location < pair.1.range.location
        }), hasNoUnrecognizedUse(
            source,
            recognized: mainFlow + [helper],
            names: [
                blurred, previous, maskName, divisorName,
                previousParameterName, straightParameterName, resultName,
                helperName,
            ]
        ) else { return nil }

        var transformed = source
        guard let outputRange = Range(output.range, in: transformed) else { return nil }
        transformed.replaceSubrange(
            outputRange,
            with: "\(outputIndent)out.mwxFragColor = "
                + "mwxGenericPremultiply(\(blurred));"
        )
        let helperSource = """

        static inline float4 mwxGenericPremultiply(float4 color) {
            return float4(color.xyz * color.w, color.w);
        }
        """
        guard let namespace = transformed.range(
            of: #"(?m)^using namespace metal;\s*$"#,
            options: .regularExpression
        ) else { return nil }
        transformed.insert(contentsOf: helperSource, at: namespace.upperBound)
        return transformed
    }

    private static func validateHelper(
        named name: String,
        uniformArgument: String,
        in source: String
    ) -> Match? {
        let helperPattern = #"(?ms)^[ \t]*(?:static\s+inline[^\n]*\n)?float4\s+"#
            + escaped(name)
            + #"\(\s*thread\s+const\s+float4&\s+([A-Za-z_]\w*)\s*,\s*"#
            + #"thread\s+float4&\s+([A-Za-z_]\w*)\s*,\s*"#
            + #"constant\s+MWXUniforms&\s+([A-Za-z_]\w*)\s*\)\s*\{([^{}]*)\}"#
        guard let helper = unique(helperPattern, in: source),
              helper.captures.count == 4 else { return nil }
        let original = helper.captures[0]
        let effect = helper.captures[1]
        let uniform = helper.captures[2]
        let body = helper.captures[3]
        guard uniform == uniformArgument,
              wordCount(original, in: body) == 0,
              let color = unique(
                #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                    + escaped(effect) + #"\s*;\s*$"#,
                in: body
              ), let colorName = color.captures.first,
              let rgb = unique(
                #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*"#
                    + escaped(colorName) + #"\.xyz\s*\*\s*"#
                    + escaped(uniform) + #"\.g_CompositeColor\s*;\s*$"#,
                in: body
              ), let rgbName = rgb.captures.first else { return nil }
        var writes: [Match] = []
        for component in ["x", "y", "z"] {
            guard let write = unique(
                #"(?m)^[ \t]*"# + escaped(effect) + #"\."# + component
                    + #"\s*=\s*"# + escaped(rgbName) + #"\."# + component
                    + #"\s*;\s*$"#,
                in: body
            ) else { return nil }
            writes.append(write)
        }
        guard let returned = unique(
            #"(?m)^[ \t]*return\s+"# + escaped(effect) + #"\s*;\s*$"#,
            in: body
        ) else { return nil }
        let flow = [color, rgb] + writes + [returned]
        guard zip(flow, flow.dropFirst()).allSatisfy({ pair in
            pair.0.range.location < pair.1.range.location
        }), hasNoUnrecognizedUse(
            body,
            recognized: flow,
            names: [effect, uniform, colorName, rgbName]
        ) else { return nil }
        return helper
    }

    private static func sampleCalls(in source: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for match in matches(
            #"\bg_Texture([0-7])\s*\.\s*sample\s*\("#, in: source
        ) {
            guard let text = capture(match, 1, in: source),
                  let slot = Int(text) else { return [:] }
            result[slot, default: 0] += 1
        }
        return result
    }

    private static func safeFragmentBody(in source: String) -> Bool {
        guard let function = unique(
            #"(?ms)^fragment\s+[^\n]+\bmwxGenericFragment\s*\([^{}]*\)\s*\{((?:[^{}]|\{\})*)\}"#,
            in: source
        ), let body = function.captures.first else { return false }
        return matches(
            #"\b(if|for|while|do|switch|discard|discard_fragment|atomic_[A-Za-z_]\w*)\b"#,
            in: body
        ).isEmpty
            && matches(#"\.\s*(read|write|gather)\s*\("#, in: body).isEmpty
            && matches(#"\breturn\b"#, in: body).count == 1
            && matches(#"\breturn\s+out\s*;"#, in: body).count == 1
    }

    private static func hasNoUnrecognizedUse(
        _ source: String,
        recognized: [Match],
        names: [String]
    ) -> Bool {
        let mutable = NSMutableString(string: source)
        for match in recognized.sorted(by: { $0.range.location > $1.range.location }) {
            mutable.replaceCharacters(
                in: match.range,
                with: String(repeating: " ", count: match.range.length)
            )
        }
        let remainder = mutable as String
        return names.allSatisfy { wordCount($0, in: remainder) == 0 }
    }

    private static func unique(_ pattern: String, in source: String) -> Match? {
        let found = matches(pattern, in: source)
        guard found.count == 1, let item = found.first else { return nil }
        let captures = (1 ..< item.numberOfRanges).compactMap {
            capture(item, $0, in: source)
        }
        guard captures.count == item.numberOfRanges - 1 else { return nil }
        return .init(range: item.range, captures: captures)
    }

    private static func escaped(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value)
    }

    private static func wordCount(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String, in source: String
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func capture(
        _ match: NSTextCheckingResult, _ index: Int, in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}
