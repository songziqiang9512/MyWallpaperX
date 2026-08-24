import Foundation

/// Conserves the host color boundary for a source-proven shader that turns
/// one compositor color input into an independent RGBA signal. The authored
/// shader owns the premultiplication that creates the signal, so this lowering
/// only presents its one color sample as straight RGBA and leaves the output
/// untouched.
nonisolated enum SceneGenericShaderIndependentSignalLowering {
    private static let unpremultiply =
        "mwxGenericIndependentSignalUnpremultiply"

    static func lowerProducer(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        guard (0 ..< 8).contains(expectedSlot),
              !containsWord(unpremultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
        else { return nil }

        let declarationPattern =
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
            + String(expectedSlot)
            + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#
        let declarations = matches(declarationPattern, in: source)
        guard declarations.count == 1,
              let declaration = declarations.first,
              let prefix = capture(declaration, 1, in: source),
              let carrier = capture(declaration, 2, in: source),
              let arguments = capture(declaration, 3, in: source),
              let suffix = capture(declaration, 4, in: source),
              !arguments.isEmpty else { return nil }

        guard let samples = sampleFacts(in: source),
              samples.filter({ $0.projection == nil }).map(\.slot)
                == [expectedSlot],
              samples.filter({ $0.projection != nil }).allSatisfy({
                  ["x", "r", "xy", "rg"].contains($0.projection!)
              }) else { return nil }

        let outputWrites = matches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=)"#,
            in: source
        )
        let wholeOutput = outputWrites.filter {
            capture($0, 1, in: source) == nil
        }
        let componentOutput = outputWrites.compactMap {
            capture($0, 1, in: source)
        }
        let wholeAssignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=.*;[ \t]*$"#,
            in: source
        )
        guard wholeOutput.count == 1,
              wholeAssignments.count == 1,
              componentOutput == ["w"],
              declaration.range.location < wholeOutput[0].range.location,
              containsWord(carrier, in: substring(
                  wholeAssignments[0].range, in: source
              ) ?? "") else { return nil }

        guard let declarationRange = Range(declaration.range, in: source) else {
            return nil
        }
        var transformed = source
        transformed.replaceSubrange(
            declarationRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
        )
        let helper = """

inline float4 \(unpremultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}
"""
        guard let namespace = transformed.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        transformed.insert(contentsOf: helper, at: namespace.upperBound)
        return transformed
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private struct SampleFact {
        let slot: Int
        let projection: String?
    }

    private static func sampleFacts(in source: String) -> [SampleFact]? {
        let calls = matches(
            #"\bg_Texture([0-7])\.sample\s*\("#,
            in: source
        )
        var result: [SampleFact] = []
        for call in calls {
            guard let slotText = capture(call, 1, in: source),
                  let slot = Int(slotText),
                  let callRange = Range(call.range, in: source) else {
                return nil
            }
            let opening = source.index(before: callRange.upperBound)
            var cursor = opening
            var depth = 0
            var closing: String.Index?
            while cursor < source.endIndex {
                switch source[cursor] {
                case "(": depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 { closing = cursor }
                    if depth < 0 { return nil }
                default: break
                }
                if closing != nil { break }
                cursor = source.index(after: cursor)
            }
            guard let closing else { return nil }
            cursor = source.index(after: closing)
            while cursor < source.endIndex, source[cursor].isWhitespace {
                cursor = source.index(after: cursor)
            }
            var projection: String?
            if cursor < source.endIndex, source[cursor] == "." {
                cursor = source.index(after: cursor)
                while cursor < source.endIndex, source[cursor].isWhitespace {
                    cursor = source.index(after: cursor)
                }
                let start = cursor
                while cursor < source.endIndex,
                      source[cursor].isLetter {
                    cursor = source.index(after: cursor)
                }
                guard start < cursor else { return nil }
                projection = String(source[start..<cursor])
            }
            result.append(.init(slot: slot, projection: projection))
        }
        return result
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
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

    private static func substring(
        _ range: NSRange,
        in source: String
    ) -> String? {
        Range(range, in: source).map { String(source[$0]) }
    }
}
