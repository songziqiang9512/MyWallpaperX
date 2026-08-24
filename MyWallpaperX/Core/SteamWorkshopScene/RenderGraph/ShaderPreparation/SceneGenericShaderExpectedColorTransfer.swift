import Foundation

/// Exact source-proven transfer carried into the external compiler request.
/// A two-slot transfer preserves semantic signal/color order; it is never
/// canonicalized as an unordered sampler set.
nonisolated struct SceneGenericShaderExpectedColorTransfer: Encodable {
    let kind: String
    let slot: Int?
    let slots: [Int]?

    init?(_ transfer: SceneShaderColorTransfer) {
        switch transfer {
        case let .independentAlphaSignal(textureSlot):
            guard Self.valid(textureSlot) else { return nil }
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
                  signalSlot != colorSlot else { return nil }
            kind = "independent-alpha-signal-compositing"
            slot = nil
            slots = [signalSlot, colorSlot]
        default:
            return nil
        }
    }

    var cacheKey: String {
        if let slot { return "\(kind):\(slot)" }
        return ([kind] + (slots ?? []).map(String.init)).joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey { case kind, slot, slots }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(slot, forKey: .slot)
        try container.encodeIfPresent(slots, forKey: .slots)
    }

    private static func valid(_ slot: Int) -> Bool {
        (0 ..< 8).contains(slot)
    }
}
