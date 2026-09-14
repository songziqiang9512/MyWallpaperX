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
        let authoredIndex = Dictionary(uniqueKeysWithValues:
            authoredLayerIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let aggregateBindings = multiProviderAggregatesByConsumerLayerID.values
            .flatMap(\.bindings)
        func bindingsForConsumer(_ layerID: Int) -> [Binding] {
            var result = bindingsByConsumerLayerID.values.filter {
                $0.consumerLayerID == layerID
            }
            result.append(contentsOf: aggregateBindings.filter {
                $0.consumerLayerID == layerID
            })
            return result
        }
        var indegree = Dictionary(uniqueKeysWithValues:
            authoredLayerIDs.map { ($0, 0) }
        )
        var successors: [Int: Set<Int>] = [:]
        for binding in Array(bindingsByConsumerLayerID.values)
            + aggregateBindings
        where available.contains(binding.providerLayerID)
            && available.contains(binding.consumerLayerID)
            && binding.providerLayerID != binding.consumerLayerID
            && requiredGraphOutputProviderLayerIDs.contains(
                binding.providerLayerID
            ) {
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
        var remaining = available
        var result: [Int] = []
        result.reserveCapacity(authoredLayerIDs.count)
        var forwardGraphProviders = Set((Array(bindingsByConsumerLayerID.values)
            + aggregateBindings)
            .filter(\.requiresForwardCapture)
            .map(\.providerLayerID))
            .intersection(requiredGraphOutputProviderLayerIDs)
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
        while let next = remaining.filter({ indegree[$0] == 0 }).min(by: {
            let lhsForward = forwardGraphProviders.contains($0)
            let rhsForward = forwardGraphProviders.contains($1)
            if lhsForward != rhsForward { return lhsForward }
            return authoredIndex[$0, default: .max]
                < authoredIndex[$1, default: .max]
        }) {
            remaining.remove(next)
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
        let authoredIndex = Dictionary(uniqueKeysWithValues:
            authoredLayerIDs.enumerated().map { ($0.element, $0.offset) }
        )
        // Aggregate consumers own several independently captured providers.
        // Keep these bindings in the same forward-preparation ledger as the
        // legacy one-provider route; otherwise a provider authored after its
        // consumer would never be published before the consumer executes.
        let aggregateBindings = multiProviderAggregatesByConsumerLayerID.values
            .flatMap(\.bindings)
        func bindingsForConsumer(_ layerID: Int) -> [Binding] {
            var result = bindingsByConsumerLayerID.values.filter {
                $0.consumerLayerID == layerID
            }
            result.append(contentsOf: aggregateBindings.filter {
                $0.consumerLayerID == layerID
            })
            return result
        }
        var providers = Set<Int>(bindingsByConsumerLayerID.values.compactMap {
            binding in
            guard binding.requiresForwardCapture,
                  activeExecutionLayerIDs.contains(binding.consumerLayerID)
            else { return nil }
            return binding.providerLayerID
        })
        providers.formUnion(aggregateBindings.compactMap { binding in
            guard binding.requiresForwardCapture,
                  activeExecutionLayerIDs.contains(binding.consumerLayerID)
            else { return nil }
            return binding.providerLayerID
        })
        providers.formUnion(staticModelBindingsByConsumerLayerID.values.compactMap {
            binding in
            binding.requiresForwardCapture
                && activeStaticModelConsumerLayerIDs.contains(binding.consumerLayerID)
                ? binding.providerLayerID : nil
        })
        var changed = true
        while changed {
            changed = false
            for providerLayerID in providers {
                for upstream in bindingsForConsumer(providerLayerID) {
                    changed = providers.insert(upstream.providerLayerID).inserted
                        || changed
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
        var remaining = providers
        var result: [Int] = []
        result.reserveCapacity(providers.count)
        while let next = remaining.filter({ indegree[$0] == 0 }).min(by: {
            authoredIndex[$0, default: .max]
                < authoredIndex[$1, default: .max]
        }) {
            remaining.remove(next)
            result.append(next)
            for successor in successors[next] ?? [] {
                indegree[successor, default: 0] -= 1
            }
        }
        return result.count == providers.count ? result : nil
    }
}
