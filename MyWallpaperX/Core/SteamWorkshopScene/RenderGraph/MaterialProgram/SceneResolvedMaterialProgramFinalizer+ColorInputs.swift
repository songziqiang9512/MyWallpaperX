import Foundation

nonisolated extension SceneResolvedMaterialProgramFinalizer {
    static func colorSampleFailure(
        variant: SceneResolvedMaterialCompiledVariant,
        textureSlots: [SceneResolvedMaterialProgram.TextureSlot?]
    ) -> Failure? {
        guard SceneResolvedMaterialProgramDerivation.hasResolvedColorSampleContract(
            colorSlots: variant.preservedAlphaRGBColorSlots,
            textureSlots: textureSlots
        ) else {
            return failure(
                .color,
                .colorContractUnproven,
                details: [
                    "preserved-alpha-rgb-color-slots",
                    variant.preservedAlphaRGBColorSlots.sorted()
                        .map(String.init).joined(separator: ","),
                ]
            )
        }
        if let contract = variant.conditionalGeneratedRGBInputContract,
           !SceneResolvedMaterialProgramDerivation
            .hasResolvedConditionalGeneratedRGBInputContract(
                contract,
                textureSlots: textureSlots
            ) {
            return failure(
                .color,
                .colorContractUnproven,
                details: [
                    "conditional-generated-rgb-input-contract",
                    contract.generatedOpaqueColorSlots.sorted()
                        .map(String.init).joined(separator: ","),
                ]
            )
        }
        return nil
    }
}
