import Foundation
import Metal

/// A one-use cache-managed preparation handle. Selection contains original input indices;
/// history/discard arrays align with the selected inputs, in original order.
/// The cache lock is the sole authority for inputs/consume/cancel/deinit.
final class SceneGraphPreparationHandle {
    typealias Prepared = ScenePreparedPersistentGraphTargets
    fileprivate let cache: SceneOffscreenTextureAllocationCache
    fileprivate let identity: UUID
    fileprivate let epoch: UUID
    fileprivate var inputs: [Prepared.AdmissionInput]?

    fileprivate init(cache: SceneOffscreenTextureAllocationCache, identity: UUID,
                     epoch: UUID, inputs: [Prepared.AdmissionInput]) {
        self.cache = cache
        self.identity = identity
        self.epoch = epoch
        self.inputs = inputs
    }

    func finalize(
        selectedInputIndices: [Int]? = nil,
        historyTokensByTarget: [[Prepared.EffectKey: Set<Prepared.Token>]],
        discardedHistoryEffectsByTarget: [Set<Prepared.EffectKey>]? = nil,
        commandBuffer: MTLCommandBuffer? = nil
    ) -> [Prepared.Commit]? {
        cache.finalizePreparation(self, selectedInputIndices: selectedInputIndices,
            historyTokensByTarget: historyTokensByTarget,
            discardedHistoryEffectsByTarget: discardedHistoryEffectsByTarget,
            commandBuffer: commandBuffer)
    }

    func cancel() { cache.cancelPreparation(self) }
    deinit { cache.cancelPreparation(self) }
}

extension SceneOffscreenTextureAllocationCache {
    /// Consumes prepared inputs without making any history decision. Failure
    /// terminates already-taken inputs, exactly as a failed one-shot commit does.
    func admitPreparedTargets(
        _ targets: [ScenePreparedPersistentGraphTargets]
    ) -> SceneGraphPreparationHandle? {
        var inputs: [ScenePreparedPersistentGraphTargets.AdmissionInput] = []
        for target in targets {
            guard let input = target.takeAdmissionInput() else { return nil }
            inputs.append(input)
        }
        return locked {
            guard !inputs.isEmpty,
                  Set(inputs.map(\.candidate.key)).count == inputs.count,
                  inputs.allSatisfy({ $0.cache === self }) else { return nil }
            let identity = UUID()
            var fresh: [Candidate] = []
            for input in inputs {
                let candidate = input.candidate, original = input.reservation
                guard original.resetEpoch == resetEpoch,
                      original.orderingContext?.isPending != false,
                      case .layerGraph(let graph) = candidate.allocation,
                      candidate.key == .layerGraph(graph.plan.key),
                      candidate.byteCost == graph.plan.residentByteCost,
                      candidate.byteCost >= 0,
                      sharedPairMatches(original.sharedPair, allocation: graph),
                      let refreshed = reserveGraphLocked(plan: graph.plan,
                        orderingContext: original.orderingContext, values: residents),
                      reservationStillMatches(original, refreshed) else { return nil }
                if let cached = original.cachedAllocation {
                    guard cached.generation == graph.generation,
                          cached.plan == graph.plan,
                          graph.texturesBySlot.allSatisfy({ slot, texture in
                              cached.texturesBySlot[slot] === texture
                          }) else { return nil }
                } else if let reusable = original.reusableAllocation {
                    var proof = residents
                    guard consumeRetired(original, candidate: graph, values: &proof),
                          graph.plan.slots.allSatisfy({ slot in
                              if graph.plan.pairStorage == .shared,
                                 case .fullFrame = slot.kind { return true }
                              return reusable.texturesBySlot[slot.id]
                                  === graph.texturesBySlot[slot.id]
                          }) else { return nil }
                } else {
                    guard !residents.values.contains(where: {
                        $0.allocation.generation == graph.generation
                    }) else { return nil }
                    fresh.append(candidate)
                }
            }
            // Perform only the original cache's legal idle replacement/demotion
            // in a local view. No graph/history publication occurs here.
            var next = residents
            for input in inputs {
                let original = input.reservation
                guard original.cachedAllocation == nil else { continue }
                if let generation = original.replacedCurrentGeneration {
                    let key = ResidentKey.current(input.candidate.key)
                    guard let old = next[key], old.allocation.generation == generation,
                          old.preparationPins.isEmpty, !old.isResetInvalidated else { return nil }
                    if old.submissionPins.isEmpty && old.sceneColorPins.isEmpty {
                        next.removeValue(forKey: key)
                        if let history = old.historyOnlyEntry(),
                           case .history(let value) = history.allocation {
                            next[.history(value.plan.key, generation)] = history
                        }
                    }
                }
                if original.reusableAllocation == nil,
                   let generation = original.consumedRetiredGeneration {
                    guard let old = next[.retired(generation)], !old.isPinned,
                          !old.isResetInvalidated else { return nil }
                    next.removeValue(forKey: .retired(generation))
                }
            }
            var rebased: [ScenePreparedPersistentGraphTargets.AdmissionInput] = []
            var protected = Set<UInt64>()
            for input in inputs {
                guard case .layerGraph(let graph) = input.candidate.allocation,
                      let reservation = reserveGraphLocked(plan: graph.plan,
                        orderingContext: input.reservation.orderingContext, values: next),
                      preparationResourcesMatch(input, refreshed: reservation, graph: graph)
                else { return nil }
                // This reservation comes from the actual post-demotion view;
                // never edit a generation or stamp a newer revision onto the old one.
                rebased.append(.init(historyRehydrateCopiesByEffect: input.historyRehydrateCopiesByEffect,
                    cache: self, candidate: input.candidate, reservation: reservation))
                protected.formUnion([
                    reservation.cachedAllocation?.generation,
                    reservation.reusableAllocation?.generation,
                    reservation.sharedPair?.identity.generation,
                    reservation.historySeedGeneration,
                    reservation.replacedCurrentGeneration,
                    reservation.consumedRetiredGeneration
                ].compactMap { $0 })
            }
            for generation in protected {
                let matches = next.filter { $0.value.allocation.generation == generation }
                guard matches.count == 1, let found = matches.first,
                      !found.value.isResetInvalidated,
                      found.value.preparationPins.isEmpty else { return nil }
                next[found.key]?.preparationPins.insert(identity)
            }
            var access = accessCounter
            for candidate in fresh {
                guard case .layerGraph(let graph) = candidate.allocation else { return nil }
                let (increment, overflow) = access.addingReportingOverflow(1)
                guard !overflow else { return nil }
                access = increment
                next[.pending(identity, graph.plan.key)] = Entry(
                    allocation: candidate.allocation, byteCost: candidate.byteCost,
                    preparationPins: [identity], lastAccess: access)
            }
            guard evictToFit(&next, incomingCost: 0,
                protected: Set(inputs.map(\.candidate.key))) else { return nil }
            apply((next, access))
            return .init(cache: self, identity: identity, epoch: resetEpoch, inputs: rebased)
        }
    }

    /// The candidate is already materialized. Only disposable cache residency
    /// may change: its actual source seed, cached/reused storage and shared pair
    /// must still be exactly the resources for which the allocator made leases.
    private func preparationResourcesMatch(
        _ input: ScenePreparedPersistentGraphTargets.AdmissionInput,
        refreshed: GraphReservation, graph: SceneLayerGraphTargetAllocation
    ) -> Bool {
        let old = input.reservation
        guard old.resetEpoch == refreshed.resetEpoch,
              old.cachedAllocation?.generation == refreshed.cachedAllocation?.generation,
              old.reusableAllocation?.generation == refreshed.reusableAllocation?.generation,
              old.historySeedGeneration == refreshed.historySeedGeneration,
              old.sharedPair?.key == refreshed.sharedPair?.key,
              old.sharedPair?.identity.generation == refreshed.sharedPair?.identity.generation,
              sharedPairMatches(refreshed.sharedPair, allocation: graph) else { return false }
        if let pair = refreshed.sharedPair {
            guard pair.pair.first === old.sharedPair?.pair.first,
                  pair.pair.second === old.sharedPair?.pair.second,
                  graph.texturesBySlot[graph.plan.fullFramePair.zeroSlot] === pair.pair.first,
                  graph.texturesBySlot[graph.plan.fullFramePair.oneSlot] === pair.pair.second else { return false }
        }
        switch (old.historySeed, refreshed.historySeed) {
        case (nil, nil): break
        case let (before?, after?):
            guard before.generation == after.generation,
                  before.tokensByEffect == after.tokensByEffect,
                  before.tokensBySlot == after.tokensBySlot,
                  before.texturesBySlot.count == after.texturesBySlot.count,
                  before.texturesBySlot.allSatisfy({ slot, texture in
                      after.texturesBySlot[slot] === texture
                  }) else { return false }
        default: return false
        }
        guard let expected = ScenePersistentGraphTargetAllocator.rehydrateCopies(
            seed: refreshed.historySeed, allocation: graph),
              Set(expected.keys) == Set(input.historyRehydrateCopiesByEffect.keys)
        else { return false }
        return expected.allSatisfy { effect, copies in
            let actual = input.historyRehydrateCopiesByEffect[effect] ?? []
            return copies.count == actual.count
                && Set(actual.map(\.sourceToken)).count == actual.count
                && copies.allSatisfy { copy in actual.contains {
                    $0.sourceToken == copy.sourceToken && $0.targetToken == copy.targetToken
                        && $0.sourceTexture === copy.sourceTexture
                        && $0.targetTexture === copy.targetTexture
                } }
        }
    }

    fileprivate func finalizePreparation(
        _ handle: SceneGraphPreparationHandle,
        selectedInputIndices: [Int]?,
        historyTokensByTarget: [[EffectKey: Set<Token>]],
        discardedHistoryEffectsByTarget: [Set<EffectKey>]?,
        commandBuffer: MTLCommandBuffer?
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        locked {
            guard handle.cache === self, let inputs = handle.inputs else { return nil }
            let selected = selectedInputIndices ?? Array(inputs.indices)
            guard handle.epoch == resetEpoch,
                  selected.allSatisfy({ inputs.indices.contains($0) }),
                  Set(selected).count == selected.count,
                  selected == selected.sorted(),
                  historyTokensByTarget.count == selected.count,
                  discardedHistoryEffectsByTarget == nil
                    || discardedHistoryEffectsByTarget?.count == selected.count,
                  let view = preparationWorkingViewLocked(handle, inputs: inputs,
                    selected: Set(selected))
            else { cancelPreparationLocked(handle); return nil }
            if selected.isEmpty {
                // Legitimate all-local-fallback: no graph/history publication.
                // The same locked view removes pending and normalizes released pins.
                apply((view, accessCounter))
                handle.inputs = nil
                return []
            }
            let requests = selected.enumerated().map { index, inputIndex in
                let input = inputs[inputIndex]
                return ScenePreparedPersistentGraphTargets.CommitRequest(
                    cache: self, candidate: input.candidate, reservation: input.reservation,
                    historyTokensByEffect: historyTokensByTarget[index],
                    discardedHistoryEffects: discardedHistoryEffectsByTarget?[index] ?? [],
                    commandBuffer: commandBuffer)
            }
            guard let staged = stageGraphCommitLocked(requests, values: view,
                forceReservationRefresh: true)
            else { cancelPreparationLocked(handle); return nil }
            // No unlock or publicly visible release/reacquire window. The sole
            // commit core converts real pending storage to current storage.
            apply(staged.residency)
            handle.inputs = nil
            return staged.pins.map(makeCommit)
        }
    }

    private func preparationWorkingViewLocked(
        _ handle: SceneGraphPreparationHandle,
        inputs: [ScenePreparedPersistentGraphTargets.AdmissionInput],
        selected: Set<Int>
    ) -> [ResidentKey: Entry]? {
        var view = residents
        var protected = Set<UInt64>()
        var selectedDependencies = Set<UInt64>()
        for (index, input) in inputs.enumerated() {
            let original = input.reservation
            let dependencies = [
                original.cachedAllocation?.generation, original.reusableAllocation?.generation,
                original.sharedPair?.identity.generation, original.historySeedGeneration,
                original.replacedCurrentGeneration, original.consumedRetiredGeneration
            ].compactMap { $0 }
            protected.formUnion(dependencies)
            if selected.contains(index) { selectedDependencies.formUnion(dependencies) }
            if original.cachedAllocation == nil && original.reusableAllocation == nil {
                guard case .layerGraph(let graph) = input.candidate.allocation,
                      let entry = view.removeValue(forKey: .pending(handle.identity, graph.plan.key)),
                      entry.allocation.generation == graph.generation,
                      entry.byteCost == input.candidate.byteCost,
                      entry.preparationPins == [handle.identity],
                      !entry.isResetInvalidated else { return nil }
            }
        }
        for generation in protected {
            let matches = view.filter { $0.value.allocation.generation == generation }
            guard matches.count == 1, let found = matches.first,
                  !found.value.isResetInvalidated,
                  found.value.preparationPins.contains(handle.identity) else { return nil }
            var entry = found.value
            entry.preparationPins.remove(handle.identity)
            if selectedDependencies.contains(generation) {
                // Selected reservation refresh still sees its original locations.
                view[found.key] = entry
            } else {
                // An omitted seed may have lost its external history pin while
                // preparation retained storage. Apply the ordinary release rule,
                // not selected-candidate history validation or a zombie entry.
                view.removeValue(forKey: found.key)
                storeAfterPinRelease(entry, key: found.key, into: &view)
            }
        }
        // A retained dependency outside this exact complete set is a bug, not
        // permission to silently strip another resident's preparation marker.
        guard !view.values.contains(where: { $0.preparationPins.contains(handle.identity) })
        else { return nil }
        return view
    }

    fileprivate func cancelPreparation(_ handle: SceneGraphPreparationHandle) {
        locked { cancelPreparationLocked(handle) }
    }

    private func cancelPreparationLocked(_ handle: SceneGraphPreparationHandle) {
        guard handle.cache === self, handle.inputs != nil else { return }
        for key in Array(residents.keys) {
            guard var entry = residents[key], entry.preparationPins.remove(handle.identity) != nil
            else { continue }
            residents.removeValue(forKey: key)
            if case .pending(let identity, _) = key, identity == handle.identity {
                // Pending storage has never been encoded and has no public pins.
                continue
            }
            storeAfterPinRelease(entry, key: key, into: &residents)
        }
        handle.inputs = nil
        revision = UUID()
    }
}
