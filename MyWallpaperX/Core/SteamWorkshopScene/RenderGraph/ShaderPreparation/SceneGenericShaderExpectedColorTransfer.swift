import Foundation

/// Exact source-proven transfer carried into the external compiler request.
/// A two-slot transfer preserves semantic signal/color order; it is never
/// canonicalized as an unordered sampler set.
nonisolated struct SceneGenericShaderExpectedColorTransfer: Encodable {
    let kind: String
    let slot: Int?
    let slots: [Int]?
    let accumulatorLoopWork: Int?

    init?(
        _ transfer: SceneShaderColorTransfer,
        fragmentSource: String,
        permitsStraightAlphaPreserving: Bool = false
    ) {
        let accumulatorLoopWork: Int?
        if case .independentAlphaSignalPreserving = transfer {
            accumulatorLoopWork =
                SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: fragmentSource)
        } else {
            accumulatorLoopWork = nil
        }
        self.init(
            transfer,
            accumulatorLoopWork: accumulatorLoopWork,
            permitsStraightAlphaPreserving: permitsStraightAlphaPreserving
        )
    }

    init?(
        _ transfer: SceneShaderColorTransfer,
        accumulatorLoopWork: Int? = nil,
        permitsStraightAlphaPreserving: Bool = false
    ) {
        if let accumulatorLoopWork,
           !(1 ... 256).contains(accumulatorLoopWork)
        {
            return nil
        }
        switch transfer {
        case let .straightAlphaPreserving(textureSlot):
            guard permitsStraightAlphaPreserving,
                  Self.valid(textureSlot), accumulatorLoopWork == nil else {
                return nil
            }
            kind = "straight-alpha-preserving"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignal(textureSlot):
            guard Self.valid(textureSlot), accumulatorLoopWork == nil else {
                return nil
            }
            kind = "independent-alpha-signal"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignalPreserving(textureSlot):
            guard Self.valid(textureSlot) else { return nil }
            kind = "independent-alpha-signal-preserving"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignalCompositing(signalSlot, colorSlot):
            guard Self.valid(signalSlot), Self.valid(colorSlot),
                  signalSlot != colorSlot,
                  accumulatorLoopWork == nil else { return nil }
            kind = "independent-alpha-signal-compositing"
            slot = nil
            slots = [signalSlot, colorSlot]
        default:
            return nil
        }
        self.accumulatorLoopWork = accumulatorLoopWork
    }

    var cacheKey: String {
        if let slot {
            let base = "\(kind):\(slot)"
            guard let accumulatorLoopWork else { return base }
            return "\(base):accumulator:\(accumulatorLoopWork)"
        }
        return ([kind] + (slots ?? []).map(String.init)).joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey {
        case kind, slot, slots, accumulatorLoopWork
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(slot, forKey: .slot)
        try container.encodeIfPresent(slots, forKey: .slots)
        try container.encodeIfPresent(
            accumulatorLoopWork,
            forKey: .accumulatorLoopWork
        )
    }

    private static func valid(_ slot: Int) -> Bool {
        (0 ..< 8).contains(slot)
    }
}
