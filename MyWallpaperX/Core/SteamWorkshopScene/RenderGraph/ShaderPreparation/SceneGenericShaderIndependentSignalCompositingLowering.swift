import Foundation

/// Conserves the color boundary for an exact source-proven composition with
/// ordered signal/color sampler roles. The color carrier is presented to the
/// authored program as straight RGBA and its sole output is repremultiplied;
/// the independent signal sample remains raw.
nonisolated enum SceneGenericShaderIndependentSignalCompositingLowering {
    private static let unpremultiply =
        "mwxGenericSignalCompositeUnpremultiply"
    private static let premultiply =
        "mwxGenericSignalCompositePremultiply"

    static func lower(
        _ source: String,
        expectedSignalSlot: Int,
        expectedColorSlot: Int,
        expectedUnderlaySlot: Int? = nil
    ) -> String? {
        guard (0 ..< 8).contains(expectedSignalSlot),
              (0 ..< 8).contains(expectedColorSlot),
              expectedSignalSlot != expectedColorSlot,
              expectedUnderlaySlot.map({
                  (0 ..< 8).contains($0)
                      && $0 != expectedSignalSlot
                      && $0 != expectedColorSlot
              }) ?? true,
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = fragmentBody(in: source) else { return nil }

        let sampleCalls = matches(
            #"\bg_Texture([0-7])\.sample\s*\("#,
            in: source,
            range: body
        )
        let expectedSlots = Set(
            [expectedSignalSlot, expectedColorSlot]
                + (expectedUnderlaySlot.map { [$0] } ?? [])
        )
        guard sampleCalls.count == expectedSlots.count else { return nil }

        let declarationPattern =
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture([0-7])\.sample\(([^;]+)\)(\s*;[ \t]*)$"#
        let declarations = matches(
            declarationPattern, in: source, range: body
        )
        guard declarations.count == expectedSlots.count else { return nil }

        var bySlot: [Int: (match: NSTextCheckingResult, name: String)] = [:]
        for declaration in declarations {
            guard let slotText = capture(declaration, 3, in: source),
                  let slot = Int(slotText),
                  let name = capture(declaration, 2, in: source),
                  bySlot[slot] == nil else { return nil }
            bySlot[slot] = (declaration, name)
        }
        guard Set(bySlot.keys) == expectedSlots,
              let signal = bySlot[expectedSignalSlot],
              let color = bySlot[expectedColorSlot],
              signal.name != color.name,
              countWord(signal.name, in: substring(body, source: source)) >= 2
        else { return nil }

        let control = matches(
            #"\b(?:if|else|for|while|do|switch|case|discard|break|continue)\b|\?"#,
            in: source,
            range: body
        )
        let outputWrites = matches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=).*;[ \t]*$"#,
            in: source,
            range: body
        )
        let outputAssignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source,
            range: body
        )
        guard control.isEmpty,
              outputWrites.count == 1,
              outputAssignments.count == 1,
              capture(outputAssignments[0], 1, in: source) == color.name,
              color.match.range.location < outputAssignments[0].range.location,
              signal.match.range.location < outputAssignments[0].range.location,
              matches(
                  #"\breturn\s+out\s*;"#, in: source, range: body
              ).count == 1 else { return nil }

        guard let outputRange = Range(outputAssignments[0].range, in: source)
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "out.mwxFragColor = \(premultiply)(\(color.name));"
        )
        let straightColorSlots = Set(
            [expectedColorSlot] + (expectedUnderlaySlot.map { [$0] } ?? [])
        )
        let straightDeclarations = straightColorSlots.compactMap { slot in
            bySlot[slot].map { (slot, $0) }
        }.sorted { $0.1.match.range.location > $1.1.match.range.location }
        guard straightDeclarations.count == straightColorSlots.count else {
            return nil
        }
        for (slot, declaration) in straightDeclarations {
            guard let adjustedRange = Range(declaration.match.range, in: transformed),
                  let prefix = capture(declaration.match, 1, in: source),
                  let arguments = capture(declaration.match, 4, in: source),
                  let suffix = capture(declaration.match, 5, in: source) else {
                return nil
            }
            transformed.replaceSubrange(
                adjustedRange,
                with: "\(prefix)\(unpremultiply)(g_Texture\(slot).sample(\(arguments)))\(suffix)"
            )
        }

        let helpers = """

inline float4 \(unpremultiply)(float4 value) {
    const float alpha = clamp(value.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(value.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}

inline float4 \(premultiply)(float4 value) {
    const float alpha = clamp(value.w, 0.0, 1.0);
    return float4(clamp(value.xyz, float3(0.0), float3(1.0)) * alpha, alpha);
}
"""
        guard let namespace = transformed.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        transformed.insert(contentsOf: helpers, at: namespace.upperBound)
        return transformed
    }

    private static func fragmentBody(in source: String) -> NSRange? {
        let masked = maskComments(source)
        let signatures = matches(
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
                    let start = masked.index(after: opening)
                    return NSRange(start..<cursor, in: masked)
                }
                if depth < 0 { return nil }
            }
            cursor = masked.index(after: cursor)
        }
        return nil
    }

    private static func maskComments(_ source: String) -> String {
        let pattern = #"/\*.*?\*/|//[^\n]*"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: .dotMatchesLineSeparators
        ) else { return source }
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

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String,
        in source: String,
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: range ?? NSRange(source.startIndex..., in: source)
        ) ?? []
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
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static func substring(_ range: NSRange, source: String) -> String {
        Range(range, in: source).map { String(source[$0]) } ?? ""
    }
}
