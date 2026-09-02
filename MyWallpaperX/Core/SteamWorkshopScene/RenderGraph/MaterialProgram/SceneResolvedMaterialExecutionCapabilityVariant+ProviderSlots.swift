import Foundation

/// Exact authored shape whose high-precedence optional input can be explicitly
/// absent, exposing a lower same-frame compositor color publication. The two
/// candidates share one sampler slot but require different Program input ABI.
/// Keeping this structural and name-independent prevents a sample/effect
/// dispatch while leaving all unproved mixed chains fail-closed.
nonisolated struct SceneResolvedMaterialMixedProviderSlotFact: Hashable {
    typealias Template = SceneResolvedMaterialTemplate
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler

    enum OptionalInput: Hashable {
        case system(String)
        case userProperty(String)

        init?(_ reference: Template.TextureReference) {
            switch reference {
            case let .provider(.system(name)) where !name.isEmpty:
                self = .system(name)
            case let .userProperty(request) where !request.key.isEmpty:
                self = .userProperty(request.key)
            default:
                return nil
            }
        }

        func matches(_ reference: Template.TextureReference) -> Bool {
            switch (self, reference) {
            case let (.system(expected), .provider(.system(actual))):
                expected == actual
            case let (.userProperty(expected), .userProperty(actual)):
                expected == actual.key
            default:
                false
            }
        }
    }

    let slot: Int
    let lowerNamedReference: SceneNamedTextureReference
    let optionalInput: OptionalInput

    static func resolve(
        in textureSlot: Template.TextureSlot,
        sampler: Sampler
    ) -> Self? {
        guard textureSlot.index == sampler.slot,
              textureSlot.candidates.count == 2,
              sampler.mode == .rgbMask,
              sampler.sourceProvenPurpose == nil
                || sampler.sourceProvenPurpose == .preservedChannels,
              defaultTextureIsNonOwning(sampler.defaultTexture),
              case let .provider(.namedLayerTarget(reference)) =
                textureSlot.candidates[0].reference,
              reference.variant == .primary,
              textureSlot.candidates[0].provenance != .explicitBinding,
              textureSlot.candidates[1].provenance == .userTexture,
              let optionalInput = OptionalInput(
                  textureSlot.candidates[1].reference
              ),
              sampler.purpose(for: textureSlot.candidates[1].reference)
                == .preservedChannels else { return nil }
        return .init(
            slot: textureSlot.index,
            lowerNamedReference: reference,
            optionalInput: optionalInput
        )
    }

    /// An authored asset default is only a declaration fallback. The exact
    /// system/named candidate chain still owns frame selection, and any
    /// pending/unavailable named target remains terminal rather than silently
    /// substituting this asset. Internal targets have independent lifecycle
    /// and are not part of this representation-switch contract.
    private static func defaultTextureIsNonOwning(
        _ reference: SceneResolvedMaterialShaderSchema.DefaultTexture?
    ) -> Bool {
        switch reference {
        case nil, .asset:
            true
        case .internalTarget:
            false
        }
    }

    func purpose(
        for reference: Template.TextureReference
    ) -> SceneTextureLoadPurpose? {
        switch reference {
        case let .provider(.namedLayerTarget(reference))
        where reference == lowerNamedReference:
            return .premultipliedColor
        case let reference where optionalInput.matches(reference):
            return .preservedChannels
        default:
            return nil
        }
    }
}

nonisolated extension SceneResolvedMaterialVariantCache {
    static func unsupportedInternalTarget(
        in samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template
    ) -> (slot: Int, name: String)? {
        for (slot, sampler) in samplers.sorted(by: { $0.key < $1.key }) {
            guard case let .internalTarget(name)? = sampler.defaultTexture else {
                continue
            }
            guard SceneResolvedMaterialTextureResolver.sceneBackgroundDefault(
                template: template,
                sampler: sampler,
                slot: slot
            ) != nil else { return (slot, name) }
        }
        return nil
    }

    static func mixedProviderSlotFacts(
        in template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> [Int: SceneResolvedMaterialMixedProviderSlotFact] {
        Dictionary(uniqueKeysWithValues: samplers.compactMap { slot, sampler in
            guard template.textureSlots.indices.contains(slot),
                  let textureSlot = template.textureSlots[slot],
                  let fact = SceneResolvedMaterialMixedProviderSlotFact.resolve(
                      in: textureSlot,
                      sampler: sampler
                  ) else { return nil }
            return (slot, fact)
        })
    }

    static func hasExternalProviderTexture(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Bool {
        !externalProviderTextureSlots(
            in: template,
            activeTextureSlots: activeTextureSlots
        ).isEmpty
    }

    static func externalProviderTextureSlots(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Set<Int> {
        Set(template.textureSlots.enumerated().compactMap { index, slot in
            guard activeTextureSlots?.contains(index) != false,
                  let slot else { return nil }
            // Candidate order is low to high precedence. A terminal graph
            // reference is the immutable selected override; earlier provider
            // entries are provenance and cannot become runtime fallbacks.
            if case .graph? = slot.candidates.last?.reference {
                return nil
            }
            return slot.candidates.contains { candidate in
                if case .provider = candidate.reference { return true }
                return false
            } ? index : nil
        })
    }

    static func terminalNamedLayerProviderTextureSlots(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Set<Int> {
        Set(template.textureSlots.enumerated().compactMap { index, slot in
            guard activeTextureSlots?.contains(index) != false,
                  let selected = slot?.candidates.last,
                  case let .provider(.namedLayerTarget(reference)) =
                    selected.reference,
                  reference.variant == .primary else {
                return nil
            }
            return index
        })
    }
}
