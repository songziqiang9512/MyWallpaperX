import Foundation
import Metal

/// One physical graph preparation, including its shared pairs. This carries
/// only allocation recovery state; graph/history publication remains unchanged.
final class SceneGraphAllocationRecoveryBatch {
    private let cache: SceneOffscreenTextureAllocationCache
    private(set) var expectedRevision: UUID
    private let resetEpoch: UUID
    private let protectedKeys: Set<SceneOffscreenTextureAllocationCache.Key>
    private var protectedGenerations: Set<UInt64>
    private var attemptedRecovery = false

    init(cache: SceneOffscreenTextureAllocationCache,
         protectedKeys: Set<SceneOffscreenTextureAllocationCache.Key>) {
        self.cache = cache
        self.protectedKeys = protectedKeys
        let state = cache.locked { () -> (UUID, UUID, Set<UInt64>) in
            // Shared pairs are allocated before graph reservations exist.
            // Preserve all generations of requested graphs until reserveGraphs
            // selects their exact cached/reusable/history sources.
            let generations = cache.residents.compactMap { key, entry -> UInt64? in
                if case let .current(current) = key, protectedKeys.contains(current) {
                    return entry.allocation.generation
                }
                if case let .layerGraph(graph) = entry.allocation,
                   protectedKeys.contains(.layerGraph(graph.plan.key)) {
                    return graph.generation
                }
                return nil
            }
            return (cache.revision, cache.resetEpoch, Set(generations))
        }
        expectedRevision = state.0
        resetEpoch = state.1
        protectedGenerations = state.2
    }

    var isCurrent: Bool {
        cache.locked { cache.revision == expectedRevision && cache.resetEpoch == resetEpoch }
    }

    func protect(_ reservations: [SceneOffscreenTextureAllocationCache.GraphReservation]) -> Bool {
        guard reservations.allSatisfy({
            $0.revision == expectedRevision && $0.resetEpoch == resetEpoch
        }), isCurrent else { return false }
        for value in reservations {
            protectedGenerations.formUnion([
                value.cachedAllocation?.generation, value.reusableAllocation?.generation,
                value.sharedPair?.identity.generation, value.historySeedGeneration,
                value.replacedCurrentGeneration, value.consumedRetiredGeneration
            ].compactMap { $0 })
        }
        return true
    }

    func makeTexture(_ factory: () -> MTLTexture?) -> MTLTexture? {
        guard isCurrent else { return nil }
        if let texture = factory() { return isCurrent ? texture : nil }
        guard !attemptedRecovery else { return nil }
        attemptedRecovery = true
        guard let revision = cache.reclaimIdleAllocations(
            expectedRevision: expectedRevision, protectedKeys: protectedKeys,
            protectedGenerations: protectedGenerations
        ) else { return nil }
        // The cache returns only a revision after releasing victim references.
        // Never sample a later revision and mistake another mutation for ours.
        expectedRevision = revision
        guard let texture = factory(), isCurrent else { return nil }
        return texture
    }

    func commitSharedPairs(
        _ candidates: [SceneOffscreenTextureAllocationCache.Candidate],
        requiredKeys: Set<SceneOffscreenTextureAllocationCache.Key>
    ) -> Bool {
        guard let revision = cache.commitSharedGraphPairs(candidates,
            requiredKeys: requiredKeys, expectedRevision: expectedRevision) else { return false }
        expectedRevision = revision
        return true
    }
}

struct SceneLayerGraphAllocationReservation {
    let revision: UUID
    let resetEpoch: UUID
    let orderingContext: SceneGraphCommandQueueOrderingContext?
    let historySeed: SceneGraphHistorySeed?
    let cachedAllocation: SceneLayerGraphTargetAllocation?
    let reusableAllocation: SceneLayerGraphTargetAllocation?
    let historySeedGeneration: UInt64?
    let replacedCurrentGeneration: UInt64?
    let consumedRetiredGeneration: UInt64?
    let sharedPair: SceneOffscreenTextureAllocationCache.SharedPair?
}
extension SceneOffscreenTextureAllocationCache {
    func reserveGraphs(
        plans: [SceneLayerGraphTargetPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> [GraphReservation]? {
        locked {
            reserveGraphsLocked(
                plans: plans,
                orderingContext: orderingContext,
                pendingSharedPairs: [:]
            )
        }
    }

    func reserveGraphsLocked(
        plans: [SceneLayerGraphTargetPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext?,
        pendingSharedPairs: [Key: SharedPair]
    ) -> [GraphReservation]? {
        guard !plans.isEmpty,
              Set(plans.map(\.key)).count == plans.count,
              orderingContext?.isPending != false else { return nil }
        var result: [GraphReservation] = []
        for plan in plans {
            guard let reservation = reserveGraphLocked(
                plan: plan,
                orderingContext: orderingContext,
                pendingSharedPairs: pendingSharedPairs, values: residents
            ) else { return nil }
            result.append(reservation)
        }
        return result
    }

    func reserveGraphLocked(
        plan: SceneLayerGraphTargetPlan,
        orderingContext: SceneGraphCommandQueueOrderingContext?,
        pendingSharedPairs: [Key: SharedPair] = [:],
        values: [ResidentKey: Entry]
    ) -> GraphReservation? {
        // A foreign preparation is an actual resident dependency, not ordered GPU work.
        guard !values.values.contains(where: { entry in
            guard !entry.preparationPins.isEmpty else { return false }
            switch entry.allocation {
            case .layerGraph(let graph): return graph.plan.key == plan.key
            case .history(let history): return history.plan.key == plan.key
            default: return false
            }
        }) else { return nil }
        let byteCost = plan.residentByteCost
        let sharedPair: SharedPair?
        if plan.pairStorage == .shared {
            guard let dimensions = plan.sharedPairDimensions else { return nil }
            let key = Key.sharedGraphPair(
                width: dimensions.width, height: dimensions.height
            )
            guard let value = currentSharedPairLocked(for: plan, values: values)
                    ?? pendingSharedPairs[key] else { return nil }
            sharedPair = value
            if let entry = values[.current(value.key)] {
                guard entry.permitsSharedPairReuse(
                    orderingContext: orderingContext
                ) else { return nil }
            } else {
                guard pendingSharedPairs[value.key] != nil else { return nil }
            }
        } else {
            sharedPair = nil
        }
        let current = ResidentKey.current(.layerGraph(plan.key))
        guard byteCost >= 0,
              SceneResolvedMaterialInFlightCapacity.admitsNewSubmission(
                  Array(values.values),
                  graphKey: plan.key
              ) else { return nil }
        let currentEntry = values[current]
        if let currentEntry {
            guard case .layerGraph(let graph) = currentEntry.allocation else {
                return nil
            }
            let pairGenerationMatches = plan.pairStorage == .owned
                || graph.fullFramePairGeneration == sharedPair?.identity.generation
            let idleHit = currentEntry.submissionPins.isEmpty
                && graph.plan == plan && plan.historyEffects.isEmpty
                && pairGenerationMatches
            let orderedHit = currentEntry.permitsOrderedSubmissionReuse(
                for: plan,
                orderingContext: orderingContext
            ) && pairGenerationMatches
            if idleHit || orderedHit {
                return .init(
                    revision: revision,
                    resetEpoch: resetEpoch,
                    orderingContext: orderingContext,
                    historySeed: nil,
                    cachedAllocation: graph,
                    reusableAllocation: nil,
                    historySeedGeneration: nil,
                    replacedCurrentGeneration: nil,
                    consumedRetiredGeneration: nil,
                    sharedPair: sharedPair
                )
            }
        }
        let idle = values.compactMap { key, entry
            -> (key: ResidentKey, entry: Entry,
                graph: SceneLayerGraphTargetAllocation)? in
            guard case .retired = key,
                  !entry.isPinned,
                  !entry.isResetInvalidated,
                  case .layerGraph(let graph) = entry.allocation,
                  graph.plan.key == plan.key else { return nil }
            return (key, entry, graph)
        }.sorted { $0.entry.lastAccess < $1.entry.lastAccess }
        let reusable = idle.first { $0.graph.plan == plan }
        let consumed = reusable ?? idle.first
        var replacingGenerations = Set<UInt64>()
        if let currentEntry, currentEntry.submissionPins.isEmpty {
            replacingGenerations.insert(currentEntry.allocation.generation)
        }
        if let consumed {
            replacingGenerations.insert(consumed.graph.generation)
        }
        guard SceneResolvedMaterialInFlightCapacity.admitsNewAllocation(
            values.values.map(\.allocation),
            graphKey: plan.key,
            replacingGenerations: replacingGenerations
        ) else { return nil }
        var staged = values
        let replaced: Entry?
        if currentEntry?.submissionPins.isEmpty == false {
            replaced = currentEntry
        } else {
            replaced = staged.removeValue(forKey: current)
            if let replaced, let history = replaced.historyOnlyEntry() {
                staged[.history(plan.key, history.allocation.generation)] = history
            }
        }
        if let consumed { staged.removeValue(forKey: consumed.key) }
        let matches = staged.compactMap { key, entry -> (ResidentKey, Entry)? in
            guard case .history(let historyKey, _) = key,
                  historyKey == plan.key,
                  !entry.isResetInvalidated,
                  case .history(let history) = entry.allocation,
                  history.isCompatible(with: plan) else { return nil }
            return (key, entry)
        }
        let pinnedCurrentSeed = replaced.flatMap { entry -> Entry? in
            guard !entry.submissionPins.isEmpty,
                  let history = entry.historyOnlyEntry(),
                  case .history(let value) = history.allocation,
                  value.isCompatible(with: plan) else { return nil }
            return history
        }
        guard pinnedCurrentSeed != nil || matches.count <= 1 else { return nil }
        let seed = pinnedCurrentSeed.map { (current, $0) } ?? matches.first
        var protected = Set<Key>()
        if let sharedPair {
            protected.insert(sharedPair.key)
        }
        guard evictToFit(
            &staged,
            incomingCost: byteCost,
            protected: protected
        ) else { return nil }
        return .init(
            revision: revision,
            resetEpoch: resetEpoch,
            orderingContext: orderingContext,
            historySeed: seed.flatMap {
                guard case .history(let history) = $0.1.allocation else {
                    return nil
                }
                return history.seed
            },
            cachedAllocation: nil,
            reusableAllocation: reusable?.graph,
            historySeedGeneration: seed?.1.allocation.generation,
            replacedCurrentGeneration: replaced?.allocation.generation,
            consumedRetiredGeneration: consumed?.graph.generation,
            sharedPair: sharedPair
        )
    }
    typealias CommitPinRecord = (
        graph: SceneLayerGraphTargetAllocation, submission: UUID,
        history: [EffectKey: UUID], tokens: [EffectKey: Set<Token>],
        sharedPair: (generation: UInt64, submission: UUID)?
    )
    typealias StagedGraphCommit = (residency: Staged, pins: [CommitPinRecord])

    func commitAndPin(
        _ requests: [ScenePreparedPersistentGraphTargets.CommitRequest]
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        locked {
            guard let staged = stageGraphCommitLocked(requests, values: residents)
            else { return nil }
            apply(staged.residency)
            return staged.pins.map(makeCommit)
        }
    }

    /// The only graph commit algorithm. All residency reads use this explicit
    /// view, including reservation refresh, shared pairs, history and capacity.
    /// Caller owns the lock; this method neither applies nor constructs pins.
    func stageGraphCommitLocked(
        _ requests: [ScenePreparedPersistentGraphTargets.CommitRequest],
        values: [ResidentKey: Entry],
        forceReservationRefresh: Bool = false
    ) -> StagedGraphCommit? {
        typealias Effective = (
            request: ScenePreparedPersistentGraphTargets.CommitRequest,
            reservation: GraphReservation,
            graph: SceneLayerGraphTargetAllocation,
            requestedHistory: Set<Token>
        )
        guard !requests.isEmpty,
              Set(requests.map(\.candidate.key)).count == requests.count,
              requests.allSatisfy({ $0.cache === self }) else { return nil }
        var effective: [Effective] = []
        for request in requests {
            let candidate = request.candidate
            let original = request.reservation
            guard original.resetEpoch == resetEpoch,
                  original.orderingContext?.accepts(request.commandBuffer)
                    ?? true,
                  case .layerGraph(let graph) = candidate.allocation,
                  candidate.key == .layerGraph(graph.plan.key),
                  candidate.byteCost == graph.plan.residentByteCost,
                  sharedPairMatches(
                      original.sharedPair,
                      allocation: graph
                  ),
                  let requestedHistory = graph.validatedHistoryTokens(
                      request.historyTokensByEffect,
                      discarding: request.discardedHistoryEffects
                  ) else { return nil }
            let reservation: GraphReservation
            if !forceReservationRefresh && original.revision == revision {
                reservation = original
            } else {
                guard let refreshed = reserveGraphLocked(
                    plan: graph.plan, orderingContext: original.orderingContext,
                    pendingSharedPairs: [:], values: values
                ), reservationStillMatches(original, refreshed) else { return nil }
                reservation = refreshed
            }
            effective.append((request, reservation, graph, requestedHistory))
        }
        var next = values
        var access = accessCounter
        var pinRecords: [CommitPinRecord] = []
        for value in effective {
            let candidate = value.request.candidate
            let reservation = value.reservation
            let graph = value.graph
            let historyTokens = value.request.historyTokensByEffect
            guard reservation.reusableAllocation == nil
                    || reservation.reusableAllocation?.generation
                        == reservation.consumedRetiredGeneration,
                  SceneResolvedMaterialInFlightCapacity.admitsNewSubmission(
                      Array(next.values),
                      graphKey: graph.plan.key
                  ) else { return nil }
            var submissionPins: [UUID: Entry.SubmissionPin] = [:]
            var historyPins: [UUID: Entry.HistoryPin] = [:]
            if let generation = reservation.historySeedGeneration {
                guard next.values.contains(where: { entry in
                    guard !entry.isResetInvalidated,
                          entry.allocation.generation == generation,
                          let seed = entry.historyOnlyEntry(),
                          case .history(let history) = seed.allocation else {
                        return false
                    }
                    return history.isCompatible(with: graph.plan)
                }) else { return nil }
            }
            if !consumeRetired(
                reservation,
                candidate: graph,
                values: &next
            ) { return nil }
            if let generation = reservation.replacedCurrentGeneration {
                let key = ResidentKey.current(candidate.key)
                guard let replaced = next.removeValue(forKey: key),
                      replaced.allocation.generation == generation else {
                    return nil
                }
                if !replaced.submissionPins.isEmpty {
                    let retired = ResidentKey.retired(generation)
                    guard next[retired] == nil else { return nil }
                    next[retired] = replaced
                } else if let history = replaced.historyOnlyEntry() {
                    next[.history(graph.plan.key, generation)] = history
                }
            }
            let existing = next.removeValue(forKey: .current(candidate.key))
            if let cached = reservation.cachedAllocation {
                guard cached.generation == graph.generation,
                      existing?.allocation.generation == graph.generation else {
                    return nil
                }
                if existing?.submissionPins.isEmpty == false {
                    guard historyTokens.isEmpty,
                          existing?.permitsOrderedSubmissionReuse(
                              for: graph.plan,
                              orderingContext: reservation.orderingContext
                          ) == true else { return nil }
                }
                submissionPins = existing?.submissionPins ?? [:]
                historyPins = existing?.historyPins ?? [:]
            } else {
                guard existing == nil,
                      !next.values.contains(where: {
                          $0.allocation.generation == graph.generation
                      }) else { return nil }
            }
            let (nextAccess, overflow) = access.addingReportingOverflow(1)
            guard !overflow else { return nil }
            access = nextAccess
            let submissionID = UUID()
            let historyIDs = Dictionary(uniqueKeysWithValues:
                historyTokens.map { ($0.key, UUID()) }
            )
            let sharedPairPin: (generation: UInt64, submission: UUID)?
            if let sharedPair = reservation.sharedPair {
                let pairKey = ResidentKey.current(sharedPair.key)
                guard var pairEntry = next[pairKey],
                      case .sharedGraphPair(_, let identity) = pairEntry.allocation,
                      identity.generation == sharedPair.identity.generation,
                      pairEntry.permitsSharedPairReuse(
                          orderingContext: reservation.orderingContext
                      ) else {
                    return nil
                }
                let pin = UUID()
                guard pairEntry.submissionPins.updateValue(
                    .init(orderingContext: reservation.orderingContext),
                    forKey: pin
                ) == nil else { return nil }
                next[pairKey] = pairEntry
                sharedPairPin = (identity.generation, pin)
            } else {
                sharedPairPin = nil
            }
            guard submissionPins.updateValue(
                .init(orderingContext: reservation.orderingContext),
                forKey: submissionID
            ) == nil else { return nil }
            var entry = Entry(
                allocation: candidate.allocation,
                byteCost: candidate.byteCost,
                submissionPins: submissionPins,
                historyPins: historyPins,
                lastAccess: access
            )
            for (effect, tokens) in historyTokens {
                guard tokens.isSubset(of: value.requestedHistory),
                      let identity = historyIDs[effect],
                      entry.historyPins.updateValue(
                          .init(effect: effect, tokens: tokens),
                          forKey: identity
                      ) == nil else { return nil }
            }
            next[.current(candidate.key)] = entry
            pinRecords.append((
                graph,
                submissionID,
                historyIDs,
                historyTokens,
                sharedPairPin
            ))
        }
        guard evictToFit(
            &next,
            incomingCost: 0,
            protected: Set(requests.map(\.candidate.key))
        ) else { return nil }
        return ((next, access), pinRecords)
    }
}
