import Foundation
import Metal

enum ScenePersistentGraphTargetPlanningFailure: Error {
    case unsupportedPixelFormat
    case invalidRequest
    case invalidExtent
    case graphTargetPlan(SceneGraphRenderTargetPlan.Failure)
    case graphTargetIdentityMismatch
    case layerTargetPlan(SceneLayerGraphTargetPlan.Failure)

    var localFallbackReasonCode: String {
        switch self {
        case .graphTargetPlan(.unsupportedTargetDescriptor):
            return "frame-target-plan-unsupported-target-descriptor"
        default:
            return "frame-target-plan-rejected"
        }
    }

    static func isLocalFallbackReasonCode(_ reasonCode: String) -> Bool {
        reasonCode == "frame-target-plan-rejected"
            || reasonCode == "frame-target-plan-unsupported-target-descriptor"
    }
}

struct ScenePersistentGraphTargetFramePlan {
    let residencyDomainID: UUID
    let graphPlan: SceneLayerGraphTargetPlan
    let orderingContext: SceneGraphCommandQueueOrderingContext?
}

extension SceneOffscreenTextureAllocationCache {
    func preflightGraphs(
        _ plans: [SceneLayerGraphTargetPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil,
        requiredSharedPairKeys: Set<Key> = [],
        pendingSharedPairByteCosts: [Key: Int] = [:]
    ) -> SceneOffscreenTextureFramePreflight.Result {
        locked {
            preflightGraphsLocked(
                plans,
                orderingContext: orderingContext,
                requiredSharedPairKeys: requiredSharedPairKeys,
                pendingSharedPairByteCosts: pendingSharedPairByteCosts
            )
        }
    }

    private func preflightGraphsLocked(
        _ plans: [SceneLayerGraphTargetPlan],
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
            case .current(.layerGraph(let graphKey)): .currentGraph(graphKey)
            case .current: .currentOther
            case .retired: .retired
            case .history: .history
            }
            let (graphPlan, history): (
                SceneLayerGraphTargetPlan?, SceneGraphHistoryResidency?
            ) = switch entry.allocation {
            case .layerGraph(let graph): (graph.plan, nil)
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
                graphPlan: graphPlan,
                history: history,
                demotedHistory: demotedHistory,
                byteCost: entry.byteCost,
                submissionPinCount: entry.submissionPins.count,
                historyPinCount: entry.historyPins.count,
                permitsOrderedReuse: graphPlan.map {
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
                graphPlan: nil,
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
    /// Allocates the two-texture pair shared by history-free graph graphs.
    /// This is a generic persistent-target resource shared by graph executions.
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
        targetExecutionPlans: [SceneEffectStageExecutionPlan?] = [],
        materialFunctionTargetsByEffect: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>] = [:],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int,
        sharesFullFramePairWhenHistoryFree: Bool = false,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        guard case let .success(plan) = framePlanResultForPersistentGraphTargets(
            admittedGraphs: admittedGraphs,
            targetExecutionPlans: targetExecutionPlans,
            materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
            pairPlan: pairPlan,
            extentPolicy: extentPolicy,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight,
            sharesFullFramePairWhenHistoryFree: sharesFullFramePairWhenHistoryFree,
            orderingContext: orderingContext
        ) else { return nil }
        return plan
    }

    func framePlanResultForPersistentGraphTargets(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        targetExecutionPlans: [SceneEffectStageExecutionPlan?] = [],
        materialFunctionTargetsByEffect: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>] = [:],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int,
        sharesFullFramePairWhenHistoryFree: Bool = false,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> Result<ScenePersistentGraphTargetFramePlan,
        ScenePersistentGraphTargetPlanningFailure> {
        guard pixelFormat == .bgra8Unorm else {
            return .failure(.unsupportedPixelFormat)
        }
        let prepared: (
            plans: [SceneGraphRenderTargetPlan], width: Int, height: Int
        )
        switch persistentTargetPlansResult(
            admittedGraphs: admittedGraphs,
            targetExecutionPlans: targetExecutionPlans,
            materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
            pairPlan: pairPlan,
            extentPolicy: extentPolicy,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        ) {
        case let .success(value): prepared = value
        case let .failure(failure): return .failure(failure)
        }
        let plan: SceneLayerGraphTargetPlan
        if sharesFullFramePairWhenHistoryFree,
           case let .success(shared) = SceneLayerGraphTargetPlan.make(
               plans: prepared.plans,
               pairPlan: pairPlan,
               byteBudget: residentByteBudget,
               pairStorage: .shared
           ) {
            plan = shared
        } else {
            switch SceneLayerGraphTargetPlan.make(
                plans: prepared.plans,
                pairPlan: pairPlan,
                byteBudget: residentByteBudget,
                pairStorage: .owned
            ) {
            case let .success(owned): plan = owned
            case let .failure(failure): return .failure(.layerTargetPlan(failure))
            }
        }
        return .success(.init(
            residencyDomainID: residencyDomainID,
            graphPlan: plan,
            orderingContext: orderingContext
        ))
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
        return allocationCache.preflightGraphs(
            plans.map(\.graphPlan),
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
            plans: framePlans.map(\.graphPlan),
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
