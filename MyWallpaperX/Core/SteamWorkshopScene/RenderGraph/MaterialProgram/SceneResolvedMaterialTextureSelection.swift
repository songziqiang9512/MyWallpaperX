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
            provenance: Program.TextureSelectionProvenance,
            graphInputSourceFact:
                SceneResolvedMaterialGraphInputSourceSlotFact?
        )
        case internalDefault(String)
    }

    static func resolve(
        _ input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        reachableSamplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>],
        channelUses: [Int: ChannelUse],
        allowPresenceIndependentDefaults: Bool,
        restrictToSamplerSlots: Bool = false,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) throws -> [Entry] {
        var result = Array(repeating: Entry.absent, count: 8)
        for slot in input.template.textureSlots.compactMap({ $0 })
        where !restrictToSamplerSlots || samplers[slot.index] != nil {
            let sampler = samplers[slot.index]
            let reachable = reachableSamplers[slot.index] ?? []
            // An authored binding that no launch-envelope variant can read is
            // loss-preserving provenance, not a frame selection candidate.
            // Current or potentially reachable samplers still participate in
            // the same readiness, format, purpose and publication hard gates.
            guard sampler != nil || !reachable.isEmpty else { continue }
            for ordinal in slot.candidates.indices.reversed() {
                let candidate = slot.candidates[ordinal]
                let terminalGraphOverride = ordinal == slot.candidates.index(
                    before: slot.candidates.endIndex
                ) && candidate.provenance == .explicitBinding && {
                    if case .graph = candidate.reference { return true }
                    return false
                }()
                let purpose = Resolver.selectionPurpose(
                    in: slot,
                    candidateOrdinal: ordinal,
                    activeSampler: sampler,
                    reachableSamplers: reachable,
                    channelUse: channelUses[slot.index],
                    input: input
                )
                guard let selection = try referenceSelection(
                    candidate.reference,
                    purpose: purpose,
                    provenance: .authored(candidate.provenance),
                    input: input,
                    preserveAbsentOverride: terminalGraphOverride
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
        try selectGraphInputs(
            into: &result,
            input: input,
            samplers: samplers,
            graphInputSourceSlotFacts: graphInputSourceSlotFacts
        )
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
            case let .internalTarget(name):
                guard let reference = Resolver.sceneBackgroundDefault(
                    template: input.template,
                    sampler: sampler,
                    slot: slot
                ) else {
                    result[slot] = .internalDefault(name)
                    continue
                }
                if let selection = try referenceSelection(
                    reference,
                    purpose: sampler.purpose(for: reference),
                    provenance: .shaderDefault,
                    input: input
                ) {
                    result[slot] = selection
                }
            case nil: break
            }
        }
    }

    private static func selectGraphInputs(
        into result: inout [Entry],
        input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]
    ) throws {
        let facts = graphInputSourceSlotFacts.isEmpty
            ? SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
                template: input.template,
                samplers: samplers,
                inputIdentity: input.implicitFramebufferIdentity
            ) : graphInputSourceSlotFacts
        for (slot, fact) in facts {
            guard result.indices.contains(slot),
                  let sampler = samplers[slot],
                  fact.slot == slot,
                  fact.inputIdentity == input.implicitFramebufferIdentity else {
                throw failure(.textureReferenceInvalid, slot: slot)
            }
            guard case .absent = result[slot] else { continue }
            let reference = Template.TextureReference.graph(fact.inputIdentity)
            if let selection = try referenceSelection(
                reference,
                purpose: sampler.purpose(for: reference),
                provenance: fact.selectionProvenance,
                input: input,
                graphInputSourceFact: fact
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
        input: SceneResolvedMaterialFinalizationInput,
        graphInputSourceFact:
            SceneResolvedMaterialGraphInputSourceSlotFact? = nil,
        preserveAbsentOverride: Bool = false
    ) throws -> Entry? {
        guard let purpose else {
            if case let .graph(identity) = reference {
                guard case .absent? = input.textureSnapshot.lookup(.graph(identity))
                else {
                    return .reference(
                        reference,
                        purpose: nil,
                        provenance: provenance,
                        graphInputSourceFact: graphInputSourceFact
                    )
                }
                return preserveAbsentOverride ? .reference(
                    reference,
                    purpose: nil,
                    provenance: provenance,
                    graphInputSourceFact: graphInputSourceFact
                ) : nil
            }
            return .reference(
                reference,
                purpose: nil,
                provenance: provenance,
                graphInputSourceFact: graphInputSourceFact
            )
        }
        let identity = try Resolver.runtimeIdentity(reference, purpose: purpose)
        guard case .absent? = input.textureSnapshot.lookup(identity) else {
            return .reference(
                reference,
                purpose: purpose,
                provenance: provenance,
                graphInputSourceFact: graphInputSourceFact
            )
        }
        return preserveAbsentOverride ? .reference(
            reference,
            purpose: purpose,
            provenance: provenance,
            graphInputSourceFact: graphInputSourceFact
        ) : nil
    }

    private static func failure(
        _ code: Failure.Code,
        slot: Int? = nil
    ) -> Failure {
        .init(phase: .texture, code: code, slot: slot)
    }
}
