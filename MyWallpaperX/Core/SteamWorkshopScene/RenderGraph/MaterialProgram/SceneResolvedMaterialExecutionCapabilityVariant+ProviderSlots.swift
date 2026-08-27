import Foundation

nonisolated extension SceneResolvedMaterialVariantCache {
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
