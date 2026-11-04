import Foundation

extension SceneDependencyRenderPlan {
    nonisolated func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        staticLayerSourcePassthroughBlockedLayerIDs.contains(layerID)
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
        // A model is a visible consumer without an executable effect graph.
        // Its typed material demand activates only the available provider
        // graph; hidden models contribute no frame execution requirement.
        for binding in staticModelBindingsByConsumerLayerID.values
        where visibleRootLayerIDs.contains(binding.consumerLayerID)
            && requiredGraphOutputProviderLayerIDs.contains(binding.providerLayerID)
            && availableExecutionLayerIDs.contains(binding.providerLayerID) {
            reachable.insert(binding.providerLayerID)
        }
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
                for binding in aggregate.bindings
                where requiredGraphOutputProviderLayerIDs.contains(binding.providerLayerID)
                    && availableExecutionLayerIDs.contains(binding.providerLayerID) {
                    changed = reachable.insert(binding.providerLayerID).inserted
                        || changed
                }
            }
        }
        return reachable
    }
    /// A forward graph runs before any authored compositor layer. It may use
    /// its own layer source, static assets, frame inputs and one exact primary
    /// named input that the same dependency plan validates and schedules
    /// first. The main target and secondary targets retain authored-order
    /// dependencies and are rejected here.
    nonisolated static func providerGraphIsAuthoredOrderIndependent(
        _ layer: SceneRenderDescriptor.Layer,
        references: [Reference]? = nil,
        texturePaths: [String]? = nil
    ) -> Bool {
        let projectedDependencies = references.map { references in
            Set(references.compactMap {
                $0.providerLayerID == layer.id ? nil : $0.providerLayerID
            })
        }
        let references = references ?? SceneDependencyGraphAnalysis.references(in: [layer])
        guard let activeDependencies = projectedDependencies ?? activeDependencyProviderLayerIDs(
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
        let paths = texturePaths ?? layer.effects.filter { $0.visible != false }
            .flatMap(\.passes).flatMap { $0.texturePaths + $0.textureSlots.compactMap { $0 } }
        return paths.allSatisfy { path in
            guard path.caseInsensitiveCompare("_rt_FullFrameBuffer") != .orderedSame else { return false }
            guard let named = SceneNamedTextureReference.parse(path) else { return true }
            return activeDependencies == [named.providerLayerID] && named.variant == .primary
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
        // Admission already selected these exact atoms. Ordering must retain
        // a proven inactive slot without granting any unrequested reference.
        for effect in layer.effects {
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

    /// Chooses the existing publication renderer for a typed named slot.
    nonisolated static func programInputBinding(
        for reference: Reference,
        layer: SceneRenderDescriptor.Layer,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        order: [Int: Int],
        visibleLayerIDs: Set<Int>,
        providerReferences: [Reference]? = nil,
        providerTexturePaths: [String]? = nil
    ) -> Binding? {
        guard reference.consumerLayerID == layer.id,
              reference.providerLayerID != layer.id,
              reference.variant == .primary,
              let provider = layersByID[reference.providerLayerID],
              provider.childLayerIDs.isEmpty,
              provider.authoredDependencies.isEmpty,
              let providerOrder = order[provider.id],
              let consumerOrder = order[layer.id],
              providerOrder != consumerOrder else { return nil }
        let hasEffects = provider.effects.contains { $0.visible != false }
        let kind: Binding.Kind
        if provider.puppetMeshPath != nil {
            guard provider.contentKind == "image", hasNoUtilityLayer(provider) else { return nil }
            kind = .geometryLayer
        } else if isImageOrTextCompositeProvider(provider) {
            kind = .imageLayerBlend
        } else if isVisibleGraphOutputProvider(provider, visibleLayerIDs: visibleLayerIDs) {
            kind = .visibleImageGraphOutput
        } else if provider.contentKind == "solid", hasNoUtilityLayer(provider),
                  provider.dependencyLayerIDs.isEmpty,
                  provider.visible == false || hasEffects {
            kind = .solidLayer
        } else if provider.utilityLayer?.kind == .composition,
                  provider.contentKind == "composition" {
            kind = .resolvedMaterial
        } else {
            return nil
        }
        let forward = providerOrder > consumerOrder
        if forward {
            let independentRawSource = provider.effects.isEmpty
                && provider.dependencyLayerIDs.isEmpty
                && provider.utilityLayer?.copyBackground != true
            let independentGraph = hasEffects && provider.utilityLayer == nil
                && providerGraphIsAuthoredOrderIndependent(provider,
                    references: providerReferences, texturePaths: providerTexturePaths)
            // A visible graph's frame ticket still owns its main output.
            guard !(hasEffects && provider.visible != false
                    && visibleLayerIDs.contains(provider.id)),
                  independentRawSource || independentGraph
            else { return nil }
        }
        return Binding(consumerLayerID: layer.id, providerLayerID: provider.id,
                       slot: reference.slot, blendMode: 0, kind: kind,
                       requiresForwardCapture: forward,
                       requiresResolvedMaterialProgram: true)
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

    nonisolated static func isMultiProviderAggregateCandidate(
        layer: SceneRenderDescriptor.Layer,
        references: [Reference]
    ) -> Bool {
        guard layer.authoredDependencies.isEmpty,
              hasNoUtilityLayer(layer) || supportsStructuralUtilityConsumer(layer)
        else { return false }
        return references.filter { reference in
            reference.providerLayerID != layer.id
                && layer.effects.first(where: { $0.id == reference.slot.effectID })?
                    .visible != false
        }.count >= 2
    }

}
