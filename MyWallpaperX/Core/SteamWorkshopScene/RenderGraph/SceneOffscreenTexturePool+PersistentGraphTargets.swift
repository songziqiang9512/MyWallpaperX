import Foundation
import Metal

struct ScenePersistentGraphTargetFramePlan {
    let residencyDomainID: UUID
    let chainPlan: SceneGraphRenderTargetChainPlan
    let orderingContext: SceneGraphCommandQueueOrderingContext?
}

extension SceneOffscreenTexturePool {
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
}
