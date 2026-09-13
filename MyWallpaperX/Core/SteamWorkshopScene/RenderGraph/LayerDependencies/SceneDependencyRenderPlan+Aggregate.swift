import Foundation

extension SceneDependencyRenderPlan {
    /// A lossless, frame-scoped description of a composition consumer that
    /// names more than one external primary provider.  This is intentionally
    /// separate from `Binding`: the legacy binding owns exactly one provider
    /// and must never project an aggregate onto its first reference.
    nonisolated struct MultiProviderAggregate: Hashable {
        let consumerLayerID: Int
        let bindings: [Binding]
        /// The exact layer.effects -> pass -> slot order in which the
        /// authored graph names its external providers. Effect identifiers
        /// are descriptive strings and are not an ordering authority.
        let authoredSlotOrder: [SceneEffectPassSlot]

        init(
            consumerLayerID: Int,
            bindings: [Binding],
            authoredSlotOrder: [SceneEffectPassSlot]
        ) {
            self.consumerLayerID = consumerLayerID
            self.bindings = bindings
            self.authoredSlotOrder = authoredSlotOrder
        }

        /// The aggregate vector has one binding per authored external slot.
        /// Keep this ordering canonical at the plan boundary so every later
        /// reservation/execute seam can reject a reordered or duplicated
        /// provider atom instead of relying on a set comparison.
        var orderedBindings: [Binding] {
            guard authoredSlotOrder.count == bindings.count else { return [] }
            var bindingsBySlot: [SceneEffectPassSlot: Binding] = [:]
            for binding in bindings {
                guard bindingsBySlot.updateValue(
                    binding,
                    forKey: binding.slot
                ) == nil else {
                    return []
                }
            }
            guard bindingsBySlot.count == authoredSlotOrder.count else {
                return []
            }
            return authoredSlotOrder.compactMap { bindingsBySlot[$0] }
        }

        /// Runtime aggregate consumers only support the exact image-primary
        /// binding shape emitted by `multiProviderAggregate`. Keeping this
        /// invariant on the value itself lets reservation and execution paths
        /// share one fail-closed check without reinterpreting the descriptor.
        var hasStrictBindingVector: Bool {
            guard bindings.count >= 2,
                  authoredSlotOrder.count == bindings.count,
                  Set(authoredSlotOrder).count == authoredSlotOrder.count,
                  Set(authoredSlotOrder) == Set(bindings.map(\.slot)),
                  bindings == orderedBindings,
                  Set(bindings.map(\.providerLayerID)).count > 1 else {
                return false
            }
            return bindings.allSatisfy { binding in
                binding.consumerLayerID == consumerLayerID
                    && binding.providerLayerID != consumerLayerID
                    && binding.referenceSlots == [binding.slot]
                    && binding.kind == .imageLayerBlend
                    && binding.blendMode == 0
                    && binding.requiresResolvedMaterialProgram
            }
        }

        var providerLayerIDs: Set<Int> {
            Set(bindings.map(\.providerLayerID))
        }

        var referenceSlots: [SceneEffectPassSlot] {
            authoredSlotOrder
        }

        /// Pure admission check shared by runtime seams and deterministic
        /// fixtures. It requires the whole provider/slot vector exactly once
        /// and in the canonical authored slot order; a set comparison would
        /// allow a caller to bind the right providers to the wrong slots.
        func admits(_ references: [Reference]) -> Bool {
            guard hasStrictBindingVector else { return false }
            let expected = orderedBindings.map {
                Reference(
                    consumerLayerID: consumerLayerID,
                    providerLayerID: $0.providerLayerID,
                    slot: $0.slot,
                    variant: .primary
                )
            }
            return references == expected
        }
    }

    nonisolated func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        staticLayerSourcePassthroughBlockedLayerIDs.contains(layerID)
    }

    nonisolated func aggregateBindingIsPlanned(
        _ binding: Binding
    ) -> Bool {
        guard let aggregate = multiProviderAggregatesByConsumerLayerID[
            binding.consumerLayerID
        ], aggregate.hasStrictBindingVector else { return false }
        return aggregate.bindings.contains(binding)
    }

    /// Restricts prepared graph work to roots that are visible in the current
    /// committed frame plus the effectful provider closure they actually use.
    /// Static image providers are captured through this plan's named target
    /// path and therefore never acquire a graph execution identity here.
    nonisolated func resolvedMaterialExecutionLayerIDs(
        visibleRootLayerIDs: Set<Int>,
        availableExecutionLayerIDs: Set<Int>
    ) -> Set<Int> {
        var reachable = visibleRootLayerIDs.intersection(
            availableExecutionLayerIDs
        )
        var changed = true
        while changed {
            changed = false
            for binding in bindingsByConsumerLayerID.values
            where reachable.contains(binding.consumerLayerID)
                && requiredGraphOutputProviderLayerIDs.contains(
                    binding.providerLayerID
                )
                && availableExecutionLayerIDs.contains(
                    binding.providerLayerID
                )
            {
                changed = reachable.insert(binding.providerLayerID).inserted
                    || changed
            }
            for aggregate in multiProviderAggregatesByConsumerLayerID.values
            where reachable.contains(aggregate.consumerLayerID) {
                for providerID in aggregate.providerLayerIDs
                where requiredGraphOutputProviderLayerIDs.contains(providerID)
                    && availableExecutionLayerIDs.contains(providerID) {
                    changed = reachable.insert(providerID).inserted
                        || changed
                }
            }
        }
        return reachable
    }
    /// A forward graph runs before any authored compositor layer. It may use
    /// its own layer source, static assets, frame inputs and one exact primary
    /// named input that the same dependency plan validates and schedules
    /// first. The main target, secondary targets and undeclared named inputs
    /// remain authored-order-dependent and are rejected.
    nonisolated static func providerGraphIsAuthoredOrderIndependent(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        let references = SceneDependencyGraphAnalysis.references(in: [layer])
        guard let activeDependencies = activeDependencyProviderLayerIDs(
            layer: layer,
            references: references
        ) else { return false }
        if activeDependencies.isEmpty {
            guard references.isEmpty else { return false }
        } else {
            guard activeDependencies.count == 1,
                  let dependencyLayerID = activeDependencies.first,
                  references.count == 1,
                  let reference = references.first,
                  reference.consumerLayerID == layer.id,
                  reference.providerLayerID == dependencyLayerID,
                  reference.variant == .primary else { return false }
        }
        return layer.effects.filter { $0.visible != false }.allSatisfy { effect in
            effect.passes.allSatisfy { pass in
                let authoredPaths = pass.texturePaths
                    + pass.textureSlots.compactMap { $0 }
                return authoredPaths.allSatisfy { path in
                    guard path.caseInsensitiveCompare("_rt_FullFrameBuffer")
                        != .orderedSame else { return false }
                    guard let named = SceneNamedTextureReference.parse(path)
                    else { return true }
                    return activeDependencies == [named.providerLayerID]
                        && named.variant == .primary
                }
            }
        }
    }
    /// Reconstructs the descriptor's authored effect/pass/slot order for the
    /// references that survived visibility and optional-input admission. The
    /// slot identity itself carries no authored ordinal, so effect IDs cannot
    /// safely stand in for this ordering when they are arbitrary strings.
    nonisolated static func authoredReferenceOrder(
        for layer: SceneRenderDescriptor.Layer,
        references: [Reference]
    ) -> [Reference]? {
        var remaining = references
        var ordered: [Reference] = []
        for effect in layer.effects where effect.visible != false {
            for pass in effect.passes {
                for slotIndex in pass.textureSlots.indices {
                    let slot = SceneEffectPassSlot(
                        effectID: effect.id,
                        passIndex: pass.passIndex,
                        slotIndex: slotIndex
                    )
                    let matches = remaining.filter { $0.slot == slot }
                    guard !matches.isEmpty else { continue }
                    ordered.append(contentsOf: matches)
                    remaining.removeAll { $0.slot == slot }
                }
            }
        }
        guard remaining.isEmpty, ordered.count == references.count else {
            return nil
        }
        return ordered
    }

    /// B2 only owns the resource carrier for a narrow, ordinary material
    /// input shape.  The shader/program remains responsible for the visual
    /// semantics, but the dependency plan must prove that each external
    /// reference is one unambiguous primary sampler: pass zero, slot one,
    /// exactly one pass, no user texture override, and no mask/secondary
    /// texture.  This accepts the stock Blend two-slot form and the stock
    /// X-Ray three-slot form (whose trailing slot is an authored hole) while
    /// rejecting arbitrary effect/pass payloads before reservation.
    nonisolated static func aggregateReferenceShapeIsStrict(
        layer: SceneRenderDescriptor.Layer,
        reference: Reference
    ) -> Bool {
        guard reference.consumerLayerID == layer.id,
              reference.variant == .primary,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 1 else { return false }
        let matchingEffects = layer.effects.filter {
            $0.id == reference.slot.effectID && $0.visible != false
        }
        guard matchingEffects.count == 1,
              let effect = matchingEffects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              (pass.textureSlots.count == 2
                  || pass.textureSlots.count == 3),
              pass.textureSlots[0] == nil,
              pass.textureSlots.indices.contains(1),
              let namedPath = pass.textureSlots[1],
              SceneNamedTextureReference.parse(namedPath)
                  == .init(
                      providerLayerID: reference.providerLayerID,
                      variant: .primary
                  ),
              pass.userTextureInputs.isEmpty,
              pass.texturePaths.count
                  == pass.textureSlots.compactMap({ $0 }).count,
              normalizedPaths(pass.texturePaths)
                  == normalizedPaths(pass.textureSlots.compactMap { $0 }),
              aggregateCombosAreStrict(pass.combos) else {
            return false
        }
        if pass.textureSlots.count == 3 {
            guard pass.textureSlots[2] == nil else { return false }
        }
        return true
    }

    private nonisolated static func aggregateCombosAreStrict(
        _ authored: [String: Int]
    ) -> Bool {
        let allowed = Set([
            "BLENDMODE", "TRANSFORMUV", "TRANSFORMREPEAT", "WRITEALPHA",
            "NUMBLENDTEXTURES", "OPACITYMASK",
        ])
        var normalized: [String: Int] = [:]
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey),
                  normalized.updateValue(value, forKey: normalizedKey) == nil
            else { return false }
        }
        let transformUV = normalized["TRANSFORMUV", default: 0]
        let transformRepeat = normalized["TRANSFORMREPEAT", default: 0]
        return normalized["BLENDMODE", default: 0] == 0
            && normalized["NUMBLENDTEXTURES", default: 1] == 1
            && normalized["OPACITYMASK", default: 0] == 0
            && (0...1).contains(transformUV)
            && (0...2).contains(transformRepeat)
            && (transformUV == 1 || transformRepeat == 0)
            && (0...1).contains(normalized["WRITEALPHA", default: 0])
    }

    private nonisolated static func normalizedPaths(_ paths: [String]) -> [String] {
        paths.map {
            $0.replacingOccurrences(of: "\\", with: "/").lowercased()
        }
    }

    /// Checks one nested provider's complete active dependency owner. A
    /// dependency-free provider is a terminal source; a one-provider legacy
    /// binding or a previously admitted aggregate must exactly cover every
    /// active provider ID. Unknown IDs, self edges and cyclic nodes remain
    /// rejected before any target reservation or graph execution is created.
    nonisolated static func providerDependenciesAreAdmitted(
        provider: SceneRenderDescriptor.Layer,
        activeDependencies: Set<Int>,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        cyclicLayerIDs: Set<Int>,
        legacyBindings: [Int: Binding],
        admittedAggregates: [Int: MultiProviderAggregate]
    ) -> Bool {
        guard !cyclicLayerIDs.contains(provider.id),
              activeDependencies.allSatisfy({ dependencyID in
                  dependencyID != provider.id
                      && layersByID[dependencyID] != nil
                      && !cyclicLayerIDs.contains(dependencyID)
              }) else { return false }
        guard !activeDependencies.isEmpty else { return true }
        if let aggregate = admittedAggregates[provider.id] {
            return aggregate.providerLayerIDs == activeDependencies
        }
        guard let binding = legacyBindings[provider.id] else { return false }
        return binding.providerLayerID != provider.id
            && activeDependencies == [binding.providerLayerID]
    }

    nonisolated static func resolvedMaterialReference(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference]
    ) -> Reference? {
        guard let reference = references.first,
              reference.slot.slotIndex == 1,
              references.allSatisfy({ candidate in
                  candidate.consumerLayerID == reference.consumerLayerID
                      && candidate.providerLayerID == reference.providerLayerID
                      && candidate.variant == reference.variant
                      && candidate.slot.slotIndex == 1
              }) else { return nil }

        for candidate in references {
            let effects = visibleEffects.filter { $0.id == candidate.slot.effectID }
            guard effects.count == 1, let effect = effects.first else { return nil }
            let passes = effect.passes.filter {
                $0.passIndex == candidate.slot.passIndex
            }
            guard passes.count == 1, let pass = passes.first else { return nil }
            let userTextureAllowsNamedFallback =
                SceneNamedTextureDependencyReferenceAnalysis
                    .userTextureAllowsNamedFallback(
                        slotIndex: candidate.slot.slotIndex,
                        pass: pass
                    )
            // Authored constants and combos select shader semantics only;
            // the admitted MaterialProgram owns them. The dependency binding
            // keeps proving the structural carrier: exact slot path, single
            // provider/variant, and no user-texture override on the slot.
            guard pass.textureSlots.indices.contains(candidate.slot.slotIndex),
                  let path = pass.textureSlots[candidate.slot.slotIndex],
                  SceneNamedTextureReference.parse(path) == .init(
                      providerLayerID: candidate.providerLayerID,
                      variant: candidate.variant
                  ),
                  userTextureAllowsNamedFallback else {
                return nil
            }
        }
        return reference
    }

    /// Bounded structural carrier for one hidden static solid publication.
    /// Effect path, combo values and authored constants belong to shader and
    /// MaterialProgram admission; they never select this dependency owner.
    nonisolated static func singleSlot3SolidLayerReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference]
    ) -> Reference? {
        guard supportsStructuralUtilityConsumer(layer),
              visibleEffects.count == 1,
              let effect = visibleEffects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.count == 4,
              pass.textureSlots[0...2].allSatisfy({ $0 == nil }),
              let path = pass.textureSlots[3],
              pass.texturePaths == [path],
              (!pass.userTextureInputs.indices.contains(3)
                  || pass.userTextureInputs[3] == nil),
              references.count == 1,
              let reference = references.first,
              reference.slot.effectID == effect.id,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 3,
              layer.dependencyLayerIDs == [reference.providerLayerID] else {
            return nil
        }
        return reference
    }


    /// Shape probe for the deferred multi-provider composition atom. This
    /// carries no provider ownership or execution behavior.
    nonisolated static func isMultiProviderUtilityCandidate(
        layer: SceneRenderDescriptor.Layer,
        references: [Reference]
    ) -> Bool {
        guard layer.utilityLayer?.kind == .composition,
              layer.contentKind == "composition",
              layer.childLayerIDs.isEmpty else { return false }
        let activeReferences = references.filter { reference in
            guard let effect = layer.effects.first(where: {
                $0.id == reference.slot.effectID
            }) else { return false }
            return effect.visible != false
        }
        let providerIDs = Set(activeReferences.compactMap { reference in
            reference.providerLayerID == layer.id
                ? nil : reference.providerLayerID
        })
        return activeReferences.count >= 2 && providerIDs.count > 1
    }

    /// Returns whether a layer can own a lossless aggregate publication. The
    /// original B2 atom is a childless composition utility; hidden image graph
    /// providers use the same typed external-primary vector and therefore may
    /// participate in a nested closure. Visible ordinary images stay on their
    /// existing single-provider route until a separate contract proves them.
    nonisolated static func isMultiProviderAggregateCandidate(
        layer: SceneRenderDescriptor.Layer,
        references: [Reference]
    ) -> Bool {
        let isUtility = isMultiProviderUtilityCandidate(
            layer: layer,
            references: references
        )
        let isHiddenImage = layer.contentKind == "image"
            && layer.puppetMeshPath == nil
            && layer.utilityLayer == nil
            && layer.visible == false
            && layer.childLayerIDs.isEmpty
            && layer.authoredDependencies.isEmpty
        guard isUtility || isHiddenImage else { return false }
        let activeReferences = references.filter { reference in
            layer.effects.first(where: { $0.id == reference.slot.effectID })?
                .visible != false
        }
        let providerIDs = Set(activeReferences.compactMap { reference in
            reference.providerLayerID == layer.id
                ? nil : reference.providerLayerID
        })
        return activeReferences.count >= 2 && providerIDs.count > 1
    }

}
