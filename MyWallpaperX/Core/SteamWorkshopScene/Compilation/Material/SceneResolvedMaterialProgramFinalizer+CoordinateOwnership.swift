nonisolated extension SceneResolvedMaterialProgramFinalizer {
    static func appliedSameSlotMappedCoordinateFacts(
        variant: SceneResolvedMaterialCompiledVariant,
        slots: [SceneResolvedMaterialProgram.TextureSlot?]
    ) -> Set<SceneAuthoredShaderSameSlotMappedCoordinateFact> {
        Set(variant.sameSlotMappedCoordinateFacts.filter { fact in
            guard slots.indices.contains(fact.textureSlot),
                  let slot = slots[fact.textureSlot] else { return false }
            return slot.resource.publication.candidate.axisAlignedMappedUVScale(
                expectedPurpose: slot.expectedPurpose
            ) != nil
        })
    }
}
