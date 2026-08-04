import Foundation

extension SceneOffscreenTextureAllocationCache {
    struct LegacyBatchSnapshot {
        let revision: UUID
        let resetEpoch: UUID
        let requiredSharedPairKeys: Set<Key>
        let pendingSharedPairByteCosts: [Key: Int]
    }

    func preflightChains(
        _ plans: [SceneGraphRenderTargetChainPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil,
        requiredSharedPairKeys: Set<Key> = [],
        pendingSharedPairByteCosts: [Key: Int] = [:]
    ) -> SceneOffscreenTextureFramePreflight.Result {
        locked {
            preflightChainsLocked(
                plans,
                orderingContext: orderingContext,
                requiredSharedPairKeys: requiredSharedPairKeys,
                pendingSharedPairByteCosts: pendingSharedPairByteCosts
            )
        }
    }

    func preflightLegacyBatch(
        _ plans: [SceneGraphRenderTargetChainPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext,
        requiredSharedPairKeys: Set<Key>,
        pendingSharedPairByteCosts: [Key: Int]
    ) -> LegacyBatchSnapshot? {
        locked {
            guard preflightChainsLocked(
                plans,
                orderingContext: orderingContext,
                requiredSharedPairKeys: requiredSharedPairKeys,
                pendingSharedPairByteCosts: pendingSharedPairByteCosts
            ) == .ready else { return nil }
            return .init(
                revision: revision,
                resetEpoch: resetEpoch,
                requiredSharedPairKeys: requiredSharedPairKeys,
                pendingSharedPairByteCosts: pendingSharedPairByteCosts
            )
        }
    }

    private func preflightChainsLocked(
        _ plans: [SceneGraphRenderTargetChainPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext?,
        requiredSharedPairKeys: Set<Key>,
        pendingSharedPairByteCosts: [Key: Int]
    ) -> SceneOffscreenTextureFramePreflight.Result {
        guard orderingContext?.isPending != false else {
            return .rejected(reasonCode: "frame-target-ordering-context-invalid")
        }
        guard Set(pendingSharedPairByteCosts.keys).isSubset(
            of: requiredSharedPairKeys
        ), pendingSharedPairByteCosts.allSatisfy({ key, byteCost in
            guard case .sharedGraphPair = key else { return false }
            return byteCost >= 0 && residents[.current(key)] == nil
        }), plans.allSatisfy({ plan in
            guard plan.pairStorage == .shared else { return true }
            guard let dimensions = plan.sharedPairDimensions else { return false }
            return requiredSharedPairKeys.contains(.sharedGraphPair(
                width: dimensions.width,
                height: dimensions.height
            ))
        }), requiredSharedPairKeys.allSatisfy({ key in
            guard case .sharedGraphPair = key else { return false }
            if let entry = residents[.current(key)] {
                guard case .sharedGraphPair = entry.allocation else { return false }
                return true
            }
            return pendingSharedPairByteCosts[key] != nil
        }) else {
            return .rejected(reasonCode: "frame-target-shared-pair-unavailable")
        }

        var snapshot = residents.enumerated().map { offset, value in
            let (key, entry) = value
            let location: SceneOffscreenTextureFramePreflight.Location = switch key {
            case .current(.chain(let chainKey)): .currentChain(chainKey)
            case .current: .currentOther
            case .retired: .retired
            case .history: .history
            }
            let (chainPlan, history): (
                SceneGraphRenderTargetChainPlan?, SceneGraphHistoryResidency?
            ) = switch entry.allocation {
            case .chain(let chain): (chain.plan, nil)
            case .history(let value): (nil, value)
            default: (nil, nil)
            }
            let demotedHistory: SceneGraphHistoryResidency?
            if let historyEntry = entry.historyOnlyEntry(),
               case .history(let value) = historyEntry.allocation {
                demotedHistory = value
            } else {
                demotedHistory = nil
            }
            let requiredByFrame: Bool = switch key {
            case .current(let current): requiredSharedPairKeys.contains(current)
            default: false
            }
            return SceneOffscreenTextureFramePreflight.Resident(
                id: offset,
                location: location,
                chainPlan: chainPlan,
                history: history,
                demotedHistory: demotedHistory,
                byteCost: entry.byteCost,
                submissionPinCount: entry.submissionPins.count,
                historyPinCount: entry.historyPins.count,
                permitsOrderedReuse: chainPlan.map {
                    entry.permitsOrderedSubmissionReuse(
                        for: $0,
                        orderingContext: orderingContext
                    )
                } ?? false,
                isResetInvalidated: entry.isResetInvalidated,
                lastAccess: entry.lastAccess,
                existedBeforeFrame: true,
                requiredByFrame: requiredByFrame
            )
        }
        for (_, byteCost) in pendingSharedPairByteCosts {
            snapshot.append(.init(
                id: snapshot.count,
                location: .currentOther,
                chainPlan: nil,
                history: nil,
                demotedHistory: nil,
                byteCost: byteCost,
                submissionPinCount: 0,
                historyPinCount: 0,
                permitsOrderedReuse: false,
                isResetInvalidated: false,
                lastAccess: accessCounter,
                existedBeforeFrame: false,
                requiredByFrame: true
            ))
        }
        for plan in plans where plan.pairStorage == .shared {
            guard let dimensions = plan.sharedPairDimensions else {
                return .rejected(reasonCode: "frame-target-shared-pair-unavailable")
            }
            let key = Key.sharedGraphPair(
                width: dimensions.width,
                height: dimensions.height
            )
            if pendingSharedPairByteCosts[key] != nil { continue }
            guard let entry = residents[.current(key)],
                  entry.permitsSharedPairReuse(orderingContext: orderingContext)
            else {
                return .rejected(
                    reasonCode: "frame-target-shared-pair-ordering-rejected"
                )
            }
        }
        return SceneOffscreenTextureFramePreflight.evaluate(
            plans: plans,
            residents: snapshot,
            byteBudget: preflightByteBudget
        )
    }

    func validateLegacySharedPairCandidatesLocked(
        _ candidates: [Candidate],
        snapshot: LegacyBatchSnapshot
    ) -> [Key: SharedPair]? {
        guard snapshot.revision == revision,
              snapshot.resetEpoch == resetEpoch,
              Set(snapshot.pendingSharedPairByteCosts.keys).isSubset(
                of: snapshot.requiredSharedPairKeys
              ),
              Set(candidates.map(\.key))
                == Set(snapshot.pendingSharedPairByteCosts.keys),
              Set(candidates.map(\.key)).count == candidates.count else {
            return nil
        }
        var result: [Key: SharedPair] = [:]
        for candidate in candidates {
            guard candidate.keyMatchesAllocation,
                  candidate.byteCost
                    == snapshot.pendingSharedPairByteCosts[candidate.key],
                  residents[.current(candidate.key)] == nil,
                  case let .sharedGraphPair(pair, identity) = candidate.allocation,
                  result.updateValue(
                      .init(key: candidate.key, pair: pair, identity: identity),
                      forKey: candidate.key
                  ) == nil else { return nil }
        }
        return result
    }

    func stageLegacySharedPairCandidatesLocked(
        _ candidates: [Candidate],
        values: inout [ResidentKey: Entry],
        access: inout UInt64
    ) -> Bool {
        for candidate in candidates {
            guard values[.current(candidate.key)] == nil,
                  !values.values.contains(where: {
                      $0.allocation.generation == candidate.allocation.generation
                  }) else { return false }
            let (nextAccess, overflow) = access.addingReportingOverflow(1)
            guard !overflow else { return false }
            access = nextAccess
            values[.current(candidate.key)] = .init(
                allocation: candidate.allocation,
                byteCost: candidate.byteCost,
                lastAccess: access
            )
        }
        return true
    }

    func reserveLegacyBatch(
        plans: [SceneGraphRenderTargetChainPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext,
        snapshot: LegacyBatchSnapshot,
        sharedPairCandidates: [Candidate]
    ) -> [ChainReservation]? {
        locked {
            guard orderingContext.isPending,
                  let pending = validateLegacySharedPairCandidatesLocked(
                      sharedPairCandidates,
                      snapshot: snapshot
                  ) else { return nil }
            return reserveChainsLocked(
                plans: plans,
                orderingContext: orderingContext,
                pendingSharedPairs: pending
            )
        }
    }

    func commitAndPinLegacyBatch(
        snapshot: LegacyBatchSnapshot,
        sharedPairCandidates: [Candidate],
        requests: [ScenePreparedPersistentGraphTargets.CommitRequest]
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        commitAndPin(
            requests,
            legacySnapshot: snapshot,
            sharedPairCandidates: sharedPairCandidates
        )
    }

    func consumeRetired(
        _ reservation: ChainReservation,
        candidate: SceneGraphRenderTargetChainAllocation,
        values: inout [ResidentKey: Entry]
    ) -> Bool {
        guard let generation = reservation.consumedRetiredGeneration else {
            return reservation.reusableAllocation == nil
        }
        let key = ResidentKey.retired(generation)
        guard let retired = values.removeValue(forKey: key),
              !retired.isPinned,
              !retired.isResetInvalidated,
              case .chain(let old) = retired.allocation,
              old.generation == generation,
              old.plan.key == candidate.plan.key else { return false }
        guard let reusable = reservation.reusableAllocation else { return true }
        return reusable.generation == generation
            && candidate.generation != generation
            && reusable.plan == candidate.plan
            && old.plan == reusable.plan
            && old.plan.slots
                .filter { slot in
                    if case .fullFrame = slot.kind { return false }
                    return true
                }
                .allSatisfy { slot in
                    old.texturesBySlot[slot.id]
                        === candidate.texturesBySlot[slot.id]
                }
    }
}

extension SceneOffscreenTexturePool {
    func pendingSharedPairByteCosts(
        for keys: Set<SceneOffscreenTextureAllocationCache.Key>
    ) -> [SceneOffscreenTextureAllocationCache.Key: Int]? {
        var result: [SceneOffscreenTextureAllocationCache.Key: Int] = [:]
        for key in keys {
            guard case let .sharedGraphPair(width, height) = key else {
                return nil
            }
            if let allocation = allocationCache.allocation(for: key) {
                guard case .sharedGraphPair = allocation else { return nil }
                continue
            }
            guard let byteCost = byteCost(
                width: width, height: height, textureCount: 2
            ) else { return nil }
            result[key] = byteCost
        }
        return result
    }
}
