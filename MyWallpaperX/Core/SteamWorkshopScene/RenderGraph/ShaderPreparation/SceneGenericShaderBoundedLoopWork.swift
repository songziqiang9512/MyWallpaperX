import Foundation

nonisolated enum SceneGenericShaderBoundedLoopWork {
    struct Consumption {
        let found: Bool
        let work: Int?
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
}
