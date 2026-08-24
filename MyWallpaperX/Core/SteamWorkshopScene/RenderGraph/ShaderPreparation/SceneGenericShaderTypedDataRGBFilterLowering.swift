import Foundation

/// Independently checks the external compiler's sampler projections before
/// applying the shared straight/premultiplied color boundary. Data samplers
/// stay byte-semantic and are never unpremultiplied.
nonisolated enum SceneGenericShaderTypedDataRGBFilterLowering {
    private enum Projection {
        case fullVector
        case red
        case redGreen
    }

    private struct SampleCall {
        let range: NSRange
        let slot: Int
        let projection: Projection
    }

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderTypedDataRGBFilterFact
    ) -> String? {
        guard let calls = sampleCalls(in: source),
              calls.count == fact.totalSampleCallCount else { return nil }
        var sourceCount = 0
        var fullVector: [Int: Int] = [:]
        var red: [Int: Int] = [:]
        var redGreen: [Int: Int] = [:]
        for call in calls {
            if call.slot == fact.sourceSlot {
                guard call.projection == .fullVector else { return nil }
                sourceCount += 1
                continue
            }
            switch call.projection {
            case .fullVector: fullVector[call.slot, default: 0] += 1
            case .red: red[call.slot, default: 0] += 1
            case .redGreen: redGreen[call.slot, default: 0] += 1
            }
        }
        guard sourceCount == 1,
              fullVector == fact.fullVectorDataSampleCallCounts,
              red == fact.redDataSampleCallCounts,
              redGreen == fact.redGreenDataSampleCallCounts else { return nil }
        return SceneGenericShaderStraightAlphaPreservingLowering.lowerPreserving(
            source,
            expectedSlot: fact.sourceSlot
        )
    }

    private static func sampleCalls(in source: String) -> [SampleCall]? {
        let starts = matches(#"\bg_Texture([0-7])\.sample\("#, in: source)
        var result: [SampleCall] = []
        for start in starts {
            guard let rawSlot = capture(start, 1, in: source),
                  let slot = Int(rawSlot),
                  let startRange = Range(start.range, in: source),
                  let open = source[..<startRange.upperBound].lastIndex(of: "(")
            else { return nil }
            var depth = 0
            var close: String.Index?
            var cursor = open
            while cursor < source.endIndex {
                switch source[cursor] {
                case "(": depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 { close = cursor }
                default: break
                }
                guard depth >= 0 else { return nil }
                if close != nil { break }
                cursor = source.index(after: cursor)
            }
            guard let close else { return nil }
            let range = startRange.lowerBound..<source.index(after: close)
            let suffix = String(source[range.upperBound...])
            let projection: Projection
            if matches(#"^\s*\.(?:x|r)\b"#, in: suffix).count == 1 {
                projection = .red
            } else if matches(#"^\s*\.(?:xy|rg)\b"#, in: suffix).count == 1 {
                projection = .redGreen
            } else if matches(#"^\s*\."#, in: suffix).isEmpty {
                projection = .fullVector
            } else {
                return nil
            }
            result.append(.init(
                range: NSRange(range, in: source),
                slot: slot,
                projection: projection
            ))
        }
        return result
    }

    private static func matches(
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
