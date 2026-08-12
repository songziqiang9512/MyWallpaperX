import Foundation

/// Selects authored, default and graph texture sources for one immutable frame
/// before the resolver validates their publications and creates Program slots.
nonisolated enum SceneResolvedMaterialTextureSelection {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Program = SceneResolvedMaterialProgram
    typealias Resolver = SceneResolvedMaterialTextureResolver
    typealias Template = SceneResolvedMaterialTemplate
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    enum Entry: Hashable {
        case absent
        case reference(
            Template.TextureReference,
            purpose: SceneTextureLoadPurpose?,
            provenance: Program.TextureSelectionProvenance
        )
        case internalDefault(String)
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        channelUses: [Int: ChannelUse],
        allowPresenceIndependentDefaults: Bool
    ) throws -> [Entry] {
        var result = Array(repeating: Entry.absent, count: 8)
        for slot in input.template.textureSlots.compactMap({ $0 }) {
            let sampler = samplers[slot.index]
            for candidate in slot.candidates.reversed() {
                let purpose = Resolver.selectionPurpose(
                    candidate.reference,
                    activeSampler: sampler,
                    reachableSamplers: reachableSamplers[slot.index] ?? [],
                    channelUse: channelUses[slot.index],
                    input: input
                )
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
        try selectDefaults(
            into: &result,
            input: input,
            samplers: samplers,
            allowPresenceIndependentDefaults: allowPresenceIndependentDefaults
        )
        try selectGraphInputs(into: &result, input: input, samplers: samplers)
        return result
    }

    private static func selectDefaults(
        into result: inout [Entry],
        input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        allowPresenceIndependentDefaults: Bool
    ) throws {
        for (slot, sampler) in samplers {
            guard case .absent = result[slot] else { continue }
            if sampler.readinessCombo != nil,
               (!allowPresenceIndependentDefaults
                   || Resolver.presenceIndependentDefault(
                       template: input.template,
                       sampler: sampler,
                       slot: slot
                   ) == nil) {
                continue
            }
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
    }

    private static func selectGraphInputs(
        into result: inout [Entry],
        input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) throws {
        for (slot, sampler) in samplers {
            guard case .absent = result[slot],
                  sampler.usesGraphInputMaterialAlias,
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
                provenance: sampler.materialKey?.caseInsensitiveCompare(
                    "previous"
                ) == .orderedSame ? .materialGraphInputAlias : .implicitFramebuffer,
                input: input
            ) {
                result[slot] = selection
            }
        }
        for slot in SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: input.template,
            samplers: samplers
        ) {
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
    }

    /// Only a producer's explicit absent fact means that this authored source
    /// was not selected. Missing, pending, unavailable and unproven sources are
    /// failures; they never authorize a lower-precedence candidate.
    private static func referenceSelection(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose?,
        provenance: Program.TextureSelectionProvenance,
        input: SceneResolvedMaterialFinalizationInput
    ) throws -> Entry? {
        guard let purpose else {
            if case let .graph(identity) = reference {
                guard case .absent? = input.textureSnapshot.lookup(.graph(identity))
                else {
                    return .reference(
                        reference,
                        purpose: nil,
                        provenance: provenance
                    )
                }
                return nil
            }
            return .reference(reference, purpose: nil, provenance: provenance)
        }
        let identity = try Resolver.runtimeIdentity(reference, purpose: purpose)
        guard case .absent? = input.textureSnapshot.lookup(identity) else {
            return .reference(
                reference,
                purpose: purpose,
                provenance: provenance
            )
        }
        return nil
    }

    private static func failure(
        _ code: Failure.Code,
        slot: Int? = nil
    ) -> Failure {
        .init(phase: .texture, code: code, slot: slot)
    }
}
