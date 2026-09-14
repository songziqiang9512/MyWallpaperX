import Foundation

/// Conserves a source-proven generated-RGB blend through compiler output.
/// The graph-input color crosses the straight-color boundary; scalar texture
/// signals remain data and the sole authored output returns to premultiplied
/// compositor storage.
nonisolated enum SceneGenericShaderGeneratedRGBPreservedAlphaLowering {
    typealias Fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
        .AlphaPreservingGeneratedRGBFact

    /// Checks the compiler-side contract before an unproven default boundary
    /// is allowed to cover a source-proven generated-RGB route. The source
    /// carrier must remain the one full-color sample, scalar auxiliaries must
    /// keep their scalar projections, and the terminal output must still copy
    /// that carrier's alpha. A changed output shape therefore fails closed
    /// instead of silently becoming a generic straight-color pass.
    static func compilerContractMatches(
        _ source: String,
        fact: Fact
    ) -> Bool {
        compilerSamplesMatch(source, fact: fact)
            && SceneGenericShaderStraightAlphaPreservingLowering.lowerComposed(
                source,
                expectedSlot: fact.sourceSlot
            ) != nil
    }

    static func lower(_ source: String, fact: Fact) -> String? {
        guard compilerSamplesMatch(source, fact: fact) else { return nil }
        return SceneGenericShaderStraightAlphaPreservingLowering.lowerComposed(
            source,
            expectedSlot: fact.sourceSlot
        )
    }

    private static func compilerSamplesMatch(
        _ source: String,
        fact: Fact
    ) -> Bool {
        let scalarCounts = fact.scalarSampleCallCounts
        guard (0 ..< 8).contains(fact.sourceSlot),
              scalarCounts[fact.sourceSlot] == nil,
              scalarCounts.keys.allSatisfy({ (0 ..< 8).contains($0) }),
              scalarCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              scalarCounts.values.reduce(0, +) <= 15,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              calls.count == scalarCounts.values.reduce(0, +) + 1
        else { return false }

        var fullColorCount = 0
        var observedScalarCounts: [Int: Int] = [:]
        for call in calls {
            guard let range = Range(call.range, in: source) else { return false }
            let suffix = source[range.upperBound...]
            if call.slot == fact.sourceSlot {
                guard suffix.range(
                    of: #"^\s*;"#,
                    options: .regularExpression
                ) != nil else { return false }
                fullColorCount += 1
            } else {
                guard scalarCounts[call.slot] != nil,
                      suffix.range(
                        of: #"^\s*\.\s*[xyzwrgba]\b"#,
                        options: .regularExpression
                      ) != nil else { return false }
                observedScalarCounts[call.slot, default: 0] += 1
            }
        }
        return fullColorCount == 1 && observedScalarCounts == scalarCounts
    }
}
