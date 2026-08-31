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
        let isFramebufferInput: Bool
        let content: SceneTextureContent
    }

    /// Source-proven input roles for the one bounded shape that combines
    /// generated RGB with an independently sampled carrier alpha. Keeping the
    /// roles explicit prevents its mixed-representation allowance from
    /// broadening every straight-alpha-preserving shader.
    struct ConditionalGeneratedRGBInputContract: Hashable {
        let alphaCarrierSlot: Int
        let generatedOpaqueColorSlots: Set<Int>
        let scalarRedSlots: Set<Int>
        let scalarGreenSlots: Set<Int>
        let scalarBlueSlots: Set<Int>
        let scalarAlphaSlots: Set<Int>
    }

    /// Source-proven roles for a same-alpha color reconstruction. Auxiliary
    /// slots are byte-semantic authored data and must never be interpreted as
    /// premultiplied color merely because their texture format is RGBA.
    struct SameAlphaReconstructedRGBInputContract: Hashable {
        let sourceSlot: Int
        let dataSlots: Set<Int>
    }

    static func associatedOverOverlaySlot(fragmentSource: String) -> Int? {
        if let overlay = SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(
            fragmentSource: fragmentSource
        )?.overlaySlot {
            return overlay
        }
        return SceneAuthoredShaderColorTransferAnalyzer.blendSourceSlots(
            fragmentSource: fragmentSource
        ).overlayAlpha?.overlay
    }

    static func hasResolvedColorContract(
        transfer: SceneShaderColorTransfer,
        textureSlots: [Program.TextureSlot?],
        conditionalGeneratedRGBInputContract:
            ConditionalGeneratedRGBInputContract? = nil,
        associatedOverOverlaySlot: Int? = nil,
        premultipliedColorInputSlots: Set<Int> = []
    ) -> Bool {
        resolveColor(
            transfer: transfer,
            textureSlots: textureSlots,
            conditionalGeneratedRGBInputContract:
                conditionalGeneratedRGBInputContract,
            associatedOverOverlaySlot: associatedOverOverlaySlot,
            premultipliedColorInputSlots: premultipliedColorInputSlots
        ) != nil
    }

    static func hasResolvedColorSampleContract(
        colorSlots: Set<Int>,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        hasResolvedColorSampleContract(
            colorSlots: colorSlots,
            textureFacts: textureSlots.map { slot -> ColorTextureFact? in
                guard let slot else { return nil }
                let isGraphReference = if case .graph = slot.reference {
                    true
                } else {
                    false
                }
                let isFramebufferInput = switch slot.reference {
                case .graph, .provider(.sceneBackground): true
                default: false
                }
                return .init(
                    isGraphReference: isGraphReference,
                    isFramebufferInput: isFramebufferInput,
                    content: slot.resource.publication.candidate.content
                )
            }
        )
    }

    static func hasResolvedColorSampleContract(
        colorSlots: Set<Int>,
        textureFacts: [ColorTextureFact?]
    ) -> Bool {
        guard textureFacts.count == 8 else { return false }
        return colorSlots.allSatisfy { slot in
            guard let representation = representation(
                slot: slot,
                textureFacts: textureFacts
            ) else { return false }
            return representation == .opaque
                || representation == .premultipliedAlpha
        }
    }

    /// Generated RGB that is not moved through an unpremultiply boundary may
    /// only consume source-proven opaque color. The carrier alpha is checked
    /// separately by the transfer projection.
    static func hasResolvedOpaqueColorSampleContract(
        colorSlots: Set<Int>,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        hasResolvedOpaqueColorSampleContract(
            colorSlots: colorSlots,
            textureFacts: textureSlots.map { slot -> ColorTextureFact? in
                guard let slot else { return nil }
                let isGraphReference = if case .graph = slot.reference {
                    true
                } else {
                    false
                }
                let isFramebufferInput = switch slot.reference {
                case .graph, .provider(.sceneBackground): true
                default: false
                }
                return .init(
                    isGraphReference: isGraphReference,
                    isFramebufferInput: isFramebufferInput,
                    content: slot.resource.publication.candidate.content
                )
            }
        )
    }

    static func hasResolvedOpaqueColorSampleContract(
        colorSlots: Set<Int>,
        textureFacts: [ColorTextureFact?]
    ) -> Bool {
        guard textureFacts.count == 8 else { return false }
        return colorSlots.allSatisfy { slot in
            representation(slot: slot, textureFacts: textureFacts) == .opaque
        }
    }

    static func hasResolvedConditionalGeneratedRGBInputContract(
        _ contract: ConditionalGeneratedRGBInputContract,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        hasResolvedConditionalGeneratedRGBInputContract(
            contract,
            textureFacts: textureSlots.map(colorTextureFact)
        )
    }

    static func hasResolvedConditionalGeneratedRGBInputContract(
        _ contract: ConditionalGeneratedRGBInputContract,
        textureFacts: [ColorTextureFact?]
    ) -> Bool {
        guard textureFacts.count == 8,
              hasResolvedOpaqueColorSampleContract(
                colorSlots: contract.generatedOpaqueColorSlots,
                textureFacts: textureFacts
              ),
              contract.scalarRedSlots.allSatisfy({
                  scalarComponentIsResolved(
                    .red,
                    slot: $0,
                    textureFacts: textureFacts
                  )
              }),
              contract.scalarGreenSlots.allSatisfy({
                  scalarComponentIsResolved(
                    .green,
                    slot: $0,
                    textureFacts: textureFacts
                  )
              }),
              contract.scalarBlueSlots.allSatisfy({
                  scalarComponentIsResolved(
                    .blue,
                    slot: $0,
                    textureFacts: textureFacts
                  )
              }),
              contract.scalarAlphaSlots.allSatisfy({
                  scalarComponentIsResolved(
                    .alpha,
                    slot: $0,
                    textureFacts: textureFacts
                  )
              }) else { return false }
        return true
    }

    static func hasResolvedSameAlphaReconstructedRGBInputContract(
        _ contract: SameAlphaReconstructedRGBInputContract,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        hasResolvedSameAlphaReconstructedRGBInputContract(
            contract,
            textureFacts: textureSlots.map(colorTextureFact)
        )
    }

    static func hasResolvedSameAlphaReconstructedRGBInputContract(
        _ contract: SameAlphaReconstructedRGBInputContract,
        textureFacts: [ColorTextureFact?]
    ) -> Bool {
        guard textureFacts.count == 8,
              (0 ..< 8).contains(contract.sourceSlot),
              !contract.dataSlots.isEmpty,
              !contract.dataSlots.contains(contract.sourceSlot),
              let source = representation(
                  slot: contract.sourceSlot,
                  textureFacts: textureFacts
              ),
              source == .opaque || source == .premultipliedAlpha else {
            return false
        }
        return contract.dataSlots.allSatisfy { slot in
            guard textureFacts.indices.contains(slot),
                  let fact = textureFacts[slot] else { return false }
            return fact.content == .data
        }
    }

    static func resolveColor(
        transfer: SceneShaderColorTransfer,
        textureSlots: [Program.TextureSlot?],
        conditionalGeneratedRGBInputContract:
            ConditionalGeneratedRGBInputContract? = nil,
        associatedOverOverlaySlot: Int? = nil,
        premultipliedColorInputSlots: Set<Int> = []
    ) -> ColorProjection? {
        resolveColor(
            transfer: transfer,
            textureFacts: textureSlots.map(colorTextureFact),
            conditionalGeneratedRGBInputContract:
                conditionalGeneratedRGBInputContract,
            associatedOverOverlaySlot: associatedOverOverlaySlot,
            premultipliedColorInputSlots: premultipliedColorInputSlots
        )
    }

    static func resolveColor(
        transfer: SceneShaderColorTransfer,
        textureFacts: [ColorTextureFact?],
        conditionalGeneratedRGBInputContract:
            ConditionalGeneratedRGBInputContract? = nil,
        associatedOverOverlaySlot: Int? = nil,
        premultipliedColorInputSlots: Set<Int> = []
    ) -> ColorProjection? {
        guard textureFacts.count == 8 else { return nil }
        if let contract = conditionalGeneratedRGBInputContract {
            guard transfer == .straightAlphaPreserving(
                textureSlot: contract.alphaCarrierSlot
            ), hasResolvedConditionalGeneratedRGBInputContract(
                contract,
                textureFacts: textureFacts
            ) else { return nil }
        }
        var framebufferRepresentations: Set<SceneShaderColorRepresentation> = []
        for fact in textureFacts.compactMap({ $0 }) where fact.isFramebufferInput {
            switch fact.content {
            case let .color(.resolved(representation)):
                framebufferRepresentations.insert(representation)
            case .color(.unresolved):
                return nil
            case .scalarRedUnorm, .redGreenUnorm, .scalarRedFloat16,
                 .redGreenFloat16, .data:
                continue
            }
        }
        let framebufferInput: SceneShaderColorRepresentation
        if (transfer == .opaque || transfer == .premultipliedAlpha
                || transfer == .generatedStraightAlpha),
           framebufferRepresentations.isEmpty {
            // An opaque procedural pass can declare an authored framebuffer
            // sampler that the prepared variant never reads. Use one stable
            // identity value without claiming or requiring a sampled input.
            framebufferInput = .opaque
        } else if let contract = conditionalGeneratedRGBInputContract,
                  case let .straightAlphaPreserving(slot) = transfer,
                  contract.alphaCarrierSlot == slot {
            guard let representation = representation(
                slot: slot,
                textureFacts: textureFacts
            ), representation == .opaque
                || representation == .premultipliedAlpha else {
                return nil
            }
            // The alpha carrier defines the framebuffer projection. Other
            // color inputs may be source-proven opaque generated RGB and are
            // validated independently before this projection is resolved.
            framebufferInput = representation
        } else if case let .independentAlphaSignalCompositing(
            signalSlot,
            colorSlot
        ) = transfer {
            guard representation(slot: signalSlot, textureFacts: textureFacts)
                    == .independentAlphaSignal,
                  let color = representation(slot: colorSlot, textureFacts: textureFacts),
                  color == .opaque || color == .premultipliedAlpha,
                  auxiliarySlotsAreData(
                    textureFacts,
                    excluding: [signalSlot, colorSlot]
                  ) else {
                return nil
            }
            framebufferInput = color
        } else {
            guard framebufferRepresentations.count == 1,
                  let representation = framebufferRepresentations.first else {
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
        case let .opaqueFromStraightColor(slot):
            guard let representation = representation(
                slot: slot,
                textureFacts: textureFacts
            ), representation == .opaque || representation == .premultipliedAlpha,
               auxiliarySlotsAreData(textureFacts, excluding: [slot]) else {
                return nil
            }
            fragmentOutput = .opaque
        case .premultipliedAlpha:
            guard textureFacts.compactMap({ $0 }).allSatisfy({ fact in
                switch fact.content {
                case .scalarRedUnorm, .redGreenUnorm, .scalarRedFloat16,
                     .redGreenFloat16, .data:
                    return true
                case .color:
                    return false
                }
            }) else { return nil }
            fragmentOutput = .premultipliedAlpha
        case .generatedStraightAlpha:
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
        case let .interpolatedColor(slots):
            guard slots.count >= 2,
                  slots == slots.sorted(),
                  Set(slots).count == slots.count else { return nil }
            let representations = slots.compactMap {
                representation(slot: $0, textureFacts: textureFacts)
            }
            guard representations.count == slots.count,
                  Set(representations).count == 1,
                  let representation = representations.first else {
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
                  associatedOverAuxiliarySlotsAreAllowed(
                      textureFacts,
                      sourceSlot: slot,
                      overlaySlot: associatedOverOverlaySlot,
                      premultipliedColorInputSlots:
                        premultipliedColorInputSlots
                  ) else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .straightAlphaUNorm(slot):
            guard textureFacts.indices.contains(slot),
                  let fact = textureFacts[slot],
                  case let .color(.resolved(representation)) = fact.content,
                  representation == .opaque || representation == .premultipliedAlpha,
                  auxiliarySlotsAreData(textureFacts, excluding: [slot]) else {
                return nil
            }
            fragmentOutput = .premultipliedAlpha
        case let .independentAlphaSignal(slot):
            guard let representation = representation(
                slot: slot, textureFacts: textureFacts
            ), representation == .opaque || representation == .premultipliedAlpha,
               auxiliarySlotsAreData(textureFacts, excluding: [slot]) else {
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

    private enum ScalarComponent {
        case red
        case green
        case blue
        case alpha
    }

    private static func scalarComponentIsResolved(
        _ component: ScalarComponent,
        slot: Int,
        textureFacts: [ColorTextureFact?]
    ) -> Bool {
        guard textureFacts.indices.contains(slot),
              let fact = textureFacts[slot] else { return false }
        switch (component, fact.content) {
        case (_, .data):
            return true
        case (.red, .scalarRedUnorm), (.red, .redGreenUnorm),
             (.red, .scalarRedFloat16), (.red, .redGreenFloat16),
             (.green, .redGreenUnorm), (.green, .redGreenFloat16):
            return true
        case (.red, .color(.resolved(.opaque))),
             (.green, .color(.resolved(.opaque))),
             (.blue, .color(.resolved(.opaque))):
            return true
        case (.alpha, .color(.resolved)):
            return true
        case (_, .color), (_, .scalarRedUnorm), (_, .redGreenUnorm),
             (_, .scalarRedFloat16), (_, .redGreenFloat16):
            return false
        }
    }

    private static func colorTextureFact(
        _ slot: Program.TextureSlot?
    ) -> ColorTextureFact? {
        guard let slot else { return nil }
        let isGraphReference = if case .graph = slot.reference {
            true
        } else {
            false
        }
        let isFramebufferInput = switch slot.reference {
        case .graph, .provider(.sceneBackground): true
        default: false
        }
        return .init(
            isGraphReference: isGraphReference,
            isFramebufferInput: isFramebufferInput,
            content: slot.resource.publication.candidate.content
        )
    }

    private static func auxiliarySlotsAreData(
        _ textureFacts: [ColorTextureFact?],
        excluding colorSlots: Set<Int>
    ) -> Bool {
        textureFacts.enumerated().allSatisfy { index, fact in
            guard !colorSlots.contains(index), let fact else { return true }
            switch fact.content {
            case .scalarRedUnorm, .redGreenUnorm, .scalarRedFloat16,
                 .redGreenFloat16, .data:
                return true
            case .color:
                return false
            }
        }
    }

    /// Associated-over and overlay-alpha authored math consumes straight RGBA.
    /// Typed data remains unchanged; a resolved premultiplied color overlay is
    /// legal only when the exact compiled Program records that slot in its
    /// input-representation ABI and unpremultiplies it before authored math.
    private static func associatedOverAuxiliarySlotsAreAllowed(
        _ textureFacts: [ColorTextureFact?],
        sourceSlot: Int,
        overlaySlot: Int?,
        premultipliedColorInputSlots: Set<Int>
    ) -> Bool {
        guard let overlaySlot, overlaySlot != sourceSlot,
              textureFacts.indices.contains(overlaySlot),
              let overlay = textureFacts[overlaySlot]
        else {
            return premultipliedColorInputSlots.isEmpty
                && auxiliarySlotsAreData(
                    textureFacts,
                    excluding: [sourceSlot]
                )
        }
        switch overlay.content {
        case .data:
            return premultipliedColorInputSlots.isEmpty
                && auxiliarySlotsAreData(
                textureFacts,
                excluding: [sourceSlot, overlaySlot]
            )
        case .color(.resolved(.premultipliedAlpha)):
            return premultipliedColorInputSlots == Set([overlaySlot])
                && auxiliarySlotsAreData(
                    textureFacts,
                    excluding: [sourceSlot, overlaySlot]
                )
        case .color, .scalarRedUnorm, .redGreenUnorm, .scalarRedFloat16,
             .redGreenFloat16:
            return false
        }
    }
}
