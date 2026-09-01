import Foundation

/// Exact authored shape whose high-precedence system data can be explicitly
/// absent, exposing a lower same-frame compositor color publication. The two
/// candidates share one sampler slot but require different Program input ABI.
/// Keeping this structural and name-independent prevents a sample/effect
/// dispatch while leaving all unproved mixed chains fail-closed.
nonisolated struct SceneResolvedMaterialMixedProviderSlotFact: Hashable {
    typealias Template = SceneResolvedMaterialTemplate
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler

    let slot: Int
    let lowerNamedReference: SceneNamedTextureReference
    let systemProviderName: String

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
              case let .provider(.system(name)) =
                textureSlot.candidates[1].reference,
              textureSlot.candidates[1].provenance == .userTexture,
              !name.isEmpty,
              sampler.purpose(for: textureSlot.candidates[1].reference)
                == .preservedChannels else { return nil }
        return .init(
            slot: textureSlot.index,
            lowerNamedReference: reference,
            systemProviderName: name
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
        case let .provider(.system(name)) where name == systemProviderName:
            return .preservedChannels
        default:
            return nil
        }
    }
}

nonisolated extension SceneResolvedMaterialVariantCache {
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
