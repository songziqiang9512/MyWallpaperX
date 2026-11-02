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
        reachableTexturePurposes: [Int: [SceneTextureLoadPurpose?]],
        channelUses: [Int: ChannelUse],
        allowPresenceIndependentDefaults: Bool,
        restrictToSamplerSlots: Bool = false,
        textureSelectionFacts: SceneResolvedMaterialCompiledVariant.TextureSelectionFacts,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]
    ) throws -> [Entry] {
        var result = Array(repeating: Entry.absent, count: 8)
        for slot in input.template.textureSlots.compactMap({ $0 })
        where !restrictToSamplerSlots || samplers[slot.index] != nil {
            let sampler = samplers[slot.index]
            let purposes = sampler == nil
                ? reachableTexturePurposes[slot.index]
                : textureSelectionFacts.candidatePurposes[slot.index]
            // An authored binding that no launch-envelope variant can read is
            // loss-preserving provenance, not a frame selection candidate.
            // Current or potentially reachable samplers still participate in
            // the same readiness, format, purpose and publication hard gates.
            guard sampler != nil || purposes != nil else { continue }
            for (ordinal, prepared) in textureSelectionFacts.candidates[slot.index, default: []]
                .enumerated().reversed() {
                let candidate = slot.candidates[ordinal]
                let sourceFact = prepared.graphInputSourceFact.flatMap { fact in
                    fact.inputIdentity.layerID == input.layerID ? fact : nil
                }
                let reference = sourceFact.map { Template.TextureReference.graph($0.inputIdentity) }
                    ?? candidate.reference
                let purpose = Resolver.selectionPurpose(
                    reference: reference,
                    declaredPurpose: purposes?[ordinal],
                    activeSampler: sampler,
                    channelUse: channelUses[slot.index],
                    input: input
                )
                guard let selection = try referenceSelection(
                    reference,
                    purpose: purpose,
                    provenance: .authored(candidate.provenance),
                    input: input,
                    graphInputSourceFact: sourceFact,
                    preserveAbsentOverride: prepared.preservesAbsentOverride,
                    deferUnreadyOptionalPromotion: prepared.defersUnreadyOptionalPromotion
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
            textureSelectionFacts: textureSelectionFacts,
            allowPresenceIndependentDefaults: allowPresenceIndependentDefaults
        )
        try selectGraphInputs(
            into: &result,
            input: input,
            samplers: samplers,
            textureSelectionFacts: textureSelectionFacts,
            graphInputSourceSlotFacts: graphInputSourceSlotFacts
        )
        return result
    }

    private static func selectDefaults(
        into result: inout [Entry],
        input: SceneResolvedMaterialFinalizationInput,
        textureSelectionFacts: SceneResolvedMaterialCompiledVariant.TextureSelectionFacts,
        allowPresenceIndependentDefaults: Bool
    ) throws {
        for (slot, source) in textureSelectionFacts.defaults {
            guard case .absent = result[slot] else { continue }
            switch source {
            case let .reference(prepared):
                guard allowPresenceIndependentDefaults
                    || !prepared.requiresPresenceIndependentAllowance else { continue }
                if let selection = try referenceSelection(
                    prepared.reference,
                    purpose: prepared.purpose,
                    provenance: .shaderDefault,
                    input: input,
                    graphInputSourceFact: prepared.graphInputSourceFact
                ) {
                    result[slot] = selection
                } else if let noiseFallback = prepared.noiseFallback {
                    // A registered stock noise asset the sample does not ship
                    // resolves as the deterministic system substitute; a pkg
                    // asset always wins above (user-directed 2026-09-26).
                    if let selection = try referenceSelection(
                        noiseFallback,
                        purpose: .noise,
                        provenance: .shaderDefault,
                        input: input
                    ) {
                        result[slot] = selection
                    }
                }
            case let .internalTarget(name):
                result[slot] = .internalDefault(name)
            }
        }
    }

    private static func selectGraphInputs(
        into result: inout [Entry],
        input: SceneResolvedMaterialFinalizationInput,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        textureSelectionFacts: SceneResolvedMaterialCompiledVariant.TextureSelectionFacts,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]
    ) throws {
        for (slot, fact) in graphInputSourceSlotFacts {
            guard result.indices.contains(slot),
                  samplers[slot] != nil,
                  fact.slot == slot,
                  fact.inputIdentity == input.implicitFramebufferIdentity else {
                throw failure(.textureReferenceInvalid, slot: slot)
            }
            guard case .absent = result[slot] else { continue }
            let reference = Template.TextureReference.graph(fact.inputIdentity)
            if let selection = try referenceSelection(
                reference,
                purpose: textureSelectionFacts.graphInputPurposes[slot],
                provenance: fact.selectionProvenance,
                input: input,
                graphInputSourceFact: fact
            ) {
                result[slot] = selection
            }
        }
    }

    /// General authored candidates expose their lower-precedence source only
    /// after an explicit absent fact. The exact mixed named/optional envelope
    /// additionally defers ownership while its optional input is pending or
    /// unavailable, because that input has not published a usable replacement.
    /// Missing identities and incomplete publications remain failures, as do
    /// all unready candidates outside that proved envelope.
    private static func referenceSelection(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose?,
        provenance: Program.TextureSelectionProvenance,
        input: SceneResolvedMaterialFinalizationInput,
        graphInputSourceFact:
            SceneResolvedMaterialGraphInputSourceSlotFact? = nil,
        preserveAbsentOverride: Bool = false,
        deferUnreadyOptionalPromotion: Bool = false
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
        let status = input.textureSnapshot.lookup(identity)
        if deferUnreadyOptionalPromotion {
            switch status {
            case .absent?, .pending?, .unavailable?: return nil
            case .ready?, .incomplete?, nil: break
            }
        }
        guard case .absent? = status else {
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
