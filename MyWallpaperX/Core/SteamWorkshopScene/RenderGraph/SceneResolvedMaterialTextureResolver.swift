import Foundation

/// Resolves authored and shader-default texture references against one frame
/// snapshot before any Program can enter GPU admission.
nonisolated enum SceneResolvedMaterialTextureResolver {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    struct Resolution {
        let prepared: SceneShaderPreparedProgram
        let frontend: SceneAuthoredShaderProgram
        let slots: [Program.TextureSlot?]
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

    private struct ShaderResolution {
        let prepared: SceneShaderPreparedProgram
        let frontend: SceneAuthoredShaderProgram
        let selections: [Selection]
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput
    ) throws -> Resolution {
        let shader = try resolveShader(input)
        return .init(
            prepared: shader.prepared,
            frontend: shader.frontend,
            slots: try textureSlots(input, shader: shader)
        )
    }

    private static func resolveShader(
        _ input: SceneResolvedMaterialFinalizationInput
    ) throws -> ShaderResolution {
        let seed: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            seed = try SceneResolvedMaterialShaderSchema.unconditionalSamplers(
                input.template
            )
        } catch {
            throw failure(.activeSamplerSchemaInvalid)
        }
        var selections = try textureSelections(input, samplers: seed)
        var seen: Set<[Selection]> = []
        for _ in 0 ..< 8 {
            guard seen.insert(selections).inserted else {
                throw failure(
                    .shaderPreparationFailed,
                    phase: .preparation,
                    details: ["texture-schema-cycle"]
                )
            }
            let prepared = try prepare(
                input.template,
                readiness: try textureReadiness(input, selections: selections)
            )
            let frontend = try compileFrontend(prepared)
            let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
            do {
                samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
            } catch {
                throw failure(.activeSamplerSchemaInvalid)
            }
            let next = try textureSelections(input, samplers: samplers)
            if next == selections {
                return .init(
                    prepared: prepared,
                    frontend: frontend,
                    selections: selections,
                    samplers: samplers
                )
            }
            selections = next
        }
        throw failure(
            .shaderPreparationFailed,
            phase: .preparation,
            details: ["texture-schema-budget"]
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

    private static func textureReadiness(
        _ input: SceneResolvedMaterialFinalizationInput,
        selections: [Selection]
    ) throws -> [Int: Bool] {
        var readiness: [Int: Bool] = [:]
        for (slot, selection) in selections.enumerated() {
            switch selection {
            case .absent:
                readiness[slot] = false
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
                readiness[slot] = true
            }
        }
        return readiness
    }

    private static func prepare(
        _ template: Template,
        readiness: [Int: Bool]
    ) throws -> SceneShaderPreparedProgram {
        switch SceneAuthoredShaderExecutionPlanner.prepareShaderStages(
            contract: template.shaderContract,
            combos: template.comboValues,
            textureReadiness: readiness
        ) {
        case let .accepted(prepared):
            return prepared
        case let .rejected(rejection):
            throw failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: [rejection.phase.rawValue, rejection.code.rawValue]
                    + rejection.details
            )
        case .notApplicable:
            throw failure(.identityInvariant, phase: .invariant)
        }
    }

    private static func compileFrontend(
        _ prepared: SceneShaderPreparedProgram
    ) throws -> SceneAuthoredShaderProgram {
        let result = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard result.diagnostics.isEmpty, let program = result.program else {
            throw failure(
                .shaderFrontendFailed,
                phase: .frontend,
                details: result.diagnostics.map { $0.code.rawValue }
            )
        }
        return program
    }

    private static func textureSlots(
        _ input: SceneResolvedMaterialFinalizationInput,
        shader: ShaderResolution
    ) throws -> [Program.TextureSlot?] {
        let bindingSlots = shader.frontend.textureBindings.map(\.slot)
        guard Set(bindingSlots).count == bindingSlots.count else {
            throw failure(.activeSamplerSchemaInvalid)
        }
        var result = Array<Program.TextureSlot?>(repeating: nil, count: 8)
        for binding in shader.frontend.textureBindings {
            guard result.indices.contains(binding.slot),
                  let sampler = shader.samplers[binding.slot],
                  sampler.name == binding.name else {
                throw failure(.activeSamplerSchemaInvalid, slot: binding.slot)
            }
            guard case let .reference(
                reference,
                selectedPurpose,
                provenance
            ) =
                    shader.selections[binding.slot] else {
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
