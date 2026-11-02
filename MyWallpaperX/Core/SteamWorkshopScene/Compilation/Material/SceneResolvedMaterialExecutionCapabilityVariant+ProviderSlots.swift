import Foundation

/// Exact authored shape whose high-precedence optional input takes ownership
/// only after it has a complete publication. Until then the lower same-frame
/// compositor color publication remains selected. The two candidates share one
/// sampler slot but require different Program input ABI. Keeping this
/// structural and name-independent prevents a sample/effect dispatch while
/// leaving all unproved mixed chains fail-closed.
nonisolated enum SceneResolvedMaterialMixedProviderSlotFact {
    typealias Template = SceneResolvedMaterialTemplate
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler

    static func resolve(
        in textureSlot: Template.TextureSlot,
        sampler: Sampler
    ) -> SceneResolvedMaterialCompiledVariant.MixedProviderSlot? {
        guard textureSlot.index == sampler.slot,
              textureSlot.candidates.count == 2,
              sampler.mode == .rgbMask,
              sampler.sourceProvenPurpose == nil
                || sampler.sourceProvenPurpose == .preservedChannels,
              defaultTextureIsNonOwning(sampler.defaultTexture),
              case let .provider(.namedLayerTarget(reference)) =
                textureSlot.candidates[0].reference,
              reference.variant == .primary,
              textureSlot.candidates[0].provenance != .explicitBinding,
              textureSlot.candidates[1].provenance == .userTexture,
              let optionalInput = SceneResolvedMaterialCompiledVariant.MixedProviderSlot.OptionalInput(
                  textureSlot.candidates[1].reference
              ),
              sampler.purpose(for: textureSlot.candidates[1].reference)
                == .preservedChannels else { return nil }
        return .init(
            slot: textureSlot.index,
            lowerNamedReference: reference,
            optionalInput: optionalInput
        )
    }

    /// An authored asset default is only a declaration fallback. The exact
    /// system/named candidate chain still owns frame selection, and any
    /// pending/unavailable named target remains terminal rather than silently
    /// substituting this asset. Internal targets have independent lifecycle
    /// and are not part of this representation-switch contract.
    private static func defaultTextureIsNonOwning(
        _ reference: SceneResolvedMaterialShaderSchema.DefaultTexture?
    ) -> Bool {
        switch reference {
        case nil, .asset:
            true
        case .internalTarget:
            false
        }
    }

}

nonisolated extension SceneResolvedMaterialVariantCache {
    static func prepareTextureSelectionFacts(
        in template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphInputSourceSlotFacts: [Int: SceneResolvedMaterialGraphInputSourceSlotFact]
    ) -> Variant.TextureSelectionFacts {
        let mixed = mixedProviderSlotFacts(in: template, samplers: samplers)
        var purposes: [Int: [SceneTextureLoadPurpose?]] = [:]
        var candidates: [Int: [Variant.TextureSelectionFacts.Candidate]] = [:]
        for slot in template.textureSlots.compactMap({ $0 }) {
            if let sampler = samplers[slot.index] {
                purposes[slot.index] = slot.candidates.indices.map {
                    SceneResolvedMaterialTextureSlotPurpose.fact(
                        in: slot, candidateOrdinal: $0, sampler: sampler,
                        mixedProvider: mixed[slot.index]
                    )?.purpose
                }
            }
            candidates[slot.index] = slot.candidates.indices.map { ordinal in
                let candidate = slot.candidates[ordinal]
                var sourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
                if let input = implicitFramebufferIdentity,
                   let identity = SceneResolvedMaterialShaderSchema.sameLayerCompositeInput(
                       candidate.reference, template: template, inputIdentity: input,
                       consumerLayerID: input.layerID
                   ) {
                    if let fact = graphInputSourceSlotFacts[slot.index],
                       fact.inputIdentity == identity,
                       SceneResolvedMaterialShaderSchema.sameLayerCompositeCandidate(
                           slot, inputIdentity: identity
                       ) {
                        sourceFact = .init(
                            slot: fact.slot,
                            inputIdentity: identity,
                            provenance: fact.provenance,
                            selectionProvenance: .authored(candidate.provenance)
                        )
                    } else if candidate.reference == mixed[slot.index].map({
                        .provider(.namedLayerTarget($0.lowerNamedReference))
                    }) {
                        sourceFact = .init(
                            slot: slot.index,
                            inputIdentity: identity,
                            provenance: .sameLayerCompositeDefault,
                            selectionProvenance: .authored(candidate.provenance)
                        )
                    }
                }
                let terminalOverride: Bool
                if case .graph = candidate.reference {
                    terminalOverride = ordinal == slot.candidates.count - 1
                        && candidate.provenance == .explicitBinding
                } else {
                    terminalOverride = false
                }
                return .init(
                    graphInputSourceFact: sourceFact,
                    preservesAbsentOverride: terminalOverride,
                    defersUnreadyOptionalPromotion:
                        mixed[slot.index]?.optionalInput.matches(candidate.reference) == true
                )
            }
        }
        var defaults: [Int: Variant.TextureSelectionFacts.DefaultSource] = [:]
        for (slot, sampler) in samplers {
            if sampler.readinessCombo != nil,
               SceneResolvedMaterialTextureResolver.presenceIndependentDefault(
                   template: template, sampler: sampler, slot: slot
               ) == nil { continue }
            let reference: Template.TextureReference
            var sourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
            let noiseFallback: Template.TextureReference?
            switch sampler.defaultTexture {
            case let .asset(path):
                reference = .asset(path)
                noiseFallback = SceneStockTextureSemanticRegistry.canSubstituteNoise(
                    path, purpose: sampler.purpose(for: reference)
                ) ? .provider(.system(path.value)) : nil
            case let .internalTarget(target):
                guard let resolved = SceneResolvedMaterialTextureResolver.renderTargetDefault(
                    template: template, sampler: sampler, slot: slot,
                    inputIdentity: implicitFramebufferIdentity
                ) else {
                    defaults[slot] = .internalTarget(target.authoredName)
                    continue
                }
                reference = resolved
                noiseFallback = nil
                if case let .graph(identity) = reference {
                    sourceFact = .init(
                        slot: slot,
                        inputIdentity: identity,
                        provenance: .sameLayerCompositeDefault,
                        selectionProvenance: .shaderDefault
                    )
                }
            case nil: continue
            }
            defaults[slot] = .reference(.init(
                reference: reference,
                purpose: sampler.purpose(for: reference),
                graphInputSourceFact: sourceFact,
                noiseFallback: noiseFallback,
                requiresPresenceIndependentAllowance: sampler.readinessCombo != nil
            ))
        }
        let graphPurposes = Dictionary(uniqueKeysWithValues: graphInputSourceSlotFacts.compactMap {
            slot, fact -> (Int, SceneTextureLoadPurpose)? in
            samplers[slot]?.purpose(for: .graph(fact.inputIdentity)).map { (slot, $0) }
        })
        return .init(
            candidatePurposes: purposes,
            candidates: candidates,
            defaults: defaults,
            graphInputPurposes: graphPurposes,
            mixedProviderSlots: mixed,
            regularNamedProviderPurposeSlots: regularNamedProviderPurposeSlots(in: template, samplers: samplers)
        )
    }

    static func unsupportedInternalTarget(
        in samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        inputIdentity: Graph.TextureIdentity?,
        readinessMask: UInt8
    ) -> (slot: Int, name: String)? {
        for (slot, sampler) in samplers.sorted(by: { $0.key < $1.key }) {
            guard case let .internalTarget(name)? = sampler.defaultTexture else {
                continue
            }
            // launchReadinessProjection derives this bit from the authored
            // candidate chain. Frame selection revalidates the selected
            // publication before binding; an idle default grants no resource.
            if readinessMask & (UInt8(1) << UInt8(slot)) != 0,
               template.textureSlots[slot]?.candidates.isEmpty == false { continue }
            guard SceneResolvedMaterialTextureResolver.renderTargetDefault(
                template: template, sampler: sampler, slot: slot,
                inputIdentity: inputIdentity
            ) != nil else { return (slot, name.authoredName) }
        }
        return nil
    }

    static func mixedProviderSlotFacts(
        in template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> [Int: Variant.MixedProviderSlot] {
        Dictionary(uniqueKeysWithValues: samplers.compactMap { slot, sampler in
            guard template.textureSlots.indices.contains(slot),
                  let textureSlot = template.textureSlots[slot],
                  let fact = SceneResolvedMaterialMixedProviderSlotFact.resolve(
                      in: textureSlot,
                      sampler: sampler
                  ) else { return nil }
            return (slot, fact)
        })
    }

    /// A single foreign named source has no lower-priority representation.
    /// Prepare both publication purposes before frames; self-composite ingress
    /// and candidate fallbacks retain their existing selection contracts.
    static func regularNamedProviderPurposeSlots(
        in template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Set<Int> {
        guard let consumerLayerID = template.effectContext?.key.layerID else { return [] }
        return terminalNamedLayerProviderTextureSlots(
            in: template, activeTextureSlots: Set(samplers.keys)
        ).filter { slot in
            guard let sampler = samplers[slot], sampler.mode == .regular,
                  sampler.defaultTexture == nil,
                  !sampler.usesGraphInputMaterialAlias,
                  let candidates = template.textureSlots[slot]?.candidates,
                  candidates.count == 1,
                  case let .provider(.namedLayerTarget(reference)) =
                    candidates[0].reference else { return false }
            return reference.providerLayerID != consumerLayerID
        }
    }

    static func hasExternalProviderTexture(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Bool {
        !externalProviderTextureSlots(
            in: template,
            activeTextureSlots: activeTextureSlots
        ).isEmpty
    }

    static func externalProviderTextureSlots(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Set<Int> {
        Set(template.textureSlots.enumerated().compactMap { index, slot in
            guard activeTextureSlots?.contains(index) != false,
                  let slot else { return nil }
            // Candidate order is low to high precedence. A terminal graph
            // reference is the immutable selected override; earlier provider
            // entries are provenance and cannot become runtime fallbacks.
            if case .graph? = slot.candidates.last?.reference {
                return nil
            }
            return slot.candidates.contains { candidate in
                if case .provider = candidate.reference { return true }
                return false
            } ? index : nil
        })
    }

    static func terminalNamedLayerProviderTextureSlots(
        in template: Template,
        activeTextureSlots: Set<Int>? = nil
    ) -> Set<Int> {
        Set(template.textureSlots.enumerated().compactMap { index, slot in
            guard activeTextureSlots?.contains(index) != false,
                  let selected = slot?.candidates.last,
                  case let .provider(.namedLayerTarget(reference)) =
                    selected.reference,
                  reference.variant == .primary else {
                return nil
            }
            return index
        })
    }
}
