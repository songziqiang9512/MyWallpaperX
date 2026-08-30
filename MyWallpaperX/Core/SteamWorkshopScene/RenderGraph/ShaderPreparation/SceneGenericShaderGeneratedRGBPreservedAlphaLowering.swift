import Foundation

/// Conserves a source-proven generated-RGB blend through compiler output.
/// The graph-input color crosses the straight-color boundary; scalar texture
/// signals remain data and the sole authored output returns to premultiplied
/// compositor storage.
nonisolated enum SceneGenericShaderGeneratedRGBPreservedAlphaLowering {
    typealias Fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
        .AlphaPreservingGeneratedRGBFact

    static func lower(_ source: String, fact: Fact) -> String? {
        let scalarCounts = fact.scalarSampleCallCounts
        guard (0 ..< 8).contains(fact.sourceSlot),
              scalarCounts[fact.sourceSlot] == nil,
              scalarCounts.keys.allSatisfy({ (0 ..< 8).contains($0) }),
              scalarCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              scalarCounts.values.reduce(0, +) <= 15,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              calls.count == scalarCounts.values.reduce(0, +) + 1
        else { return nil }

        var fullColorCount = 0
        var observedScalarCounts: [Int: Int] = [:]
        for call in calls {
            guard let range = Range(call.range, in: source) else { return nil }
            let suffix = source[range.upperBound...]
            if call.slot == fact.sourceSlot {
                guard suffix.range(
                    of: #"^\s*;"#,
                    options: .regularExpression
                ) != nil else { return nil }
                fullColorCount += 1
            } else {
                guard scalarCounts[call.slot] != nil,
                      suffix.range(
                        of: #"^\s*\.\s*[xyzwrgba]\b"#,
                        options: .regularExpression
                      ) != nil else { return nil }
                observedScalarCounts[call.slot, default: 0] += 1
            }
        }
        guard fullColorCount == 1,
              observedScalarCounts == scalarCounts else { return nil }
        return SceneGenericShaderStraightAlphaPreservingLowering.lowerComposed(
            source,
            expectedSlot: fact.sourceSlot
        )
    }
}
