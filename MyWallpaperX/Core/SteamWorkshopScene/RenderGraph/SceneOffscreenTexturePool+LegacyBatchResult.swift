import Metal

extension SceneOffscreenTexturePool {
    enum LegacyAuthoredFrameBatchResult {
        case ready([Int: LegacyAuthoredFrameTables])
        case deferred
        case rejected(reasonCode: String)
    }

    func prepareLegacyAuthoredFrameBatchResult(
        framePlans: [ScenePersistentGraphTargetFramePlan],
        orderingContext: SceneGraphCommandQueueOrderingContext
    ) -> LegacyAuthoredFrameBatchResult {
        guard !framePlans.isEmpty, orderingContext.isPending,
              framePlans.allSatisfy({
                  $0.residencyDomainID == residencyDomainID
                    && $0.orderingContext?.accepts(
                        orderingContext.commandBuffer
                    ) == true
              }), let keys = requiredSharedPairKeys(for: framePlans),
              let costs = pendingSharedPairByteCosts(for: keys) else {
            return .rejected(reasonCode: "legacy-authored-batch-contract")
        }
        switch allocationCache.preflightChains(
            framePlans.map(\.chainPlan),
            orderingContext: orderingContext,
            requiredSharedPairKeys: keys,
            pendingSharedPairByteCosts: costs
        ) {
        case .temporarilyBlocked:
            return .deferred
        case let .rejected(reasonCode):
            return .rejected(reasonCode: reasonCode)
        case .ready:
            guard let tables = prepareLegacyAuthoredFrameBatch(
                framePlans: framePlans,
                orderingContext: orderingContext
            ) else {
                return .rejected(
                    reasonCode: "legacy-authored-batch-commit-rejected"
                )
            }
            return .ready(tables)
        }
    }
}
