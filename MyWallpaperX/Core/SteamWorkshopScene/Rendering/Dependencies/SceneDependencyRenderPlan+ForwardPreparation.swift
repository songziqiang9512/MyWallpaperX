import Foundation

extension SceneDependencyRenderPlan {
    /// Stable dependency-first transaction order for the shared graph
    /// submission. Final compositor order remains authored and is not changed.
    nonisolated func resolvedMaterialPreparationOrder(
        authoredLayerIDs: [Int]
    ) -> [Int]? {
        guard Set(authoredLayerIDs).count == authoredLayerIDs.count else {
            return nil
        }
        let available = Set(authoredLayerIDs)
        // Both plan maps are keyed by consumer, so one consumer's complete
        // binding vector is a direct lookup pair - never a values scan.
        func bindingsForConsumer(_ layerID: Int) -> [Binding] {
            guard let aggregate = multiProviderAggregatesByConsumerLayerID[
                layerID
            ] else {
                return bindingsByConsumerLayerID[layerID].map { [$0] } ?? []
            }
            guard let singular = bindingsByConsumerLayerID[layerID] else {
                return aggregate.bindings
            }
            return [singular] + aggregate.bindings
        }
        var indegree = Dictionary(uniqueKeysWithValues:
            authoredLayerIDs.map { ($0, 0) }
        )
        var successors: [Int: Set<Int>] = [:]
        func admitEdge(_ binding: Binding) {
            guard available.contains(binding.providerLayerID),
                  available.contains(binding.consumerLayerID),
                  binding.providerLayerID != binding.consumerLayerID,
                  requiredGraphOutputProviderLayerIDs.contains(
                      binding.providerLayerID
                  ) else { return }
            // Only an effectful provider owns an earlier graph transaction.
            // A static forward provider is captured by the renderer prepass;
            // moving its consumer in this ledger would diverge from authored
            // compositor consumption order and make safe predecessors appear
            // unconsumed.
            if successors[binding.providerLayerID, default: []]
                .insert(binding.consumerLayerID).inserted {
                indegree[binding.consumerLayerID, default: 0] += 1
            }
        }
        for binding in bindingsByConsumerLayerID.values {
            admitEdge(binding)
        }
        for aggregate in multiProviderAggregatesByConsumerLayerID.values {
            for binding in aggregate.bindings {
                admitEdge(binding)
            }
        }
        var forwardGraphProviders = Set(
            bindingsByConsumerLayerID.values.compactMap {
                $0.requiresForwardCapture ? $0.providerLayerID : nil
            }
        )
        for aggregate in multiProviderAggregatesByConsumerLayerID.values {
            for binding in aggregate.bindings
            where binding.requiresForwardCapture {
                forwardGraphProviders.insert(binding.providerLayerID)
            }
        }
        forwardGraphProviders.formIntersection(requiredGraphOutputProviderLayerIDs)
        var changed = true
        while changed {
            changed = false
            for providerLayerID in forwardGraphProviders {
                for upstream in bindingsForConsumer(providerLayerID)
                where requiredGraphOutputProviderLayerIDs.contains(
                    upstream.providerLayerID
                ) {
                    changed = forwardGraphProviders.insert(
                        upstream.providerLayerID
                    ).inserted || changed
                }
            }
        }
        var emitted = Set<Int>()
        var result: [Int] = []
        result.reserveCapacity(authoredLayerIDs.count)
        while emitted.count < available.count {
            // Selection order of the previous `filter + min(by:)`: any
            // forward-graph provider wins over a plain layer, then authored
            // order decides.
            let next = authoredLayerIDs.first {
                !emitted.contains($0)
                    && indegree[$0] == 0
                    && forwardGraphProviders.contains($0)
            } ?? authoredLayerIDs.first {
                !emitted.contains($0) && indegree[$0] == 0
            }
            guard let next else { break }
            emitted.insert(next)
            result.append(next)
            for successor in successors[next] ?? [] {
                indegree[successor, default: 0] -= 1
            }
        }
        return result.count == authoredLayerIDs.count ? result : nil
    }

    /// Returns every provider that must publish before authored compositor
    /// traversal can begin. A directly forward provider brings its complete
    /// already-validated upstream binding closure with it; otherwise a middle
    /// provider could execute before the named texture it consumes exists.
    nonisolated func forwardDependencyPreparationOrder(
        authoredLayerIDs: [Int],
        activeExecutionLayerIDs: Set<Int>,
        activeStaticModelConsumerLayerIDs: Set<Int> = []
    ) -> [Int]? {
        guard Set(authoredLayerIDs).count == authoredLayerIDs.count else {
            return nil
        }
        let available = Set(authoredLayerIDs)
        // Aggregate consumers own several independently captured providers.
        // Keep these bindings in the same forward-preparation ledger as the
        // legacy one-provider route; otherwise a provider authored after its
        // consumer would never be published before the consumer executes.
        func bindingsForConsumer(_ layerID: Int) -> [Binding] {
            guard let aggregate = multiProviderAggregatesByConsumerLayerID[
                layerID
            ] else {
                return bindingsByConsumerLayerID[layerID].map { [$0] } ?? []
            }
            guard let singular = bindingsByConsumerLayerID[layerID] else {
                return aggregate.bindings
            }
            return [singular] + aggregate.bindings
        }
        var providers = Set<Int>()
        for binding in bindingsByConsumerLayerID.values
        where binding.requiresForwardCapture
            && activeExecutionLayerIDs.contains(binding.consumerLayerID) {
            providers.insert(binding.providerLayerID)
        }
        for aggregate in multiProviderAggregatesByConsumerLayerID.values {
            guard activeExecutionLayerIDs.contains(aggregate.consumerLayerID)
            else { continue }
            for binding in aggregate.bindings
            where binding.requiresForwardCapture {
                providers.insert(binding.providerLayerID)
            }
        }
        for binding in staticModelBindingsByConsumerLayerID.values
        where binding.requiresForwardCapture
            && activeStaticModelConsumerLayerIDs.contains(
                binding.consumerLayerID
            ) {
            providers.insert(binding.providerLayerID)
        }
        var changed = true
        while changed {
            changed = false
            for providerLayerID in providers {
                for upstream in bindingsForConsumer(providerLayerID) {
                    changed = providers.insert(upstream.providerLayerID)
                        .inserted || changed
                }
            }
        }
        guard providers.isSubset(of: available) else { return nil }
        var indegree = Dictionary(uniqueKeysWithValues:
            providers.map { ($0, 0) }
        )
        var successors: [Int: Set<Int>] = [:]
        for consumerLayerID in providers {
            for binding in bindingsForConsumer(consumerLayerID)
            where providers.contains(binding.providerLayerID) {
                if successors[binding.providerLayerID, default: []]
                    .insert(consumerLayerID).inserted {
                    indegree[consumerLayerID, default: 0] += 1
                }
            }
        }
        var emitted = Set<Int>()
        var result: [Int] = []
        result.reserveCapacity(providers.count)
        while emitted.count < providers.count {
            // Authored-order scan replaces `filter + min(by:)`: providers are
            // a subset of the authored IDs, so the first ready candidate in
            // authored order is exactly the minimum authored index.
            guard let next = authoredLayerIDs.first(where: {
                providers.contains($0)
                    && !emitted.contains($0)
                    && indegree[$0] == 0
            }) else { break }
            emitted.insert(next)
            result.append(next)
            for successor in successors[next] ?? [] {
                indegree[successor, default: 0] -= 1
            }
        }
        return result.count == providers.count ? result : nil
    }
}
