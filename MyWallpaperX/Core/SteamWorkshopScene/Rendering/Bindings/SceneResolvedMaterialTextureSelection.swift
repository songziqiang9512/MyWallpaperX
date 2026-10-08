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
        let graphFacts = graphInputSourceSlotFacts.isEmpty
            ? SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
                template: input.template,
                samplers: samplers,
                inputIdentity: input.implicitFramebufferIdentity
            ) : graphInputSourceSlotFacts
        for slot in input.template.textureSlots.compactMap({ $0 })
        where !restrictToSamplerSlots || samplers[slot.index] != nil {
            let sampler = samplers[slot.index]
            let reachable = reachableSamplers[slot.index] ?? []
            let mixedProviderFact = sampler.flatMap {
                SceneResolvedMaterialMixedProviderSlotFact.resolve(
                    in: slot,
                    sampler: $0
                )
            }
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
                var purpose = Resolver.selectionPurpose(
                    in: slot,
                    candidateOrdinal: ordinal,
                    activeSampler: sampler,
                    reachableSamplers: reachable,
                    channelUse: channelUses[slot.index],
                    input: input
                )
                var reference = candidate.reference
                var sourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
                if let identity = SceneResolvedMaterialShaderSchema.sameLayerCompositeInput(
                    reference, template: input.template,
                    inputIdentity: input.implicitFramebufferIdentity,
                    consumerLayerID: input.layerID
                ) {
                    if let fact = graphFacts[slot.index],
                       fact.inputIdentity == identity,
                       SceneResolvedMaterialShaderSchema.sameLayerCompositeCandidate(
                           slot, inputIdentity: identity
                       ) {
                        reference = .graph(identity)
                        sourceFact = .init(
                            slot: fact.slot, inputIdentity: fact.inputIdentity,
                            provenance: fact.provenance,
                            selectionProvenance: .authored(candidate.provenance)
                        )
                    } else if candidate.reference == mixedProviderFact.map({
                        .provider(.namedLayerTarget($0.lowerNamedReference))
                    }) {
                        // This already-proved optional override keeps its
                        // selected ABI and precedence. Only its lower self
                        // candidate names the existing graph ingress.
                        reference = .graph(identity)
                        sourceFact = .init(
                            slot: slot.index, inputIdentity: identity,
                            provenance: .sameLayerCompositeDefault,
                            selectionProvenance: .authored(candidate.provenance)
                        )
                    }
                    if reference != candidate.reference, let sampler {
                        // The graph atom owns current content and generation;
                        // an old named publication cannot relabel that atom.
                        purpose = SceneResolvedMaterialTextureSlotPurpose.fact(
                            in: slot, candidateOrdinal: ordinal, sampler: sampler
                        )?.purpose
                    }
                }
                guard let selection = try referenceSelection(
                    reference,
                    purpose: purpose,
                    provenance: .authored(candidate.provenance),
                    input: input,
                    graphInputSourceFact: sourceFact,
                    preserveAbsentOverride: terminalGraphOverride,
                    deferUnreadyOptionalPromotion:
                        mixedProviderFact?.optionalInput.matches(
                            candidate.reference
                        ) == true
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
            graphInputSourceSlotFacts: graphFacts
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
                } else if SceneStockTextureSemanticRegistry.canSubstituteNoise(
                    path, purpose: sampler.purpose(for: reference)
                ) {
                    // A registered stock noise asset the sample does not ship
                    // resolves as the deterministic system substitute; a pkg
                    // asset always wins above (user-directed 2026-09-26).
                    let stockReference = Template.TextureReference
                        .provider(.system(path.value))
                    if let selection = try referenceSelection(
                        stockReference,
                        purpose: .noise,
                        provenance: .shaderDefault,
                        input: input
                    ) {
                        result[slot] = selection
                    }
                }
            case let .internalTarget(target):
                guard let reference = Resolver.renderTargetDefault(
                    template: input.template, sampler: sampler, slot: slot,
                    inputIdentity: input.implicitFramebufferIdentity
                ) else {
                    result[slot] = .internalDefault(target.authoredName)
                    continue
                }
                let sourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
                if case let .graph(identity) = reference {
                    sourceFact = .init(slot: slot, inputIdentity: identity,
                        provenance: .sameLayerCompositeDefault, selectionProvenance: .shaderDefault)
                } else { sourceFact = nil }
                if let selection = try referenceSelection(
                    reference, purpose: sampler.purpose(for: reference),
                    provenance: .shaderDefault, input: input, graphInputSourceFact: sourceFact
                ) { result[slot] = selection }
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
        for (slot, fact) in graphInputSourceSlotFacts {
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
