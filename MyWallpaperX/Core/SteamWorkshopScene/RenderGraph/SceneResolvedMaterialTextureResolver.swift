import Foundation

/// Resolves authored and shader-default texture references against one frame
/// snapshot before any Program can enter GPU admission.
nonisolated enum SceneResolvedMaterialTextureResolver {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    struct Resolution {
        let variant: SceneResolvedMaterialCompiledVariant
        let slots: [Program.TextureSlot?]

        var prepared: SceneShaderPreparedProgram { variant.preparedShader }
        var frontend: SceneAuthoredShaderProgram { variant.frontendProgram }
    }

    private enum Selection: Hashable {
        case absent
        case reference(
            Template.TextureReference,
            purpose: SceneTextureLoadPurpose?,
            provenance: Program.TextureSelectionProvenance
        )
        case internalDefault(String)
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput
    ) throws -> Resolution {
        guard let cache = SceneResolvedMaterialVariantCache(
            template: input.template,
            maximumVariantCount: 8
        ) else { throw failure(.activeSamplerSchemaInvalid) }
        switch cache.resolve(input) {
        case let .success(variant):
            return try resolve(input, variant: variant)
        case let .failure(error):
            throw error
        }
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant
    ) throws -> Resolution {
        guard try readinessMask(input, samplers: variant.activeSamplers)
                == variant.readinessMask else {
            throw failure(.identityInvariant, phase: .invariant)
        }
        return .init(
            variant: variant,
            slots: try textureSlots(input, variant: variant)
        )
    }

    private static func textureSelections(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) throws -> [Selection] {
        var result = Array(repeating: Selection.absent, count: 8)
        for slot in input.template.textureSlots.compactMap({ $0 }) {
            let sampler = samplers[slot.index]
            for candidate in slot.candidates.reversed() {
                let purpose = sampler?.purpose(for: candidate.reference)
                guard let selection = try referenceSelection(
                    candidate.reference,
                    purpose: purpose,
                    provenance: .authored(candidate.provenance),
                    input: input
                ) else {
                    continue
                }
                result[slot.index] = selection
                break
            }
        }
        for (slot, sampler) in samplers {
            guard case .absent = result[slot] else { continue }
            switch sampler.defaultTexture {
            case let .asset(path):
                let reference = Template.TextureReference.asset(path)
                if let selection = try referenceSelection(
                    reference,
                    purpose: sampler.purpose(for: reference),
                    provenance: .shaderDefault,
                    input: input
                ) {
                    result[slot] = selection
                }
            case let .internalTarget(name): result[slot] = .internalDefault(name)
            case nil: break
            }
        }
        for (slot, sampler) in samplers {
            guard case .absent = result[slot],
                  sampler.materialKey?.caseInsensitiveCompare("framebuffer")
                    == .orderedSame,
                  let identity = input.implicitFramebufferIdentity else {
                continue
            }
            guard identity.kind == .layerSource
                    || identity.kind == .effectOutput,
                  identity.name == nil else {
                throw failure(.textureReferenceInvalid, slot: slot)
            }
            let reference = Template.TextureReference.graph(identity)
            if let selection = try referenceSelection(
                reference,
                purpose: sampler.purpose(for: reference),
                provenance: .implicitFramebuffer,
                input: input
            ) {
                result[slot] = selection
            }
        }
        for slot in SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(template: input.template, samplers: samplers) {
            guard case .absent = result[slot],
                  let identity = input.implicitFramebufferIdentity,
                  identity.kind == .layerSource || identity.kind == .effectOutput,
                  identity.name == nil else {
                throw failure(.textureReferenceInvalid, slot: slot)
            }
            let reference = Template.TextureReference.graph(identity)
            if let selection = try referenceSelection(
                reference,
                purpose: samplers[slot]?.purpose(for: reference),
                provenance: .implicitFramebuffer,
                input: input
            ) {
                result[slot] = selection
            }
        }
        return result
    }

    /// Only a producer's explicit absent fact means that this authored source
    /// was not selected. Missing, pending, unavailable and unproven sources are
    /// failures; they never authorize a lower-precedence candidate.
    private static func referenceSelection(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose?,
        provenance: Program.TextureSelectionProvenance,
        input: SceneResolvedMaterialFinalizationInput
    ) throws -> Selection? {
        guard let purpose else {
            return .reference(
                reference,
                purpose: nil,
                provenance: provenance
            )
        }
        let identity = try runtimeIdentity(reference, purpose: purpose)
        guard case .absent? = input.textureSnapshot.lookup(identity) else {
            return .reference(
                reference,
                purpose: purpose,
                provenance: provenance
            )
        }
        return nil
    }

    static func readinessMask(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) throws -> UInt8 {
        let selections = try textureSelections(input, samplers: samplers)
        var mask: UInt8 = 0
        for (slot, selection) in selections.enumerated() {
            switch selection {
            case .absent: break
            case .internalDefault:
                throw failure(.textureBindingInvalid, slot: slot)
            case let .reference(reference, purpose, _):
                guard let purpose else {
                    throw failure(.texturePurposeUnproven, slot: slot)
                }
                _ = try readyResource(
                    input,
                    reference: reference,
                    purpose: purpose,
                    slot: slot
                )
                mask |= UInt8(1) << UInt8(slot)
            }
        }
        return mask
    }

    private static func textureSlots(
        _ input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant
    ) throws -> [Program.TextureSlot?] {
        let selections = try textureSelections(
            input,
            samplers: variant.activeSamplers
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
            guard let purpose = sampler.purpose(for: reference) else {
                throw failure(.texturePurposeUnproven, slot: binding.slot)
            }
            guard selectedPurpose == purpose else {
                throw failure(.activeSamplerSchemaInvalid, slot: binding.slot)
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

    private static func runtimeIdentity(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) throws -> SceneFrameTextureIdentity {
        switch reference {
        case let .asset(path):
            return .asset(.init(path: path, purpose: purpose))
        case let .userProperty(request):
            guard let identity = SceneUserPropertyTextureIdentity(
                propertyKey: request.key,
                purpose: purpose
            ) else { throw failure(.identityInvariant, phase: .invariant) }
            return .materialUserProperty(identity)
        case let .provider(.system(name)):
            return .system(name)
        case let .graph(graph):
            return .graph(graph)
        }
    }

    private typealias ResolvedResource = (
        identity: SceneFrameTextureIdentity,
        resource: SceneFrameTextureResource
    )

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
