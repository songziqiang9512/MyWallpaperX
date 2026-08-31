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
        guard SceneResolvedMaterialProgramDerivation
            .hasResolvedOpaqueColorSampleContract(
                colorSlots: variant.sourceProvenOpaqueColorSlots,
                textureSlots: textureSlots
            ) else {
            return failure(
                .color,
                .colorContractUnproven,
                details: [
                    "source-proven-opaque-color-slots",
                    variant.sourceProvenOpaqueColorSlots.sorted()
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
        if let contract = variant.sameAlphaReconstructedRGBInputContract,
           !SceneResolvedMaterialProgramDerivation
            .hasResolvedSameAlphaReconstructedRGBInputContract(
                contract,
                textureSlots: textureSlots
            ) {
            return failure(
                .color,
                .colorContractUnproven,
                details: [
                    "same-alpha-reconstructed-rgb-input-contract",
                    contract.dataSlots.sorted()
                        .map(String.init).joined(separator: ","),
                ]
            )
        }
        return nil
    }

    /// Redacted typed atoms for the uncommon frame-time rejection path. The
    /// graph executor adds node/material identity to the enclosing diagnostic.
    static func colorContractFailureDetails(
        transfer: SceneShaderColorTransfer,
        slots: [Program.TextureSlot?]
    ) -> [String] {
        [
            "transfer-\(SceneResolvedMaterialProgramIdentity.colorTransferToken(transfer))"
        ]
            + slots.compactMap { slot in
                guard let slot else { return nil }
                let publication = slot.resource.publication
                return "slot-\(slot.index)-ref-\(referenceToken(slot.reference))-"
                    + "content-\(contentToken(publication.candidate.content))-"
                    + "purpose-\(String(describing: slot.expectedPurpose))-"
                    + "request-\(requestToken(publication.requestIdentity))-"
                    + "resource-\(resourceToken(publication.candidate.identity))-"
                    + "cg-\(publication.contentGeneration)-"
                    + "rg-\(slot.resource.resourceGeneration)"
            }
    }

    private static func referenceToken(_ reference: Template.TextureReference) -> String {
        switch reference {
        case .asset: "asset"
        case .userProperty: "user-property"
        case .provider(.system): "provider-system"
        case .provider(.namedLayerTarget): "provider-named-layer"
        case .provider(.sceneBackground): "provider-scene-background"
        case let .graph(identity): "graph-\(identity.kind.rawValue)"
        }
    }

    private static func contentToken(_ content: SceneTextureContent) -> String {
        switch content {
        case .color(.unresolved): "color-unresolved"
        case let .color(.resolved(value)): "color-\(String(describing: value))"
        case .scalarRedUnorm: "scalar-r-unorm"
        case .redGreenUnorm: "rg-unorm"
        case .scalarRedFloat16: "scalar-r-f16"
        case .redGreenFloat16: "rg-f16"
        case .data: "data"
        }
    }

    private static func requestToken(_ identity: SceneFrameTextureIdentity) -> String {
        switch identity {
        case .layerSource: "layer-source"
        case .namedLayerTarget: "named-layer-target"
        case .sceneBackground: "scene-background"
        case let .graph(identity): "graph-\(identity.kind.rawValue)"
        case .asset: "asset"
        case .userProperty: "user-property"
        case .materialUserProperty: "material-user-property"
        case .system: "system"
        }
    }

    private static func resourceToken(_ identity: SceneTextureResourceIdentity) -> String {
        switch identity {
        case .file: "file"
        case .builtIn: "built-in"
        case .provider(.dynamicText): "provider-dynamic-text"
        case .provider(.graph): "provider-graph"
        case .provider(.mediaThumbnailCurrent): "provider-media-thumbnail"
        case .provider(.mediaThumbnailPrevious): "provider-media-thumbnail-previous"
        case .provider(.namedLayerTarget): "provider-named-layer"
        case .provider(.sceneBackground): "provider-scene-background"
        case .provider(.video): "provider-video"
        }
    }
}
