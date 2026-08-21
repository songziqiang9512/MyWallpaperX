import Foundation

nonisolated enum SceneGenericShaderBoundedLoopWork {
    enum Failure: Error {
        case unbounded
        case budget
    }

    struct Consumption {
        let found: Bool
        let work: Int?
    }

    static func evaluate(sources: [String]) -> Result<Int, Failure> {
        let zeroBasedPattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*0\s*;\s*([A-Za-z_]\w*)\s*<\s*(\d+)\s*;\s*(?:(?:\+\+\s*([A-Za-z_]\w*))|(?:([A-Za-z_]\w*)\s*\+\+))\s*\)"#
        let signedInclusivePattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*(-?(?:\d+|[A-Za-z_]\w*))\s*;\s*([A-Za-z_]\w*)\s*<=\s*(-?(?:\d+|[A-Za-z_]\w*))\s*;\s*(?:(?:\+\+\s*([A-Za-z_]\w*))|(?:([A-Za-z_]\w*)\s*\+\+))\s*\)"#
        var total = 0
        for source in sources {
            var body = source.replacingOccurrences(
                of: #"(?s)/\*.*?\*/|//[^\n]*"#,
                with: " ",
                options: .regularExpression
            )
            guard let defines = numericDefines(in: body) else {
                return .failure(.unbounded)
            }
            for match in matches(zeroBasedPattern, in: body).reversed() {
                guard let declared = capture(match, 1, in: body),
                      let compared = capture(match, 2, in: body),
                      let limitText = capture(match, 3, in: body),
                      let limit = Int(limitText), (1 ... 64).contains(limit),
                      [capture(match, 4, in: body), capture(match, 5, in: body)]
                        .compactMap({ $0 }).contains(declared),
                      declared == compared,
                      let range = Range(match.range, in: body) else {
                    return .failure(.unbounded)
                }
                total += limit
                body.removeSubrange(range)
            }
            for match in matches(signedInclusivePattern, in: body).reversed() {
                guard let declared = capture(match, 1, in: body),
                      let startText = capture(match, 2, in: body),
                      let compared = capture(match, 3, in: body),
                      let endText = capture(match, 4, in: body),
                      let start = signedBound(startText, defines: defines),
                      let end = signedBound(endText, defines: defines),
                      declared == compared,
                      [capture(match, 5, in: body), capture(match, 6, in: body)]
                        .compactMap({ $0 }).contains(declared),
                      (-64 ... 64).contains(start),
                      (-64 ... 64).contains(end),
                      (1 ... 64).contains(end - start + 1),
                      let range = Range(match.range, in: body) else {
                    return .failure(.unbounded)
                }
                total += end - start + 1
                body.removeSubrange(range)
            }
            let audioLoops = consumeAudioLoops(in: &body)
            if audioLoops.found {
                guard let work = audioLoops.work else {
                    return .failure(.unbounded)
                }
                total += work
            }
            if regexMatches(#"\b(for|while|do)\b"#, body) {
                return .failure(.unbounded)
            }
        }
        return total <= 256 ? .success(total) : .failure(.budget)
    }

    static func consumeAudioLoops(in source: inout String) -> Consumption {
        let pattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*int\(g_AudioFrequencyMin\)\s*;\s*\1\s*<=\s*int\(g_AudioFrequencyMax\)\s*;\s*\+\+\s*\1\s*\)"#
        let loops = matches(pattern, in: source)
        guard !loops.isEmpty else { return .init(found: false, work: 0) }
        guard let bound = audioSpectrumBound(in: source) else {
            return .init(found: true, work: nil)
        }
        for loop in loops.reversed() {
            guard let range = Range(loop.range, in: source) else {
                return .init(found: true, work: nil)
            }
            source.removeSubrange(range)
        }
        return .init(found: true, work: bound * loops.count)
    }

    private static func audioSpectrumBound(in source: String) -> Int? {
        let names = matches(
            #"\b(?:float|half)\s+g_AudioSpectrum(16|32|64)(?:Left|Right)\s*\[\s*\1\s*\]"#,
            in: source
        )
        guard names.count >= 2 else { return nil }
        let bounds = names.compactMap { capture($0, 1, in: source) }.compactMap(Int.init)
        guard !bounds.isEmpty, Set(bounds).count == 1 else { return nil }
        return bounds[0]
    }

    private static func numericDefines(in source: String) -> [String: Int]? {
        var result: [String: Int] = [:]
        for match in matches(
            #"(?m)^\s*#define\s+([A-Za-z_]\w*)\s+(-?\d+)\s*$"#,
            in: source
        ) {
            guard let name = capture(match, 1, in: source),
                  let raw = capture(match, 2, in: source),
                  let value = Int(raw),
                  result.updateValue(value, forKey: name) == nil else {
                return nil
            }
        }
        return result
    }

    private static func signedBound(
        _ raw: String,
        defines: [String: Int]
    ) -> Int? {
        if let literal = Int(raw) { return literal }
        let isNegative = raw.hasPrefix("-")
        let name = isNegative ? String(raw.dropFirst()) : raw
        guard let value = defines[name] else { return nil }
        return isNegative ? -value : value
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

    private static func regexMatches(_ pattern: String, _ source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}
