import Foundation

/// Resolves authored and shader-default texture references against one frame
/// snapshot before any Program can enter GPU admission.
nonisolated enum SceneResolvedMaterialTextureResolver {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    struct Resolution {
        let variant: SceneResolvedMaterialCompiledVariant
        let slots: [Program.TextureSlot?]

        var prepared: SceneShaderPreparedProgram { variant.preparedShader }
        var frontend: SceneAuthoredShaderProgram { variant.frontendProgram }
    }

    private typealias Selection = SceneResolvedMaterialTextureSelection.Entry

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant,
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
    ) throws -> Resolution {
        let channelUses = try SceneResolvedMaterialVariantCache
            .validatedSamplerChannelUses(
                variant.activeSamplers,
                bindings: variant.frontendProgram.textureBindings
            )
        guard try readinessMask(
            input,
            samplers: variant.activeSamplers,
            reachableSamplers: reachableSamplers,
            channelUses: channelUses,
            graphInputSourceSlotFacts: variant.graphInputSourceSlotFacts
        )
                == variant.readinessMask else {
            throw failure(.textureReadinessIdentityInvariant, phase: .invariant)
        }
        return .init(
            variant: variant,
            slots: try textureSlots(
                input,
                variant: variant,
                reachableSamplers: reachableSamplers
            )
        )
    }

    static func readinessMask(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        channelUses: [Int: ChannelUse],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) throws -> UInt8 {
        try variantKey(
            input,
            samplers: samplers,
            reachableSamplers: reachableSamplers,
            formatSlots: [],
            channelUses: channelUses,
            allowPresenceIndependentDefaults: true,
            restrictToSamplerSlots: true,
            graphInputSourceSlotFacts: graphInputSourceSlotFacts
        ).readinessMask
    }

    static func variantKey(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        formatSlots: Set<Int>,
        channelUses: [Int: ChannelUse] = [:],
        allowPresenceIndependentDefaults: Bool,
        restrictToSamplerSlots: Bool = false,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) throws -> SceneResolvedMaterialVariantKey {
        guard formatSlots.allSatisfy((0 ..< 8).contains),
              channelUses.keys.allSatisfy((0 ..< 8).contains) else {
            throw failure(.textureVariantKeyIdentityInvariant, phase: .invariant)
        }
        let selections = try SceneResolvedMaterialTextureSelection.resolve(
            input,
            samplers: samplers,
            reachableSamplers: reachableSamplers,
            channelUses: channelUses,
            allowPresenceIndependentDefaults: allowPresenceIndependentDefaults,
            restrictToSamplerSlots: restrictToSamplerSlots,
            graphInputSourceSlotFacts: graphInputSourceSlotFacts
        )
        var mask: UInt8 = 0
        var formats = Array<SceneShaderTextureFormat?>(repeating: nil, count: 8)
        var selectedPurposes = Array<SceneTextureLoadPurpose?>(
            repeating: nil,
            count: 8
        )
        for (slot, selection) in selections.enumerated() {
            switch selection {
            case .absent: break
            case .internalDefault:
                throw failure(.textureBindingInvalid, slot: slot)
            case let .reference(
                reference,
                purpose,
                provenance,
                _
            ):
                let resolved: ResolvedResource
                if let purpose {
                    resolved = try readyResource(
                        input,
                        reference: reference,
                        purpose: purpose,
                        slot: slot
                    )
                } else {
                    guard case let .graph(identity) = reference else {
                        throw failure(
                            .texturePurposeUnproven,
                            slot: slot,
                            details: ["variant-purpose-slot-\(slot)-non-graph"]
                        )
                    }
                    resolved = try readyGraphResource(
                        input,
                        identity: identity,
                        slot: slot
                    )
                    guard [.scalarRedUnorm, .redGreenUnorm,
                           .scalarRedFloat16, .redGreenFloat16].contains(
                            resolved.resource.publication.candidate.content
                           ) else {
                        throw failure(
                            .texturePurposeUnproven,
                            slot: slot,
                            details: ["variant-purpose-slot-\(slot)-graph-content"]
                        )
                    }
                }
                if samplerReadinessIncludes(
                    selectionProvenance: provenance,
                    sampler: samplers[slot]
                ) {
                    mask |= UInt8(1) << UInt8(slot)
                }
                if formatSlots.contains(slot) {
                    formats[slot] = try textureFormatFact(
                        reference: reference,
                        resource: resolved.resource,
                        slot: slot
                    )
                }
                if let sampler = samplers[slot],
                   input.template.textureSlots.indices.contains(slot),
                   let textureSlot = input.template.textureSlots[slot],
                   let mixed = SceneResolvedMaterialMixedProviderSlotFact.resolve(
                       in: textureSlot,
                       sampler: sampler
                   ) {
                    guard let purpose,
                          mixed.purpose(for: reference) == purpose else {
                        throw failure(
                            .textureVariantKeyIdentityInvariant,
                            phase: .invariant,
                            slot: slot
                        )
                    }
                    selectedPurposes[slot] = purpose
                }
            }
        }
        guard let key = SceneResolvedMaterialVariantKey(
            readinessMask: mask,
            textureFormats: formats,
            selectedTexturePurposes: selectedPurposes
        ) else {
            throw failure(.textureVariantKeyIdentityInvariant, phase: .invariant)
        }
        return key
    }

    private static func textureFormatFact(
        reference: Template.TextureReference,
        resource: SceneFrameTextureResource,
        slot: Int
    ) throws -> SceneShaderTextureFormat? {
        let candidate = resource.publication.candidate
        guard case .graph = reference else { return candidate.authoredFormat }
        guard resource.isCompleteGraphResource,
              candidate.authoredFormat == nil else {
            throw failure(
                .textureVariantKeyIdentityInvariant,
                phase: .invariant,
                slot: slot
            )
        }
        switch candidate.content {
        case .scalarRedUnorm:
            return .r8
        case .redGreenUnorm:
            return .rg88
        case .scalarRedFloat16:
            return .r16f
        case .redGreenFloat16:
            return .rg1616f
        case .color:
            return nil
        case .data:
            throw failure(
                .textureVariantKeyIdentityInvariant,
                phase: .invariant,
                slot: slot
            )
        }
    }

    private static func samplerReadinessIncludes(
        selectionProvenance: Program.TextureSelectionProvenance,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?
    ) -> Bool {
        guard selectionProvenance == .shaderDefault,
              sampler?.readinessCombo != nil else { return true }
        return false
    }

    private static func textureSlots(
        _ input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant,
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
    ) throws -> [Program.TextureSlot?] {
        let channelUses = try SceneResolvedMaterialVariantCache
            .validatedSamplerChannelUses(
            variant.activeSamplers,
            bindings: variant.frontendProgram.textureBindings
        )
        let selections = try SceneResolvedMaterialTextureSelection.resolve(
            input,
            samplers: variant.activeSamplers,
            reachableSamplers: reachableSamplers,
            channelUses: channelUses,
            allowPresenceIndependentDefaults: true,
            restrictToSamplerSlots: true,
            graphInputSourceSlotFacts: variant.graphInputSourceSlotFacts
        )
        var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
        for binding in variant.frontendProgram.textureBindings {
            guard case let .reference(
                reference,
                selectedPurpose,
                provenance,
                graphInputSourceFact
            ) =
                    selections[binding.slot] else {
                throw failure(.textureBindingInvalid, slot: binding.slot)
            }
            guard let purpose = selectedPurpose else {
                throw failure(
                    .texturePurposeUnproven,
                    slot: binding.slot,
                    details: ["selected-purpose-slot-\(binding.slot)"]
                )
            }
            let resolved = try readyResource(
                input,
                reference: reference,
                purpose: purpose,
                slot: binding.slot
            )
            result[binding.slot] = .init(
                index: binding.slot,
                reference: reference,
                registryIdentity: resolved.identity,
                diagnosticSelectionProvenance: provenance,
                graphInputSourceFact: graphInputSourceFact,
                expectedPurpose: purpose,
                resource: resolved.resource
            )
        }
        return result
    }

    private typealias ResolvedResource = (
        identity: SceneFrameTextureIdentity,
        resource: SceneFrameTextureResource
    )

    /// Readiness is independent of a framebuffer's eventual color/data use.
    /// The compiled frontend supplies that use before `textureSlots` binds the
    /// resource and validates its exact purpose.
    private static func readyGraphResource(
        _ input: SceneResolvedMaterialFinalizationInput,
        identity: Graph.TextureIdentity,
        slot: Int
    ) throws -> ResolvedResource {
        let registryIdentity = SceneFrameTextureIdentity.graph(identity)
        guard let status = input.textureSnapshot.lookup(registryIdentity) else {
            throw failure(.resourceSnapshotUnresolved, slot: slot)
        }
        guard case let .ready(resource) = status else {
            let code: Failure.Code = if case .incomplete = status {
                .textureMetadataIncomplete
            } else {
                .resourceSnapshotUnresolved
            }
            throw failure(code, slot: slot)
        }
        guard resource.publication.requestIdentity == registryIdentity,
              resource.publication.isComplete,
              resource.publication.candidate.sampling.isResolvedForMaterialProgram
        else { throw failure(.textureMetadataIncomplete, slot: slot) }
        return (registryIdentity, resource)
    }

    private static func readyResource(
        _ input: SceneResolvedMaterialFinalizationInput,
        reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose,
        slot: Int
    ) throws -> ResolvedResource {
        let identity = try runtimeIdentity(reference, purpose: purpose)
        guard let status = input.textureSnapshot.lookup(identity) else {
            throw failure(
                .resourceSnapshotUnresolved,
                slot: slot,
                effectLocalVisualFallback: optionalVisualFallback(
                    .optionalTextureUnavailable,
                    reference: reference,
                    purpose: purpose
                )
            )
        }
        guard case let .ready(resource) = status else {
            let code: Failure.Code
            let fallback: Failure.EffectLocalVisualFallback?
            switch status {
            case let .incomplete(incomplete):
                code = .textureMetadataIncomplete
                fallback = optionalIncompleteVisualFallback(
                    incomplete,
                    identity: identity,
                    reference: reference,
                    purpose: purpose
                )
            case .pending:
                code = .resourceSnapshotUnresolved
                fallback = typedVisualFallback(
                    optional: .optionalTextureUnavailable,
                    system: .systemProviderPending,
                    reference: reference,
                    purpose: purpose
                )
            case .absent, .unavailable:
                code = .resourceSnapshotUnresolved
                fallback = typedVisualFallback(
                    optional: .optionalTextureUnavailable,
                    system: .systemProviderUnavailable,
                    reference: reference,
                    purpose: purpose
                )
            case .ready:
                code = .identityInvariant
                fallback = nil
            }
            throw failure(
                code,
                slot: slot,
                effectLocalVisualFallback: fallback
            )
        }
        let publication = resource.publication
        guard publication.requestIdentity == identity,
              publication.isComplete else {
            throw failure(.textureMetadataIncomplete, slot: slot)
        }
        guard publication.candidate.purpose == purpose else {
            throw failure(
                .textureMetadataIncomplete,
                slot: slot,
                effectLocalVisualFallback: typedVisualFallback(
                    optional: .optionalTexturePurposeMismatch,
                    system: .systemProviderPurposeMismatch,
                    reference: reference,
                    purpose: purpose
                )
            )
        }
        guard publication.candidate.sampling.isResolvedForMaterialProgram else {
            throw failure(
                .textureMetadataIncomplete,
                slot: slot,
                effectLocalVisualFallback: typedVisualFallback(
                    optional: .optionalTextureSamplingUnresolved,
                    system: .systemProviderSamplingUnresolved,
                    reference: reference,
                    purpose: purpose
                )
            )
        }
        return (identity, resource)
    }

    private static func optionalIncompleteVisualFallback(
        _ incomplete: SceneFrameTextureIncompleteResource,
        identity: SceneFrameTextureIdentity,
        reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) -> Failure.EffectLocalVisualFallback? {
        guard optionalVisualReference(reference, purpose: purpose) else {
            return nil
        }
        guard case let .publication(publication, resourceGeneration) = incomplete,
              resourceGeneration > 0,
              publication.contentGeneration > 0,
              publication.requestIdentity == identity,
              publicationGenerationIsCurrent(publication) else {
            return nil
        }
        if publication.candidate.purpose != purpose {
            return .optionalTexturePurposeMismatch
        }
        guard publication.candidate.content == .data else {
            return .optionalTextureContentMismatch
        }
        return nil
    }

    private static func publicationGenerationIsCurrent(
        _ publication: SceneTextureProviderPublication
    ) -> Bool {
        switch (
            publication.candidate.identity,
            publication.candidate.generation
        ) {
        case (.file, .file), (.builtIn, .immutable):
            return true
        case let (.provider, .provider(contentGeneration)):
            return contentGeneration == publication.contentGeneration
        default:
            return false
        }
    }

    private static func optionalVisualFallback(
        _ fallback: Failure.EffectLocalVisualFallback,
        reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) -> Failure.EffectLocalVisualFallback? {
        optionalVisualReference(reference, purpose: purpose) ? fallback : nil
    }

    private static func typedVisualFallback(
        optional: Failure.EffectLocalVisualFallback,
        system: Failure.EffectLocalVisualFallback,
        reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) -> Failure.EffectLocalVisualFallback? {
        if optionalVisualReference(reference, purpose: purpose) {
            return optional
        }
        return systemProviderVisualReference(reference) ? system : nil
    }

    private static func optionalVisualReference(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) -> Bool {
        guard purpose == .mask else { return false }
        switch reference {
        case .asset, .userProperty:
            return true
        case .provider, .graph:
            return false
        }
    }

    private static func systemProviderVisualReference(
        _ reference: Template.TextureReference
    ) -> Bool {
        guard case .provider(.system) = reference else { return false }
        return true
    }

    private static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        effectLocalVisualFallback: Failure.EffectLocalVisualFallback? = nil,
        details: [String] = []
    ) -> Failure {
        .init(
            phase: phase,
            code: code,
            slot: slot,
            effectLocalVisualFallback: effectLocalVisualFallback,
            details: details
        )
    }
}
