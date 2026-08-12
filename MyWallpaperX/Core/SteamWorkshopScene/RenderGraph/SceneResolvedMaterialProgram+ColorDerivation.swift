import Foundation

nonisolated extension SceneResolvedMaterialProgramDerivation {
    struct ColorProjection: Hashable {
        let framebufferInput: SceneShaderColorRepresentation
        let fragmentOutput: SceneShaderColorRepresentation
    }

    /// The resource-independent color atom shared by launch admission and
    /// exact frame finalization. Pixel formats never imply this semantic.
    struct ColorTextureFact: Hashable {
        let isGraphReference: Bool
        let content: SceneTextureContent
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
        resolveColor(
            transfer: transfer,
            textureFacts: textureSlots.map { slot -> ColorTextureFact? in
                guard let slot else { return nil }
                let isGraphReference: Bool
                if case .graph = slot.reference {
                    isGraphReference = true
                } else {
                    isGraphReference = false
                }
                return .init(
                    isGraphReference: isGraphReference,
                    content: slot.resource.publication.candidate.content
                )
            }
        )
    }

    static func resolveColor(
        transfer: SceneShaderColorTransfer,
        textureFacts: [ColorTextureFact?]
    ) -> ColorProjection? {
        guard textureFacts.count == 8 else { return nil }
        var graphRepresentations: Set<SceneShaderColorRepresentation> = []
        for fact in textureFacts.compactMap({ $0 }) where fact.isGraphReference {
            switch fact.content {
            case let .color(.resolved(representation)):
                graphRepresentations.insert(representation)
            case .color(.unresolved):
                return nil
            case .scalarRedUnorm, .data:
                continue
            }
        }
        let framebufferInput: SceneShaderColorRepresentation
        if (transfer == .opaque || transfer == .premultipliedAlpha),
           graphRepresentations.isEmpty {
            // An opaque procedural pass can declare an authored framebuffer
            // sampler that the prepared variant never reads. Use one stable
            // identity value without claiming or requiring a sampled input.
            framebufferInput = .opaque
        } else if case let .independentAlphaSignalCompositing(
            signalSlot,
            colorSlot
        ) = transfer {
            guard representation(slot: signalSlot, textureFacts: textureFacts)
                    == .independentAlphaSignal,
                  let color = representation(slot: colorSlot, textureFacts: textureFacts),
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
        case .premultipliedAlpha:
            guard textureFacts.compactMap({ $0 }).allSatisfy({ fact in
                switch fact.content {
                case .scalarRedUnorm, .data:
                    return true
                case .color:
                    return false
                }
            }) else { return nil }
            fragmentOutput = .premultipliedAlpha
        case let .passthrough(slot):
            guard textureFacts.indices.contains(slot),
                  let fact = textureFacts[slot] else {
                return nil
            }
            guard case let .color(.resolved(representation)) =
                    fact.content else {
                return nil
            }
            fragmentOutput = representation
        case let .straightAlphaPreserving(slot):
            guard let representation = representation(
                slot: slot, textureFacts: textureFacts
            ), representation == .opaque || representation == .premultipliedAlpha else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .straightAlpha(slot):
            guard textureFacts.indices.contains(slot),
                  let fact = textureFacts[slot],
                  case let .color(.resolved(representation)) =
                    fact.content,
                  representation == .opaque || representation == .premultipliedAlpha,
                  auxiliarySlotsAreData(textureFacts, excluding: slot) else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .independentAlphaSignal(slot):
            guard let representation = representation(
                slot: slot, textureFacts: textureFacts
            ), representation == .opaque || representation == .premultipliedAlpha else {
                return nil
            }
            fragmentOutput = .independentAlphaSignal
        case let .independentAlphaSignalPreserving(slot):
            guard representation(slot: slot, textureFacts: textureFacts)
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
        textureFacts: [ColorTextureFact?]
    ) -> SceneShaderColorRepresentation? {
        guard textureFacts.indices.contains(slot),
              let fact = textureFacts[slot],
              case let .color(.resolved(value)) =
                fact.content else { return nil }
        return value
    }

    private static func auxiliarySlotsAreData(
        _ textureFacts: [ColorTextureFact?],
        excluding colorSlot: Int
    ) -> Bool {
        textureFacts.enumerated().allSatisfy { index, fact in
            guard index != colorSlot, let fact else { return true }
            switch fact.content {
            case .scalarRedUnorm, .data:
                return true
            case .color:
                return false
            }
        }
    }
}
