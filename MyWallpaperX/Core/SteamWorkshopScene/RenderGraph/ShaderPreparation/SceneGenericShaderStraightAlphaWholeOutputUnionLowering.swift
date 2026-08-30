import Foundation

extension SceneGenericShaderStraightAlphaPreservingLowering {
    /// Conserves a source-proven straight-alpha program whose compiler output
    /// assigns one of several complete colors before one terminal return. The
    /// semantic analyzer owns branch meaning; this pass only accepts a single
    /// color texture, whole-output writes, and one compositor boundary.
    static func lowerWholeOutputUnion(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        let unpremultiply = "mwxGenericUnpremultiply"
        let premultiply = "mwxGenericPremultiply"
        guard (0 ..< 8).contains(expectedSlot),
              !unionContainsWord(unpremultiply, in: source),
              !unionContainsWord(premultiply, in: source),
              unionMatches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let bodyRange = unionFragmentBody(in: source),
              let body = unionSubstring(bodyRange, in: source) else { return nil }

        let samples = textureSampleCalls(in: body)
        let allSamples = textureSampleCalls(in: source)
        guard (1 ... 32).contains(samples.count),
              samples.count == allSamples.count,
              samples.allSatisfy({ $0.slot == expectedSlot }) else { return nil }

        let bindings = unionMatches(
            #"\btexture(?:1d|2d|3d|cube)(?:_array)?\s*<[^>]+>\s+g_Texture([0-7])\b"#,
            in: source
        )
        let references = unionMatches(#"\bg_Texture([0-7])\b"#, in: source)
        guard bindings.count == 1,
              unionCapture(bindings[0], 1, in: source) == String(expectedSlot),
              references.count == bindings.count + allSamples.count,
              references.allSatisfy({
                  unionCapture($0, 1, in: source) == String(expectedSlot)
              }) else { return nil }

        let maskedBody = unionMaskComments(body)
        let writes = unionMatches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\s*\.[xyzwrgba]{1,4})?\s*(?:[+\-*/]=|=(?!=))"#,
            in: maskedBody
        )
        let wholeAssignments = unionMatches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=(?!=)[^;\n]+;[ \t]*$"#,
            in: maskedBody
        )
        let outputReferences = unionMatches(
            #"\bout\.mwxFragColor\b"#,
            in: maskedBody
        )
        let returns = unionMatches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: maskedBody
        )
        guard (2 ... 8).contains(wholeAssignments.count),
              writes.count == wholeAssignments.count,
              outputReferences.count == wholeAssignments.count,
              returns.count == 1,
              unionMatches(#"\breturn\b"#, in: maskedBody).count == 1,
              let terminalReturn = returns.first,
              wholeAssignments.allSatisfy({
                  $0.range.location < terminalReturn.range.location
              }) else { return nil }

        var transformedBody = body
        for sample in samples.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            guard let range = Range(sample.range, in: transformedBody),
                  let call = unionSubstring(sample.range, in: body) else { return nil }
            transformedBody.replaceSubrange(
                range,
                with: "\(unpremultiply)(\(call))"
            )
        }
        let transformedMaskedBody = unionMaskComments(transformedBody)
        let transformedReturns = unionMatches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: transformedMaskedBody
        )
        guard transformedReturns.count == 1,
              let transformedReturn = transformedReturns.first,
              let indent = unionCapture(
                  transformedReturn, 1, in: transformedMaskedBody
              ),
              let transformedReturnRange = Range(
                  transformedReturn.range,
                  in: transformedBody
              ) else { return nil }
        transformedBody.replaceSubrange(
            transformedReturnRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                + "\(indent)return out;"
        )

        guard let sourceBodyRange = Range(bodyRange, in: source) else {
            return nil
        }
        var transformed = source
        transformed.replaceSubrange(sourceBodyRange, with: transformedBody)
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

    /// Conserves a source-proven direct sampled output followed by one alpha
    /// attenuation. The sample enters authored math as straight color and the
    /// fully mutated output crosses the compositor boundary exactly once.
    static func lowerDirectOutputAlphaMutation(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        let unpremultiply = "mwxGenericUnpremultiply"
        let premultiply = "mwxGenericPremultiply"
        guard (0 ..< 8).contains(expectedSlot),
              !unionContainsWord(unpremultiply, in: source),
              !unionContainsWord(premultiply, in: source),
              unionMatches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let bodyRange = unionFragmentBody(in: source),
              let body = unionSubstring(bodyRange, in: source) else { return nil }

        let samples = textureSampleCalls(in: body)
        let allSamples = textureSampleCalls(in: source)
        guard samples.count == 1,
              samples.count == allSamples.count,
              samples[0].slot == expectedSlot else { return nil }

        let bindings = unionMatches(
            #"\btexture(?:1d|2d|3d|cube)(?:_array)?\s*<[^>]+>\s+g_Texture([0-7])\b"#,
            in: source
        )
        let references = unionMatches(#"\bg_Texture([0-7])\b"#, in: source)
        guard bindings.count == 1,
              unionCapture(bindings[0], 1, in: source) == String(expectedSlot),
              references.count == bindings.count + allSamples.count,
              references.allSatisfy({
                  unionCapture($0, 1, in: source) == String(expectedSlot)
              }) else { return nil }

        let maskedBody = unionMaskComments(body)
        let writes = unionMatches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\s*\.[xyzwrgba]{1,4})?\s*(?:[+\-*/]=|=(?!=))"#,
            in: maskedBody
        )
        let whole = unionMatches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=\s*g_Texture"#
                + String(expectedSlot) + #"\.sample\([^;]+\)\s*;[ \t]*$"#,
            in: maskedBody
        )
        let alpha = unionMatches(
            #"(?m)^[ \t]*out\.mwxFragColor\.(?:w|a)\s*\*=\s*[^;]+;[ \t]*$"#,
            in: maskedBody
        )
        let outputReferences = unionMatches(
            #"\bout\.mwxFragColor\b"#,
            in: maskedBody
        )
        let returns = unionMatches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: maskedBody
        )
        guard writes.count == 2,
              whole.count == 1,
              alpha.count == 1,
              outputReferences.count == 2,
              returns.count == 1,
              unionMatches(#"\breturn\b"#, in: maskedBody).count == 1,
              whole[0].range.location < alpha[0].range.location,
              alpha[0].range.location < returns[0].range.location else { return nil }

        var transformedBody = body
        guard let sampleRange = Range(samples[0].range, in: transformedBody),
              let sample = unionSubstring(samples[0].range, in: body) else {
            return nil
        }
        transformedBody.replaceSubrange(
            sampleRange,
            with: "\(unpremultiply)(\(sample))"
        )
        let transformedMaskedBody = unionMaskComments(transformedBody)
        let transformedReturns = unionMatches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: transformedMaskedBody
        )
        guard transformedReturns.count == 1,
              let terminalReturn = transformedReturns.first,
              let indent = unionCapture(terminalReturn, 1, in: transformedMaskedBody),
              let returnRange = Range(terminalReturn.range, in: transformedBody)
        else { return nil }
        transformedBody.replaceSubrange(
            returnRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                + "\(indent)return out;"
        )

        guard let sourceBodyRange = Range(bodyRange, in: source) else {
            return nil
        }
        var transformed = source
        transformed.replaceSubrange(sourceBodyRange, with: transformedBody)
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

    private struct TextureSampleCall {
        let range: NSRange
        let slot: Int
    }

    private static func textureSampleCalls(
        in source: String
    ) -> [TextureSampleCall] {
        let starts = unionMatches(
            #"\bg_Texture([0-7])\.sample\s*\("#,
            in: source
        )
        var result: [TextureSampleCall] = []
        for start in starts {
            guard let slotText = unionCapture(start, 1, in: source),
                  let slot = Int(slotText),
                  let startRange = Range(start.range, in: source),
                  let open = source[..<startRange.upperBound].lastIndex(of: "(")
            else { return [] }
            var cursor = open
            var depth = 0
            var close: String.Index?
            while cursor < source.endIndex {
                if source[cursor] == "(" { depth += 1 }
                if source[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        close = cursor
                        break
                    }
                    if depth < 0 { return [] }
                }
                cursor = source.index(after: cursor)
            }
            guard let close else { return [] }
            let range = startRange.lowerBound..<source.index(after: close)
            result.append(.init(range: NSRange(range, in: source), slot: slot))
        }
        return result
    }

    private static func unionFragmentBody(in source: String) -> NSRange? {
        let masked = unionMaskComments(source)
        let signatures = unionMatches(
            #"\bfragment\b[^\{;]*\bmwxGenericFragment\s*\([^\{;]*\)\s*\{"#,
            in: masked
        )
        guard signatures.count == 1,
              let signature = signatures.first,
              let signatureRange = Range(signature.range, in: masked) else {
            return nil
        }
        let opening = masked.index(before: signatureRange.upperBound)
        var cursor = opening
        var depth = 0
        while cursor < masked.endIndex {
            if masked[cursor] == "{" { depth += 1 }
            if masked[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return NSRange(
                        masked.index(after: opening)..<cursor,
                        in: masked
                    )
                }
                if depth < 0 { return nil }
            }
            cursor = masked.index(after: cursor)
        }
        return nil
    }

    private static func unionMaskComments(_ source: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"/\*.*?\*/|//[^\n]*"#,
            options: .dotMatchesLineSeparators
        )
        var masked = source
        for match in expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            masked.replaceSubrange(range, with: source[range].map {
                $0 == "\n" ? "\n" : " "
            })
        }
        return masked
    }

    private static func unionContainsWord(
        _ word: String,
        in source: String
    ) -> Bool {
        !unionMatches(
            #"\b"# + unionEscaped(word) + #"\b"#,
            in: source
        ).isEmpty
    }

    private static func unionMatches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) ?? []
    }

    private static func unionEscaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    private static func unionCapture(
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

    static func unionSubstring(
        _ range: NSRange,
        in source: String
    ) -> String? {
        Range(range, in: source).map { String(source[$0]) }
    }
}
