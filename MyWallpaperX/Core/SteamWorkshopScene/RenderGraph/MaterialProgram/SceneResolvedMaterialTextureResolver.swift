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
        _ input: SceneResolvedMaterialFinalizationInput
    ) throws -> Resolution {
        guard let cache = SceneResolvedMaterialVariantCache(
            template: input.template,
            maximumVariantCount: 8
        ) else { throw failure(.activeSamplerSchemaInvalid) }
        switch cache.resolveSelection(input) {
        case let .success(selection):
            return try resolve(
                input,
                variant: selection.variant,
                reachableSamplers: selection.reachableSamplers
            )
        case let .failure(error):
            throw error
        }
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant,
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
    ) throws -> Resolution {
        guard try readinessMask(
            input,
            samplers: variant.activeSamplers,
            reachableSamplers: reachableSamplers
        )
                == variant.readinessMask else {
            throw failure(.identityInvariant, phase: .invariant)
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
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
    ) throws -> UInt8 {
        try variantKey(
            input,
            samplers: samplers,
            reachableSamplers: reachableSamplers,
            formatSlots: [],
            allowPresenceIndependentDefaults: true,
            restrictToSamplerSlots: true
        ).readinessMask
    }

    static func variantKey(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        formatSlots: Set<Int>,
        channelUses: [Int: ChannelUse] = [:],
        allowPresenceIndependentDefaults: Bool,
        restrictToSamplerSlots: Bool = false
    ) throws -> SceneResolvedMaterialVariantKey {
        guard formatSlots.allSatisfy((0 ..< 8).contains),
              channelUses.keys.allSatisfy((0 ..< 8).contains) else {
            throw failure(.identityInvariant, phase: .invariant)
        }
        let selections = try SceneResolvedMaterialTextureSelection.resolve(
            input,
            samplers: samplers,
            reachableSamplers: reachableSamplers,
            channelUses: channelUses,
            allowPresenceIndependentDefaults: allowPresenceIndependentDefaults,
            restrictToSamplerSlots: restrictToSamplerSlots
        )
        var mask: UInt8 = 0
        var formats = Array<SceneShaderTextureFormat?>(repeating: nil, count: 8)
        for (slot, selection) in selections.enumerated() {
            switch selection {
            case .absent: break
            case .internalDefault:
                throw failure(.textureBindingInvalid, slot: slot)
            case let .reference(reference, purpose, provenance):
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
                        throw failure(.texturePurposeUnproven, slot: slot)
                    }
                    resolved = try readyGraphResource(
                        input,
                        identity: identity,
                        slot: slot
                    )
                    guard resolved.resource.publication.candidate.content
                            == .scalarRedUnorm else {
                        throw failure(.texturePurposeUnproven, slot: slot)
                    }
                }
                if samplerReadinessIncludes(
                    selectionProvenance: provenance,
                    sampler: samplers[slot]
                ) {
                    mask |= UInt8(1) << UInt8(slot)
                }
                if formatSlots.contains(slot) {
                    formats[slot] = resolved.resource.publication.candidate
                        .authoredFormat
                }
            }
        }
        guard let key = SceneResolvedMaterialVariantKey(
            readinessMask: mask,
            textureFormats: formats
        ) else { throw failure(.identityInvariant, phase: .invariant) }
        return key
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
        let selections = try SceneResolvedMaterialTextureSelection.resolve(
            input,
            samplers: variant.activeSamplers,
            reachableSamplers: reachableSamplers,
            channelUses: Dictionary(uniqueKeysWithValues:
                variant.frontendProgram.textureBindings.map {
                    ($0.slot, $0.channelUse)
                }
            ),
            allowPresenceIndependentDefaults: true,
            restrictToSamplerSlots: true
        )
        let bindingSlots = variant.frontendProgram.textureBindings.map(\.slot)
        guard Set(bindingSlots).count == bindingSlots.count else {
            throw failure(.activeSamplerSchemaInvalid)
        }
        var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
        for binding in variant.frontendProgram.textureBindings {
            guard result.indices.contains(binding.slot),
                  let sampler = variant.activeSamplers[binding.slot],
                  sampler.name == binding.name else {
                throw failure(.activeSamplerSchemaInvalid, slot: binding.slot)
            }
            guard case let .reference(
                reference,
                selectedPurpose,
                provenance
            ) =
                    selections[binding.slot] else {
                throw failure(.textureBindingInvalid, slot: binding.slot)
            }
            guard let purpose = selectedPurpose else {
                throw failure(.texturePurposeUnproven, slot: binding.slot)
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
            throw failure(.resourceSnapshotUnresolved, slot: slot)
        }
        guard case let .ready(resource) = status else {
            let code: Failure.Code
            switch status {
            case .incomplete:
                code = .textureMetadataIncomplete
            case .absent, .pending, .unavailable:
                code = .resourceSnapshotUnresolved
            case .ready:
                code = .identityInvariant
            }
            throw failure(code, slot: slot)
        }
        let publication = resource.publication
        guard publication.requestIdentity == identity,
              publication.isComplete,
              publication.candidate.purpose == purpose,
              publication.candidate.sampling.isResolvedForMaterialProgram else {
            throw failure(.textureMetadataIncomplete, slot: slot)
        }
        return (identity, resource)
    }

    private static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: details)
    }
}
