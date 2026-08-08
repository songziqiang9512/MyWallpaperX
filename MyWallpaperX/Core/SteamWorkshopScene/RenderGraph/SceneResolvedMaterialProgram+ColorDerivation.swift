import Foundation

nonisolated extension SceneResolvedMaterialProgramDerivation {
    struct ColorProjection {
        let framebufferInput: SceneShaderColorRepresentation
        let fragmentOutput: SceneShaderColorRepresentation
    }

    static func hasResolvedColorContract(
        transfer: SceneShaderColorTransfer,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        resolveColor(transfer: transfer, textureSlots: textureSlots) != nil
    }

    static func resolveColor(
        transfer: SceneShaderColorTransfer,
        textureSlots: [Program.TextureSlot?]
    ) -> ColorProjection? {
        var graphRepresentations: Set<SceneShaderColorRepresentation> = []
        for slot in textureSlots.compactMap({ $0 }) {
            guard case .graph = slot.reference else { continue }
            switch slot.resource.publication.candidate.content {
            case let .color(.resolved(representation)):
                graphRepresentations.insert(representation)
            case .color(.unresolved):
                return nil
            case .data:
                continue
            }
        }
        let framebufferInput: SceneShaderColorRepresentation
        if transfer == .opaque, graphRepresentations.isEmpty {
            // An opaque procedural pass can declare an authored framebuffer
            // sampler that the prepared variant never reads. Use one stable
            // identity value without claiming or requiring a sampled input.
            framebufferInput = .opaque
        } else if case let .independentAlphaSignalCompositing(
            signalSlot,
            colorSlot
        ) = transfer {
            guard representation(slot: signalSlot, textureSlots: textureSlots)
                    == .independentAlphaSignal,
                  let color = representation(slot: colorSlot, textureSlots: textureSlots),
                  color == .opaque || color == .premultipliedAlpha else {
                return nil
            }
            framebufferInput = color
        } else {
            guard graphRepresentations.count == 1,
                  let representation = graphRepresentations.first else {
                return nil
            }
            framebufferInput = representation
        }

        let fragmentOutput: SceneShaderColorRepresentation
        switch transfer {
        case .unresolved:
            return nil
        case .opaque:
            fragmentOutput = .opaque
        case let .passthrough(slot):
            guard (0 ..< textureSlots.count).contains(slot),
                  let texture = textureSlots[slot] else {
                return nil
            }
            guard case let .color(.resolved(representation)) =
                    texture.resource.publication.candidate.content else {
                return nil
            }
            fragmentOutput = representation
        case let .straightAlphaPreserving(slot):
            guard let representation = representation(
                slot: slot, textureSlots: textureSlots
            ), representation == .opaque || representation == .premultipliedAlpha else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .straightAlpha(slot):
            guard (0 ..< textureSlots.count).contains(slot),
                  let texture = textureSlots[slot],
                  case let .color(.resolved(representation)) =
                    texture.resource.publication.candidate.content,
                  representation == .opaque || representation == .premultipliedAlpha,
                  auxiliarySlotsAreData(textureSlots, excluding: slot) else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .independentAlphaSignal(slot):
            guard let representation = representation(
                slot: slot, textureSlots: textureSlots
            ), representation == .opaque || representation == .premultipliedAlpha else {
                return nil
            }
            fragmentOutput = .independentAlphaSignal
        case let .independentAlphaSignalPreserving(slot):
            guard representation(slot: slot, textureSlots: textureSlots)
                    == .independentAlphaSignal else { return nil }
            fragmentOutput = .independentAlphaSignal
        case .independentAlphaSignalCompositing:
            fragmentOutput = .premultipliedAlpha
        }
        return .init(
            framebufferInput: framebufferInput,
            fragmentOutput: fragmentOutput
        )
    }

    private static func representation(
        slot: Int,
        textureSlots: [Program.TextureSlot?]
    ) -> SceneShaderColorRepresentation? {
        guard textureSlots.indices.contains(slot),
              let texture = textureSlots[slot],
              case let .color(.resolved(value)) =
                texture.resource.publication.candidate.content else { return nil }
        return value
    }

    private static func auxiliarySlotsAreData(
        _ textureSlots: [Program.TextureSlot?],
        excluding colorSlot: Int
    ) -> Bool {
        textureSlots.enumerated().allSatisfy { index, texture in
            guard index != colorSlot, let texture else { return true }
            if case .data = texture.resource.publication.candidate.content {
                return true
            }
            return false
        }
    }
}
