import Foundation

/// Exact source-proven transfer carried into the external compiler request.
/// A two-slot transfer preserves semantic signal/color order; it is never
/// canonicalized as an unordered sampler set.
nonisolated struct SceneGenericShaderExpectedColorTransfer: Encodable {
    let kind: String
    let slot: Int?
    let slots: [Int]?
    let accumulatorLoopWork: Int?
    let usesRGBA8UnormAttachmentBoundary: Bool

    init?(
        _ transfer: SceneShaderColorTransfer,
        fragmentSource: String,
        usesRGBA8UnormAttachmentBoundary: Bool = false,
        permitsStraightAlphaPreserving: Bool = false
    ) {
        let accumulatorLoopWork: Int?
        if case .independentAlphaSignalPreserving = transfer {
            accumulatorLoopWork = usesRGBA8UnormAttachmentBoundary
                ? SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .rgba8UnormAttachmentLoopWork(fragmentSource: fragmentSource)
                : SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .staticLoopWork(fragmentSource: fragmentSource)
        } else {
            accumulatorLoopWork = nil
        }
        self.init(
            transfer,
            accumulatorLoopWork: accumulatorLoopWork,
            usesRGBA8UnormAttachmentBoundary:
                usesRGBA8UnormAttachmentBoundary,
            permitsStraightAlphaPreserving: permitsStraightAlphaPreserving
        )
    }

    init?(
        _ transfer: SceneShaderColorTransfer,
        accumulatorLoopWork: Int? = nil,
        usesRGBA8UnormAttachmentBoundary: Bool = false,
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
                  Self.valid(textureSlot), accumulatorLoopWork == nil,
                  !usesRGBA8UnormAttachmentBoundary else {
                return nil
            }
            kind = "straight-alpha-preserving"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignal(textureSlot):
            guard Self.valid(textureSlot), accumulatorLoopWork == nil,
                  !usesRGBA8UnormAttachmentBoundary else {
                return nil
            }
            kind = "independent-alpha-signal"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignalPreserving(textureSlot):
            guard Self.valid(textureSlot),
                  !usesRGBA8UnormAttachmentBoundary
                    || accumulatorLoopWork != nil else { return nil }
            kind = "independent-alpha-signal-preserving"
            slot = textureSlot
            slots = nil
        case let .independentAlphaSignalCompositing(signalSlot, colorSlot):
            guard Self.valid(signalSlot), Self.valid(colorSlot),
                  signalSlot != colorSlot,
                  accumulatorLoopWork == nil,
                  !usesRGBA8UnormAttachmentBoundary else { return nil }
            kind = "independent-alpha-signal-compositing"
            slot = nil
            slots = [signalSlot, colorSlot]
        case let .independentAlphaSignalUnderlayCompositing(
            signalSlot, colorSlot, underlaySlot
        ):
            guard [signalSlot, colorSlot, underlaySlot].allSatisfy(Self.valid),
                  Set([signalSlot, colorSlot, underlaySlot]).count == 3,
                  accumulatorLoopWork == nil,
                  !usesRGBA8UnormAttachmentBoundary else { return nil }
            kind = "independent-alpha-signal-underlay-compositing"
            slot = nil
            slots = [signalSlot, colorSlot, underlaySlot]
        default:
            return nil
        }
        self.accumulatorLoopWork = accumulatorLoopWork
        self.usesRGBA8UnormAttachmentBoundary =
            usesRGBA8UnormAttachmentBoundary
    }

    var cacheKey: String {
        if let slot {
            let base = "\(kind):\(slot)"
            let storage = usesRGBA8UnormAttachmentBoundary
                ? ":rgba8-unorm" : ""
            guard let accumulatorLoopWork else { return base + storage }
            return "\(base):accumulator:\(accumulatorLoopWork)\(storage)"
        }
        return ([kind] + (slots ?? []).map(String.init)).joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey {
        case kind, slot, slots, accumulatorLoopWork,
             usesRGBA8UnormAttachmentBoundary
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
        if usesRGBA8UnormAttachmentBoundary {
            try container.encode(
                true,
                forKey: .usesRGBA8UnormAttachmentBoundary
            )
        }
    }

    private static func valid(_ slot: Int) -> Bool {
        (0 ..< 8).contains(slot)
    }
}
