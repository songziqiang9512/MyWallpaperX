import Foundation
import Metal

struct ScenePersistentGraphTargetFramePlan {
    let residencyDomainID: UUID
    let chainPlan: SceneGraphRenderTargetChainPlan
    let orderingContext: SceneGraphCommandQueueOrderingContext?
}

extension SceneOffscreenTextureAllocationCache {
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
}

extension SceneOffscreenTexturePool {
    /// Allocates the two-texture pair shared by history-free graph chains.
    /// This is a generic persistent-target resource, not a legacy chain batch.
    func sharedPairCandidate(
        width: Int,
        height: Int,
        textureFactory: ScenePersistentGraphTargetAllocator.TextureFactory? = nil
    ) -> Candidate? {
        let key = CacheKey.sharedGraphPair(width: width, height: height)
        guard let byteCost = byteCost(
            width: width,
            height: height,
            textureCount: 2
        ), byteCost <= residentByteBudget else { return nil }
        if let cached = allocationCache.allocation(for: key) {
            guard case .sharedGraphPair = cached else { return nil }
            return .init(key: key, allocation: cached, byteCost: byteCost)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let factory = textureFactory ?? { [device] descriptor, label in
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = label
            return texture
        }
        let label = "sharedPair:\(width)x\(height)"
        guard let first = factory(descriptor, "SceneSharedPairA \(label)"),
              let second = factory(descriptor, "SceneSharedPairB \(label)"),
              let physicalIdentity = allocationCache.issuePhysicalIdentity(
                  textures: [first, second]
              ) else { return nil }
        return .init(
            key: key,
            allocation: .sharedGraphPair(
                SharedGraphPair(first: first, second: second),
                physicalIdentity
            ),
            byteCost: byteCost
        )
    }

    func framePlanForPersistentGraphTargets(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int,
        sharesFullFramePairWhenHistoryFree: Bool = false,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = persistentTargetPlans(
                  admittedGraphs: admittedGraphs,
                  pairPlan: pairPlan,
                  extentPolicy: extentPolicy,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ) else { return nil }
        let plan: SceneGraphRenderTargetChainPlan
        if sharesFullFramePairWhenHistoryFree,
           case let .success(shared) = SceneGraphRenderTargetChainPlan.make(
               plans: prepared.plans,
               pairPlan: pairPlan,
               byteBudget: residentByteBudget,
               pairStorage: .shared
           ) {
            plan = shared
        } else {
            guard case let .success(owned) = SceneGraphRenderTargetChainPlan.make(
                plans: prepared.plans,
                pairPlan: pairPlan,
                byteBudget: residentByteBudget,
                pairStorage: .owned
            ) else { return nil }
            plan = owned
        }
        return .init(
            residencyDomainID: residencyDomainID,
            chainPlan: plan,
            orderingContext: orderingContext
        )
    }

    func preflightPersistentGraphTargets(
        _ plans: [ScenePersistentGraphTargetFramePlan]
    ) -> SceneOffscreenTextureFramePreflight.Result {
        guard plans.allSatisfy({ $0.residencyDomainID == residencyDomainID }) else {
            return .rejected(reasonCode: "frame-target-residency-domain-mismatch")
        }
        guard let requiredSharedPairKeys = requiredSharedPairKeys(for: plans),
              let pendingSharedPairByteCosts = pendingSharedPairByteCosts(
                  for: requiredSharedPairKeys
              ) else {
            return .rejected(reasonCode: "frame-target-shared-pair-unavailable")
        }
        let contexts = plans.compactMap(\.orderingContext)
        guard contexts.isEmpty || contexts.count == plans.count,
              Set(contexts.map({ ObjectIdentifier($0.commandBuffer) })).count <= 1 else {
            return .rejected(reasonCode: "frame-target-ordering-context-mismatch")
        }
        return allocationCache.preflightChains(
            plans.map(\.chainPlan),
            orderingContext: contexts.first,
            requiredSharedPairKeys: requiredSharedPairKeys,
            pendingSharedPairByteCosts: pendingSharedPairByteCosts
        )
    }

    func preparePersistentGraphTargets(
        framePlan: ScenePersistentGraphTargetFramePlan
    ) -> ScenePreparedPersistentGraphTargets? {
        preparePersistentGraphTargets(framePlans: [framePlan])?.first
    }

    func preparePersistentGraphTargets(
        framePlans: [ScenePersistentGraphTargetFramePlan]
    ) -> [ScenePreparedPersistentGraphTargets]? {
        guard let requiredSharedPairKeys = requiredSharedPairKeys(for: framePlans),
              ensureSharedPairs(requiredSharedPairKeys),
              preflightPersistentGraphTargets(framePlans) == .ready else {
            return nil
        }
        let contexts = framePlans.compactMap(\.orderingContext)
        return ScenePersistentGraphTargetAllocator(
            device: device, cache: allocationCache
        ).prepare(
            plans: framePlans.map(\.chainPlan),
            orderingContext: contexts.first
        )
    }

    func commitAndPinPersistentGraphTargets(
        _ targets: [ScenePreparedPersistentGraphTargets],
        historyTokensByTarget: [[ScenePreparedPersistentGraphTargets.EffectKey:
            Set<ScenePreparedPersistentGraphTargets.Token>]],
        commandBuffer: MTLCommandBuffer
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        guard !targets.isEmpty,
              targets.count == historyTokensByTarget.count else { return nil }
        let requests = zip(targets, historyTokensByTarget).compactMap {
            $0.0.takeCommitRequest(
                historyTokensByEffect: $0.1,
                commandBuffer: commandBuffer
            )
        }
        guard requests.count == targets.count,
              requests.allSatisfy({ $0.cache === allocationCache }) else {
            return nil
        }
        return allocationCache.commitAndPin(requests)
    }

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
