/// Proves the purpose of one exact authored candidate without losing its
/// ordinal or provenance inside the immutable eight-slot Template.
nonisolated enum SceneResolvedMaterialTextureSlotPurpose {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Template = SceneResolvedMaterialTemplate

    struct Fact: Hashable {
        let slot: Int
        let ordinal: Int
        let reference: Template.TextureReference
        let provenance: SceneResolvedMaterialNode.TextureProvenance
        let purpose: SceneTextureLoadPurpose
    }

    static func fact(
        in slot: Template.TextureSlot,
        candidateOrdinal: Int,
        sampler: Sampler
    ) -> Fact? {
        guard slot.index == sampler.slot,
              slot.candidates.indices.contains(candidateOrdinal) else {
            return nil
        }
        let candidate = slot.candidates[candidateOrdinal]
        let directPurpose = sampler.purpose(for: candidate.reference)
        guard case let .asset(path) = candidate.reference else {
            return directPurpose.map {
                Fact(
                    slot: slot.index,
                    ordinal: candidateOrdinal,
                    reference: candidate.reference,
                    provenance: candidate.provenance,
                    purpose: $0
                )
            }
        }

        let registeredPurpose = SceneStockTextureSemanticRegistry.purpose(
            for: path
        )
        // Existing mode/material/default facts remain authoritative. Slot-chain
        // inheritance applies only when an asset has no direct fact, while an
        // exact registered instance override additionally participates in the
        // lower-chain conflict check.
        if directPurpose != nil && registeredPurpose == nil {
            return makeFact(
                slot: slot,
                ordinal: candidateOrdinal,
                candidate: candidate,
                purpose: directPurpose
            )
        }
        guard candidate.provenance == .instance,
              candidateOrdinal > slot.candidates.startIndex else {
            return makeFact(
                slot: slot,
                ordinal: candidateOrdinal,
                candidate: candidate,
                purpose: directPurpose
            )
        }

        var lowerPurposes: [SceneTextureLoadPurpose] = []
        for ordinal in slot.candidates.indices where ordinal < candidateOrdinal {
            let lower = slot.candidates[ordinal]
            guard lower.provenance == .material,
                  case let .asset(lowerPath) = lower.reference,
                  let exact = SceneStockTextureSemanticRegistry.purpose(
                      for: lowerPath
                  ),
                  sampler.purpose(for: lower.reference) == exact else {
                return makeFact(
                    slot: slot,
                    ordinal: candidateOrdinal,
                    candidate: candidate,
                    purpose: directPurpose
                )
            }
            lowerPurposes.append(exact)
        }
        guard !lowerPurposes.isEmpty else {
            return makeFact(
                slot: slot,
                ordinal: candidateOrdinal,
                candidate: candidate,
                purpose: directPurpose
            )
        }
        let unique = Set(lowerPurposes)
        guard unique.count == 1, let inheritedPurpose = unique.first else {
            return nil
        }
        if let registeredPurpose {
            guard registeredPurpose == inheritedPurpose,
                  directPurpose == registeredPurpose else { return nil }
            return makeFact(
                slot: slot,
                ordinal: candidateOrdinal,
                candidate: candidate,
                purpose: registeredPurpose
            )
        }
        guard directPurpose == nil else {
            return makeFact(
                slot: slot,
                ordinal: candidateOrdinal,
                candidate: candidate,
                purpose: directPurpose
            )
        }
        return makeFact(
            slot: slot,
            ordinal: candidateOrdinal,
            candidate: candidate,
            purpose: inheritedPurpose
        )
    }

    private static func makeFact(
        slot: Template.TextureSlot,
        ordinal: Int,
        candidate: Template.TextureCandidate,
        purpose: SceneTextureLoadPurpose?
    ) -> Fact? {
        purpose.map {
            Fact(
                slot: slot.index,
                ordinal: ordinal,
                reference: candidate.reference,
                provenance: candidate.provenance,
                purpose: $0
            )
        }
    }
}
