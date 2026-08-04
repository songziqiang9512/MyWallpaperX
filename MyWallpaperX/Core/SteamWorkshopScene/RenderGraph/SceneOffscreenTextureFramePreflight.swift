import Foundation
import Metal

/// Pure whole-frame residency simulation. It mirrors chain replacement,
/// history demotion, the two-generation ceiling, and LRU pressure before any
/// Metal texture is allocated or any capability-owned layer is claimed.
enum SceneOffscreenTextureFramePreflight {
    enum Result: Equatable {
        case ready
        case temporarilyBlocked
        case rejected(reasonCode: String)
    }

    enum Location: Equatable {
        case currentChain(SceneGraphRenderTargetChainPlan.Key)
        case currentOther
        case retired
        case history
    }

    struct Resident {
        let id: Int
        var location: Location
        var chainPlan: SceneGraphRenderTargetChainPlan?
        var history: SceneGraphHistoryResidency?
        var demotedHistory: SceneGraphHistoryResidency?
        var byteCost: Int
        var submissionPinCount: Int
        var historyPinCount: Int
        var permitsOrderedReuse: Bool
        let isResetInvalidated: Bool
        var lastAccess: UInt64
        let existedBeforeFrame: Bool
        var requiredByFrame: Bool

        var isFullChain: Bool { chainPlan != nil }
        var isTransientBlocker: Bool {
            existedBeforeFrame
                && (submissionPinCount > 0 || isResetInvalidated)
        }
    }

    static func evaluate(
        plans: [SceneGraphRenderTargetChainPlan],
        residents: [Resident],
        byteBudget: Int
    ) -> Result {
        guard byteBudget >= 0,
              Set(plans.map(\.key)).count == plans.count,
              plans.allSatisfy({
                  $0.residentByteCost >= 0 && $0.residentByteCost <= byteBudget
              }), residents.allSatisfy({
                  $0.byteCost >= 0
                      && $0.submissionPinCount >= 0
                      && $0.historyPinCount >= 0
              }) else {
            return .rejected(reasonCode: "frame-target-plan-invalid")
        }
        var values = residents
        var nextID = (values.map(\.id).max() ?? -1)
        var access = values.map(\.lastAccess).max() ?? 0
        for plan in plans {
            guard nextID < Int.max, access < UInt64.max else {
                return .rejected(reasonCode: "frame-target-identity-overflow")
            }
            nextID += 1
            access += 1
            if let result = apply(
                plan,
                values: &values,
                nextID: nextID,
                access: access,
                byteBudget: byteBudget
            ) {
                return result
            }
        }
        return .ready
    }

    private static func apply(
        _ plan: SceneGraphRenderTargetChainPlan,
        values: inout [Resident],
        nextID: Int,
        access: UInt64,
        byteBudget: Int
    ) -> Result? {
        let currentIDs = values.filter {
            $0.location == .currentChain(plan.key)
        }.map(\.id)
        guard currentIDs.count <= 1 else {
            return .rejected(reasonCode: "frame-target-current-ambiguous")
        }
        let pinCounts = values.compactMap {
            $0.chainPlan?.key == plan.key ? $0.submissionPinCount : nil
        }
        guard SceneResolvedMaterialInFlightCapacity.admitsNewSubmission(pinCounts)
        else { return blocked(values, byteBudget: byteBudget) }
        let currentID = currentIDs.first
        if let currentID, let index = index(of: currentID, in: values),
           values[index].chainPlan == plan, plan.historyEffects.isEmpty,
           (values[index].submissionPinCount == 0
            || values[index].permitsOrderedReuse) {
            values[index].submissionPinCount += 1
            values[index].permitsOrderedReuse = false
            values[index].requiredByFrame = true
            values[index].lastAccess = access
            return fit(&values, byteBudget: byteBudget)
        }

        let idle = values.filter {
            $0.location == .retired
                && $0.submissionPinCount == 0
                && $0.historyPinCount == 0
                && !$0.isResetInvalidated
                && $0.chainPlan?.key == plan.key
        }.sorted {
            ($0.lastAccess, $0.id) < ($1.lastAccess, $1.id)
        }
        let reusable = idle.first { $0.chainPlan == plan }
        let consumed = reusable ?? idle.first
        var replacementIDs = Set<Int>()
        if let currentID, let index = index(of: currentID, in: values),
           values[index].submissionPinCount == 0 {
            replacementIDs.insert(currentID)
        }
        if let consumed { replacementIDs.insert(consumed.id) }
        let retainedCount = values.filter {
            $0.isFullChain && $0.chainPlan?.key == plan.key
                && !replacementIDs.contains($0.id)
        }.count
        guard retainedCount < SceneResolvedMaterialInFlightCapacity.maximumSubmissions
        else { return blocked(values, byteBudget: byteBudget) }

        let pinnedCurrentSeed: SceneGraphHistoryResidency?
        if let currentID, let index = index(of: currentID, in: values),
           values[index].submissionPinCount > 0,
           values[index].demotedHistory?.isCompatible(with: plan) == true {
            pinnedCurrentSeed = values[index].demotedHistory
        } else {
            pinnedCurrentSeed = nil
        }
        if let currentID, let index = index(of: currentID, in: values) {
            let current = values[index]
            values.remove(at: index)
            if current.submissionPinCount > 0 {
                var retired = current
                retired.location = .retired
                values.append(retired)
            } else if let history = current.demotedHistory {
                values.append(historyResident(from: current, history: history))
            }
        }
        if let consumed, let index = index(of: consumed.id, in: values) {
            values.remove(at: index)
        }
        let compatibleHistoryCount = values.filter {
            $0.location == .history && !$0.isResetInvalidated
                && $0.history?.isCompatible(with: plan) == true
        }.count
        guard pinnedCurrentSeed != nil || compatibleHistoryCount <= 1 else {
            return .rejected(reasonCode: "frame-target-history-ambiguous")
        }
        values.append(.init(
            id: nextID,
            location: .currentChain(plan.key),
            chainPlan: plan,
            history: nil,
            demotedHistory: nil,
            byteCost: plan.residentByteCost,
            submissionPinCount: 1,
            historyPinCount: plan.historyEffects.count,
            permitsOrderedReuse: false,
            isResetInvalidated: false,
            lastAccess: access,
            existedBeforeFrame: false,
            requiredByFrame: true
        ))
        return fit(&values, byteBudget: byteBudget)
    }

    private static func fit(
        _ values: inout [Resident],
        byteBudget: Int
    ) -> Result? {
        guard var total = cost(values) else {
            return .rejected(reasonCode: "frame-target-byte-cost-overflow")
        }
        while total > byteBudget {
            let victims = values.filter {
                $0.submissionPinCount == 0 && !$0.isResetInvalidated
                    && !$0.requiredByFrame
                    && ($0.location == .currentOther
                        || $0.location == .retired
                        || isCurrentChain($0.location))
            }.sorted {
                ($0.lastAccess, $0.id) < ($1.lastAccess, $1.id)
            }
            guard let victim = victims.first,
                  let index = index(of: victim.id, in: values) else {
                return blocked(values, byteBudget: byteBudget)
            }
            values.remove(at: index)
            if let history = victim.demotedHistory {
                values.append(historyResident(from: victim, history: history))
            }
            guard let next = cost(values), next < total else {
                return .rejected(reasonCode: "frame-target-eviction-invariant")
            }
            total = next
        }
        return nil
    }

    private static func blocked(
        _ values: [Resident],
        byteBudget: Int
    ) -> Result {
        let required = values.filter(\.requiredByFrame)
        if cost(required).map({ $0 > byteBudget }) != false {
            return .rejected(reasonCode: "frame-target-byte-budget-exceeded")
        }
        let transientIDs = Set(values.filter(\.isTransientBlocker).map(\.id))
        guard !transientIDs.isEmpty else {
            return .rejected(reasonCode: "frame-target-residency-unavailable")
        }

        // A submission pin can disappear on GPU completion, but any history
        // owned by that generation remains immutable. Classify the frame as
        // deferred only when releasing every pre-frame transient blocker would
        // actually make the requested workload fit beside that residual state.
        var residual: [Resident] = []
        for value in values {
            guard transientIDs.contains(value.id) else {
                residual.append(value)
                continue
            }
            guard !value.requiredByFrame else {
                return .rejected(reasonCode: "frame-target-residency-invariant")
            }
            if value.isResetInvalidated { continue }
            if let history = value.demotedHistory {
                residual.append(historyResident(from: value, history: history))
            }
        }
        guard cost(residual).map({ $0 <= byteBudget }) == true else {
            return .rejected(reasonCode: "frame-target-residency-unavailable")
        }
        return .temporarilyBlocked
    }

    private static func historyResident(
        from value: Resident,
        history: SceneGraphHistoryResidency
    ) -> Resident {
        var result = value
        result.location = .history
        result.chainPlan = nil
        result.history = history
        result.demotedHistory = nil
        result.byteCost = history.byteCost
        result.submissionPinCount = 0
        result.permitsOrderedReuse = false
        result.requiredByFrame = false
        return result
    }

    private static func isCurrentChain(_ location: Location) -> Bool {
        guard case .currentChain = location else { return false }
        return true
    }

    private static func index(of id: Int, in values: [Resident]) -> Int? {
        values.firstIndex { $0.id == id }
    }

    private static func cost(_ values: [Resident]) -> Int? {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value.byteCost)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}

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
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = persistentTargetPlans(
                  admittedGraphs: admittedGraphs,
                  pairPlan: pairPlan,
                  extentPolicy: extentPolicy,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), case .success(let plan) = SceneGraphRenderTargetChainPlan.make(
                  plans: prepared.plans,
                  pairPlan: pairPlan,
                  byteBudget: residentByteBudget
              ) else { return nil }
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
        guard let requiredSharedPairKeys = requiredSharedPairKeys(for: plans) else {
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
            requiredSharedPairKeys: requiredSharedPairKeys
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
              ensureSharedPairs(requiredSharedPairKeys) else {
            return nil
        }
        guard preflightPersistentGraphTargets(framePlans) == .ready else {
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
