import Foundation

extension SceneDependencyRenderPlan {
    nonisolated final class SourcePreparationPlan {
        let preparationLayerIDs: [Int]
        let authoredLayerIDs: [Int]
        let positions: [Int: Int]
        let graphs: Set<Int>
        let bindingsByConsumer: [Int: [Binding]]
        let dependencyOrder: [Int]
        let ownCuts: [Int: Int]
        let fixedSourceLayerIDs: Set<Int>
        let executionRoots: Set<Int>
        let modelProviders: [Int: Int]

        init(authoredLayerIDs: [Int], positions: [Int: Int], graphs: Set<Int>,
             bindingsByConsumer: [Int: [Binding]], dependencyOrder: [Int],
             ownCuts: [Int: Int], fixedSourceLayerIDs: Set<Int>,
             executionRoots: Set<Int>, modelProviders: [Int: Int]) {
            self.preparationLayerIDs = dependencyOrder.filter { graphs.contains($0) }
            self.authoredLayerIDs = authoredLayerIDs
            self.positions = positions
            self.graphs = graphs
            self.bindingsByConsumer = bindingsByConsumer
            self.dependencyOrder = dependencyOrder
            self.ownCuts = ownCuts
            self.fixedSourceLayerIDs = fixedSourceLayerIDs
            self.executionRoots = executionRoots
            self.modelProviders = modelProviders
        }

        func preparationSchedule(
            excludingSlotsByConsumerLayerID excluded: [Int: Set<SceneEffectPassSlot>] = [:]
        ) -> PreparationSchedule {
            var providersByConsumer: [Int: Set<Int>] = [:]
            for (consumer, bindings) in bindingsByConsumer {
                for binding in bindings where !binding.referenceSlots.allSatisfy({
                    excluded[consumer]?.contains($0) == true
                }) {
                    providersByConsumer[consumer, default: []].insert(binding.providerLayerID)
                }
            }
            var bounds: [Int: Int] = [:]
            for layerID in dependencyOrder {
                let ownCut = ownCuts[layerID]!
                if fixedSourceLayerIDs.contains(layerID) {
                    bounds[layerID] = ownCut
                    continue
                }
                var ready = -1
                if graphs.contains(layerID) {
                    for provider in providersByConsumer[layerID] ?? [] {
                        ready = max(ready, bounds[provider]!)
                    }
                    if ready >= 0 && !ready.isMultiple(of: 2) { ready += 1 }
                    if executionRoots.contains(layerID) { ready = min(ready, ownCut) }
                }
                bounds[layerID] = ready
            }
            var cuts: [Int: Int] = [:]
            func request(_ provider: Int, by requestedCut: Int) {
                guard let bound = bounds[provider], let ownCut = ownCuts[provider] else { return }
                var need = requestedCut
                if graphs.contains(provider), !fixedSourceLayerIDs.contains(provider),
                   need >= 0 && !need.isMultiple(of: 2) { need -= 1 }
                guard need >= bound else { return }
                let cut: Int
                if fixedSourceLayerIDs.contains(provider) {
                    cut = ownCut
                } else {
                    let atNeed = max(bound, min(ownCut, need))
                    cut = atNeed < ownCut && bound == -1 ? -1 : atNeed
                }
                cuts[provider] = min(cuts[provider] ?? cut, cut)
            }
            for layerID in graphs.intersection(executionRoots) {
                cuts[layerID] = ownCuts[layerID]!
            }
            for consumer in executionRoots where !graphs.contains(consumer) {
                guard let position = positions[consumer] else { continue }
                let cut = ownCuts[consumer] ?? position * 2
                for provider in providersByConsumer[consumer] ?? [] { request(provider, by: cut) }
            }
            for (consumer, provider) in modelProviders {
                request(provider, by: -1)
                request(provider, by: positions[consumer]! * 2)
            }
            for consumer in dependencyOrder.reversed() where graphs.contains(consumer) {
                guard let cut = cuts[consumer] else { continue }
                for provider in providersByConsumer[consumer] ?? [] { request(provider, by: cut) }
            }
            let ranks = Dictionary(uniqueKeysWithValues:
                dependencyOrder.enumerated().map { ($0.element, $0.offset) })
            let ordered = dependencyOrder.filter { cuts[$0] != nil }.sorted {
                let lhs = cuts[$0]!, rhs = cuts[$1]!
                return lhs == rhs ? ranks[$0]! < ranks[$1]! : lhs < rhs
            }
            var preparation: [Int] = []
            var prepass: [Int] = []
            var before: [Int: [Int]] = [:]
            var scheduledGraphs = Set<Int>()
            for layerID in ordered {
                let isGraph = graphs.contains(layerID)
                let cut = cuts[layerID]!
                if isGraph { preparation.append(layerID) }
                guard cut != ownCuts[layerID] else { continue }
                if isGraph { scheduledGraphs.insert(layerID) }
                if cut == -1 { prepass.append(layerID) }
                else { before[authoredLayerIDs[cut / 2], default: []].append(layerID) }
            }
            return .init(preparationLayerIDs: preparation,
                prepassProviderLayerIDs: prepass, providersBeforeLayerID: before,
                scheduledGraphProviderLayerIDs: scheduledGraphs)
        }
    }

    nonisolated func sourcePreparationPlan(
        authoredLayerIDs: [Int], availableExecutionLayerIDs: Set<Int>,
        visibleRootLayerIDs: Set<Int>, activeStaticModelConsumerLayerIDs: Set<Int>,
        sourceAfterLayerIDByLayerID: [Int: Int]
    ) -> SourcePreparationPlan? {
        guard Set(authoredLayerIDs).count == authoredLayerIDs.count else { return nil }
        let positions = Dictionary(uniqueKeysWithValues:
            authoredLayerIDs.enumerated().map { ($0.element, $0.offset) })
        let graphs = availableExecutionLayerIDs.intersection(positions.keys)
        let rawProviders = requiredProviderLayerIDs.subtracting(graphs)
            .subtracting(cyclicLayerIDs).intersection(positions.keys)
        let available = graphs.union(rawProviders)
        let modelConsumers = Set(staticModelBindingsByConsumerLayerID.keys)
        let executionRoots = visibleRootLayerIDs.subtracting(modelConsumers)
            .union(visibleRootLayerIDs.intersection(activeStaticModelConsumerLayerIDs)
                .intersection(modelConsumers))
        var bindingsByConsumer: [Int: [Binding]] = [:]
        for (consumer, binding) in bindingsByConsumerLayerID
        where available.contains(binding.providerLayerID)
            && !cyclicLayerIDs.contains(binding.providerLayerID) {
            bindingsByConsumer[consumer, default: []].append(binding)
        }
        for (consumer, aggregate) in multiProviderAggregatesByConsumerLayerID {
            bindingsByConsumer[consumer, default: []].append(contentsOf: aggregate.bindings.filter {
                available.contains($0.providerLayerID) && !cyclicLayerIDs.contains($0.providerLayerID)
            })
        }
        var modelProviders: [Int: Int] = [:]
        for consumer in activeStaticModelConsumerLayerIDs.intersection(visibleRootLayerIDs) {
            if let binding = staticModelBindingsByConsumerLayerID[consumer],
               positions[consumer] != nil, available.contains(binding.providerLayerID) {
                modelProviders[consumer] = binding.providerLayerID
            }
        }
        var needed = graphs.intersection(executionRoots)
        for consumer in executionRoots where !graphs.contains(consumer) {
            needed.formUnion((bindingsByConsumer[consumer] ?? []).map(\.providerLayerID))
        }
        needed.formUnion(modelProviders.values)
        var pending = Array(needed)
        while let consumer = pending.popLast() {
            guard graphs.contains(consumer) else { continue }
            for binding in bindingsByConsumer[consumer] ?? [] {
                if needed.insert(binding.providerLayerID).inserted { pending.append(binding.providerLayerID) }
            }
        }
        bindingsByConsumer = bindingsByConsumer.mapValues { bindings in
            bindings.filter { needed.contains($0.providerLayerID) }
        }
        var remaining = Dictionary(uniqueKeysWithValues: needed.map { ($0, 0) })
        var consumersByProvider: [Int: Set<Int>] = [:]
        for consumer in needed.intersection(graphs) {
            for provider in Set((bindingsByConsumer[consumer] ?? []).map(\.providerLayerID)) {
                remaining[consumer, default: 0] += 1
                consumersByProvider[provider, default: []].insert(consumer)
            }
        }
        var order: [Int] = []
        while order.count < needed.count {
            guard let next = authoredLayerIDs.first(where: { remaining[$0] == 0 }) else { return nil }
            order.append(next)
            remaining.removeValue(forKey: next)
            for consumer in consumersByProvider[next] ?? [] { remaining[consumer, default: 0] -= 1 }
        }
        var ownCuts: [Int: Int] = [:]
        for layerID in Set(order).union(executionRoots.intersection(positions.keys)) {
            if let trigger = sourceAfterLayerIDByLayerID[layerID] {
                guard let position = positions[trigger] else { return nil }
                ownCuts[layerID] = position * 2 + 1
            } else { ownCuts[layerID] = positions[layerID]! * 2 }
        }
        return SourcePreparationPlan(authoredLayerIDs: authoredLayerIDs,
            positions: positions, graphs: graphs, bindingsByConsumer: bindingsByConsumer,
            dependencyOrder: order, ownCuts: ownCuts,
            fixedSourceLayerIDs: Set(sourceAfterLayerIDByLayerID.keys),
            executionRoots: executionRoots, modelProviders: modelProviders)
    }
}
