import Foundation
import Metal

struct SceneGraphCommandQueueOrderingContext {
    let commandBuffer: MTLCommandBuffer
    var isPending: Bool { commandBuffer.status == .notEnqueued }

    func accepts(_ actual: MTLCommandBuffer?) -> Bool {
        guard let actual else { return false }
        return actual === commandBuffer && isPending
            && ObjectIdentifier(actual.commandQueue)
                == ObjectIdentifier(commandBuffer.commandQueue)
    }
}

struct SceneOffscreenTextureAllocationCandidate {
    let key: SceneOffscreenTextureAllocationCache.Key
    let allocation: SceneOffscreenTextureAllocationCache.Allocation
    let byteCost: Int

    var keyMatchesAllocation: Bool {
        switch (key, allocation) {
        case (.pair, .pair), (.authoredPair, .pair): true
        case (.graph(let effect), .graph(let lease)):
            lease.table.plan.output.effect == effect
        default: false
        }
    }
}

extension SceneOffscreenTextureAllocationCache {
    struct SharedPair {
        let key: Key
        let pair: SceneOffscreenTexturePool.Pair
        let identity: PhysicalIdentity
    }

    func cachedPair(for key: Key) -> SceneOffscreenTexturePool.Pair? {
        locked {
            let residentKey = ResidentKey.current(key)
            guard var entry = residents[residentKey],
                  case .pair(let pair, _) = entry.allocation else { return nil }
            guard accessCounter < UInt64.max else { return nil }
            accessCounter += 1
            entry.lastAccess = accessCounter
            residents[residentKey] = entry
            return pair
        }
    }

    func currentSharedPairLocked(
        for plan: SceneGraphRenderTargetChainPlan
    ) -> SharedPair? {
        guard let dimensions = plan.sharedPairDimensions else { return nil }
        let key = Key.pair(width: dimensions.width, height: dimensions.height)
        guard let entry = residents[.current(key)],
              !entry.isResetInvalidated,
              case .pair(let pair, let identity) = entry.allocation else {
            return nil
        }
        return .init(key: key, pair: pair, identity: identity)
    }

    func sharedPairMatches(
        _ pair: SharedPair?,
        allocation: SceneGraphRenderTargetChainAllocation
    ) -> Bool {
        guard allocation.plan.pairStorage == .shared else { return pair == nil }
        return pair?.identity.generation == allocation.fullFramePairGeneration
    }

    func reservationStillMatches(
        _ original: ChainReservation,
        _ refreshed: ChainReservation
    ) -> Bool {
        original.resetEpoch == refreshed.resetEpoch
            && original.historySeedGeneration == refreshed.historySeedGeneration
            && original.replacedCurrentGeneration == refreshed.replacedCurrentGeneration
            && original.consumedRetiredGeneration == refreshed.consumedRetiredGeneration
            && original.cachedAllocation?.generation
                == refreshed.cachedAllocation?.generation
            && original.reusableAllocation?.generation
                == refreshed.reusableAllocation?.generation
            && original.sharedPair?.key == refreshed.sharedPair?.key
            && original.sharedPair?.identity.generation
                == refreshed.sharedPair?.identity.generation
    }

    func makeCommit(
        _ value: (
            chain: SceneGraphRenderTargetChainAllocation,
            submission: UUID,
            history: [EffectKey: UUID],
            tokens: [EffectKey: Set<Token>],
            sharedPair: (generation: UInt64, submission: UUID)?
        )
    ) -> ScenePreparedPersistentGraphTargets.Commit {
        let submission = SceneGraphRenderTargetResidencyPin(
            identity: value.submission,
            purpose: .submission,
            generation: value.chain.generation,
            cache: self
        )
        let history = Dictionary(uniqueKeysWithValues: value.tokens.map {
            effect, tokens in
            (effect, SceneGraphRenderTargetResidencyPin(
                identity: value.history[effect]!,
                purpose: .history(effect, tokens),
                generation: value.chain.generation,
                cache: self
            ))
        })
        let sharedPair = value.sharedPair.map {
            SceneGraphRenderTargetResidencyPin(
                identity: $0.submission,
                purpose: .submission,
                generation: $0.generation,
                cache: self
            )
        }
        return .init(
            leases: value.chain.leases,
            submissionPin: submission,
            historyPinsByEffect: history,
            sharedPairPin: sharedPair
        )
    }
}

extension SceneOffscreenTextureAllocationCache.Entry {
    func permitsSharedPairReuse(
        orderingContext: SceneGraphCommandQueueOrderingContext?
    ) -> Bool {
        guard case .pair = allocation, !isResetInvalidated else { return false }
        guard !submissionPins.isEmpty else { return true }
        guard let orderingContext, orderingContext.isPending else { return false }
        let current = orderingContext.commandBuffer
        return submissionPins.values.allSatisfy { pin in
            guard let prior = pin.orderingContext else { return false }
            let previous = prior.commandBuffer
            if current === previous { return true }
            return ObjectIdentifier(current.commandQueue)
                    == ObjectIdentifier(previous.commandQueue)
                && previous.status != .notEnqueued
        }
    }
}

extension SceneOffscreenTexturePool {
    func requiredSharedPairKeys(
        for plans: [ScenePersistentGraphTargetFramePlan]
    ) -> Set<SceneOffscreenTextureAllocationCache.Key>? {
        var keys = Set<SceneOffscreenTextureAllocationCache.Key>()
        for framePlan in plans where framePlan.chainPlan.pairStorage == .shared {
            guard let dimensions = framePlan.chainPlan.sharedPairDimensions else {
                return nil
            }
            keys.insert(.pair(width: dimensions.width, height: dimensions.height))
        }
        return keys
    }

    func ensureSharedPairs(
        _ keys: Set<SceneOffscreenTextureAllocationCache.Key>
    ) -> Bool {
        for key in keys.sorted(by: { lhs, rhs in
            switch (lhs, rhs) {
            case let (.pair(lw, lh), .pair(rw, rh)):
                return (lw, lh) < (rw, rh)
            default:
                return false
            }
        }) {
            guard case .pair(let width, let height) = key else { return false }
            guard allocationCache.allocation(for: key) != nil
                || textures(
                    width: width,
                    height: height,
                    maximumDimension: max(width, height)
                ) != nil else { return false }
        }
        return true
    }
}
