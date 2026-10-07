import Foundation
import Metal

/// Shared byte-accounted residency for graph target tables and ordered layer graphs
/// transactions. R4 history entries retain only dynamically mapped tokens.
final class SceneOffscreenTextureAllocationCache {
    private let byteBudget: Int
    let lock = NSLock()
    private let identityIssuer = SceneOffscreenTextureIdentityIssuer()
    var residents: [ResidentKey: Entry] = [:]
    var accessCounter: UInt64 = 0
    var revision = UUID()
    var resetEpoch = UUID()

    init(byteBudget: Int) { self.byteBudget = max(byteBudget, 0) }

    func issuePhysicalIdentity(textures: [MTLTexture]) -> PhysicalIdentity? {
        identityIssuer.issue(textures: textures)
    }

    func issueAllocationGeneration() -> UInt64? {
        identityIssuer.issueGeneration()
    }
    var residentByteCost: Int { locked { cost(residents) ?? Int.max } }
    var preflightByteBudget: Int { byteBudget }

    func commit(_ candidates: [Candidate]) -> Bool {
        locked {
            guard let staged = stageCandidates(candidates) else { return false }
            apply(staged)
            return true
        }
    }

    func commitSharedGraphPairs(
        _ candidates: [Candidate],
        requiredKeys: Set<Key>
    ) -> Bool {
        locked { commitSharedGraphPairsLocked(candidates, requiredKeys: requiredKeys) }
    }

    func commitSharedGraphPairs(
        _ candidates: [Candidate],
        requiredKeys: Set<Key>,
        expectedResetEpoch: UUID,
        expectedGenerations: [Key: UInt64]
    ) -> UUID? {
        locked {
            // Successful allocation can overlap GPU completion. Verify the exact
            // pair state instead of a revision that also changes on pin release.
            // Never replace a pair published since the batch's snapshot.
            guard resetEpoch == expectedResetEpoch,
                  requiredKeys.allSatisfy({ key in
                      let entry = residents[.current(key)]
                      guard let generation = expectedGenerations[key] else {
                          return entry == nil
                      }
                      guard let entry, !entry.isResetInvalidated,
                            case .sharedGraphPair = entry.allocation else { return false }
                      return entry.allocation.generation == generation
                  }), candidates.allSatisfy({ expectedGenerations[$0.key] == nil }),
                  commitSharedGraphPairsLocked(candidates, requiredKeys: requiredKeys)
            else { return nil }
            return revision
        }
    }

    private func commitSharedGraphPairsLocked(
        _ candidates: [Candidate], requiredKeys: Set<Key>
    ) -> Bool {
        let candidateKeys = Set(candidates.map(\.key))
        guard !requiredKeys.isEmpty,
              candidateKeys.count == candidates.count,
              candidateKeys.isSubset(of: requiredKeys),
              requiredKeys.allSatisfy({ key in
                  guard case .sharedGraphPair = key else { return false }
                  if candidateKeys.contains(key) { return true }
                  guard let entry = residents[.current(key)],
                        !entry.isResetInvalidated,
                        case .sharedGraphPair = entry.allocation else {
                      return false
                  }
                  return true
              }), candidates.allSatisfy({ candidate in
                  guard case .sharedGraphPair = candidate.key,
                        case .sharedGraphPair = candidate.allocation else {
                      return false
                  }
                  return candidate.keyMatchesAllocation
              }) else { return false }
        guard !candidates.isEmpty else { return true }
        guard let staged = stageCandidates(candidates, protectedKeys: requiredKeys)
        else { return false }
        apply(staged)
        return true
    }

    func stageCandidates(
        _ candidates: [Candidate],
        protectedKeys: Set<Key> = []
    ) -> Staged? {
        guard !candidates.isEmpty,
              Set(candidates.map(\.key)).count == candidates.count,
              candidates.allSatisfy({ $0.byteCost >= 0 && $0.keyMatchesAllocation }) else {
            return nil
        }
        var next = residents
        var access = accessCounter
        let protected = Set(candidates.map(\.key)).union(protectedKeys)
        for candidate in candidates {
            guard next[.current(candidate.key)]?.preparationPins.isEmpty != false else { return nil }
            let previous = next.removeValue(forKey: .current(candidate.key))
            if candidate.key.retainsReplacedSubmission,
               let previous, previous.isPinned {
                next[.retired(previous.allocation.generation)] = previous
            }
            guard !next.values.contains(where: {
                $0.allocation.generation == candidate.allocation.generation
            }) else { return nil }
            let (nextAccess, overflow) = access.addingReportingOverflow(1)
            guard !overflow else { return nil }
            access = nextAccess
            next[.current(candidate.key)] = .init(
                allocation: candidate.allocation,
                byteCost: candidate.byteCost,
                lastAccess: access
            )
        }
        guard evictToFit(&next, incomingCost: 0, protected: protected) else { return nil }
        return (next, access)
    }

    func evictToFit(
        _ values: inout [ResidentKey: Entry],
        incomingCost: Int,
        protected: Set<Key> = []
    ) -> Bool {
        guard let base = cost(values) else { return false }
        let (initial, overflow) = base.addingReportingOverflow(incomingCost)
        guard !overflow else { return false }
        var total = initial
        let victims = evictionVictims(in: values, protectedKeys: protected,
                                     protectedGenerations: [])
        for victim in victims where total > byteBudget {
            total -= evictVictim(victim, from: &values)
        }
        return total <= byteBudget
    }

    /// Reclaims rebuildable residency only after a real allocation failed.
    /// Resource leases release physical quota when their textures deinitialize.
    func reclaimIdleAllocations(
        expectedRevision: UUID, protectedKeys: Set<Key>,
        protectedGenerations: Set<UInt64> = []
    ) -> UUID? {
        autoreleasepool {
            locked {
                guard revision == expectedRevision else { return nil }
                let victims = evictionVictims(in: residents, protectedKeys: protectedKeys,
                                             protectedGenerations: protectedGenerations)
                guard !victims.isEmpty else { return nil }
                for victim in victims { _ = evictVictim(victim, from: &residents) }
                revision = UUID()
                return revision
            }
        }
    }

    private func evictionVictims(
        in values: [ResidentKey: Entry], protectedKeys: Set<Key>,
        protectedGenerations: Set<UInt64>
    ) -> [ResidentKey] {
        values.compactMap { key, entry -> (ResidentKey, UInt64)? in
            guard entry.preparationPins.isEmpty, entry.submissionPins.isEmpty,
                  !entry.isResetInvalidated, entry.sceneColorPins.isEmpty,
                  !protectedGenerations.contains(entry.allocation.generation)
            else { return nil }
            switch key {
            case .current(let current) where protectedKeys.contains(current): return nil
            case .current, .retired: break
            case .history, .pending: return nil
            }
            return (key, entry.lastAccess)
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    /// Both logical eviction and allocation recovery preserve the same history
    /// closure. Return only scalar cost; never retain a removed Entry in a plan.
    private func evictVictim(
        _ key: ResidentKey, from values: inout [ResidentKey: Entry]
    ) -> Int {
        guard let victim = values.removeValue(forKey: key) else { return 0 }
        let graphKey: SceneLayerGraphTargetPlan.Key? = switch victim.allocation {
        case .layerGraph(let graph): graph.plan.key
        case .history(let history): history.plan.key
        default: nil
        }
        if let graphKey, let history = victim.historyOnlyEntry() {
            values[.history(graphKey, history.allocation.generation)] = history
            return victim.byteCost - history.byteCost
        }
        return victim.byteCost
    }

    private func cost(_ values: [ResidentKey: Entry]) -> Int? {
        var total = 0
        for entry in values.values {
            let (next, overflow) = total.addingReportingOverflow(entry.byteCost)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}

extension SceneOffscreenTextureAllocationCache {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    typealias PhysicalIdentity = SceneOffscreenTexturePhysicalIdentity
    typealias Candidate = SceneOffscreenTextureAllocationCandidate
    typealias GraphReservation = SceneLayerGraphAllocationReservation
    typealias Staged = (values: [ResidentKey: Entry], access: UInt64)

    var residentAllocationCount: Int { locked { residents.count } }
    func allocation(for key: Key) -> Allocation? {
        locked { residents[.current(key)]?.allocation }
    }

    func apply(_ staged: Staged) {
        (residents, accessCounter, revision) = (staged.values, staged.access, UUID())
    }

    func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func releasePin(identity: UUID) {
        locked {
            guard let located = residents.first(where: {
                $0.value.submissionPins[identity] != nil
                    || $0.value.historyPins[identity] != nil
                    || $0.value.sceneColorPins.contains(identity)
            }) else { return }
            let key = located.key
            var entry = located.value
            entry.submissionPins.removeValue(forKey: identity)
            entry.historyPins.removeValue(forKey: identity)
            entry.sceneColorPins.remove(identity)
            residents.removeValue(forKey: key)
            storeAfterPinRelease(entry, key: key, into: &residents)
            revision = UUID()
        }
    }

    // Caller holds the cache lock. Preparation protects full storage even after
    // an external submission/history pin releases; it never fabricates history.
    func storeAfterPinRelease(_ entry: Entry, key: ResidentKey,
                              into values: inout [ResidentKey: Entry]) {
        if !entry.preparationPins.isEmpty { values[key] = entry; return }
        switch key {
            case .current(.layerGraph), .current(.sharedGraphPair), .current(.sceneColor),
                 .current(.composition), .current(.compositionGroup), .current(.environment),
                 .current(.modelShadow), .current(.puppetClipping):
                values[key] = entry
            case .history(let graphKey, _):
                if let history = entry.historyOnlyEntry() {
                    values[.history(graphKey, history.allocation.generation)] = history
                }
            case .retired(let generation):
                if !entry.submissionPins.isEmpty { values[key] = entry }
                else if case .sceneColor = entry.allocation, !entry.sceneColorPins.isEmpty {
                    values[key] = entry
                } else if let history = entry.historyOnlyEntry() {
                    if entry.isResetInvalidated { values[key] = history }
                    else if case .history(let value) = history.allocation {
                        values[.history(value.plan.key, generation)] = history
                    }
                } else if !entry.isResetInvalidated,
                          case .layerGraph = entry.allocation { values[key] = entry }
            case .current, .pending:
                break
            }
    }

    func reset() {
        locked {
            var retained: [ResidentKey: Entry] = [:]
            for (key, entry) in residents where entry.isPinned {
                var value = !entry.preparationPins.isEmpty || !entry.submissionPins.isEmpty
                    ? Optional(entry) : entry.historyOnlyEntry()
                value?.isResetInvalidated = true
                if let value {
                    if case .pending = key { retained[key] = value }
                    else { retained[.retired(value.allocation.generation)] = value }
                }
            }
            residents = retained
            accessCounter = 0
            revision = UUID()
            resetEpoch = UUID()
        }
    }
}

extension SceneOffscreenTextureAllocationCache {
    var residentTextureCount: Int {
        locked { residents.values.reduce(0) { $0 + $1.allocation.textureCount } }
    }

    nonisolated enum Key: Hashable {
        case composition(width: Int, height: Int)
        case environment(width: Int, height: Int)
        case modelShadow(slot: Int, width: Int, height: Int)
        case puppetClipping(layerID: Int, clipID: Int, domain: UUID, width: Int, height: Int)

        var retainsReplacedSubmission: Bool {
            switch self {
            case .composition, .compositionGroup, .environment, .modelShadow, .puppetClipping: true
            default: false
            }
        }
        case sceneColor(width: Int, height: Int, pixelFormat: MTLPixelFormat,
                        intent: SceneOffscreenTexturePool.SceneColorIntent)
        /// D1 composition-group target: one isolated allocation per logical
        /// group and extent, so simultaneous groups never share storage the
        /// way the neutral composition copy target may.
        case compositionGroup(layerID: Int, width: Int, height: Int)
        case sharedGraphPair(width: Int, height: Int)
        case graph(EffectKey)
        case layerGraph(SceneLayerGraphTargetPlan.Key)
    }

    enum Allocation {
        case composition(MTLTexture, PhysicalIdentity)
        case sceneColor(SceneOffscreenTexturePool.SceneColorTargets)
        case sharedGraphPair(
            SceneOffscreenTexturePool.SharedGraphPair,
            PhysicalIdentity
        )
        case graph(SceneGraphRenderTargetLease)
        case layerGraph(SceneLayerGraphTargetAllocation)
        case history(SceneGraphHistoryResidency)

        var generation: UInt64 {
            switch self {
            case .composition(_, let identity): identity.generation
            case .sceneColor(let targets): targets.identity.generation
            case .sharedGraphPair(_, let identity): identity.generation
            case .graph(let lease): lease.generation
            case .layerGraph(let graph): graph.generation
            case .history(let history): history.generation
            }
        }

        var textureCount: Int {
            switch self {
            case .composition: 1
            case .sceneColor(let targets): targets.display == nil ? 2 : 3
            case .sharedGraphPair: 2
            case .graph(let lease): lease.table.residentTextureCount
            case .layerGraph(let graph): graph.textureCount
            case .history(let history): history.textureCount
            }
        }
    }

    struct Entry {
        struct SubmissionPin {
            let orderingContext: SceneGraphCommandQueueOrderingContext?
        }
        struct HistoryPin {
            let effect: EffectKey
            let tokens: Set<Token>
        }

        var allocation: Allocation
        var byteCost: Int
        var submissionPins: [UUID: SubmissionPin] = [:]
        var historyPins: [UUID: HistoryPin] = [:]
        var sceneColorPins: Set<UUID> = []
        var preparationPins: Set<UUID> = []
        var isResetInvalidated = false
        var lastAccess: UInt64
        var isPinned: Bool { !preparationPins.isEmpty || !submissionPins.isEmpty || !historyPins.isEmpty || !sceneColorPins.isEmpty }
        var historyTokens: Set<Token> {
            historyPins.values.reduce(into: Set<Token>()) {
                $0.formUnion($1.tokens)
            }
        }
        var historyTokensByEffect: [EffectKey: Set<Token>] {
            historyPins.values.reduce(into: [:]) { result, pin in
                result[pin.effect, default: []].formUnion(pin.tokens)
            }
        }

        func permitsOrderedSubmissionReuse(
            for plan: SceneLayerGraphTargetPlan,
            orderingContext: SceneGraphCommandQueueOrderingContext?
        ) -> Bool {
            guard let orderingContext,
                  preparationPins.isEmpty, !isResetInvalidated,
                  !submissionPins.isEmpty,
                  submissionPins.count
                    < SceneResolvedMaterialInFlightCapacity.maximumSubmissions,
                  historyPins.isEmpty,
                  historyTokens.isEmpty,
                  plan.historyEffects.isEmpty,
                  plan.stages.allSatisfy({ $0.historyClosureIdentities.isEmpty }),
                  case .layerGraph(let graph) = allocation,
                  graph.plan == plan,
                  graph.historyEligibleTokensByEffect.isEmpty,
                  graph.requiredHistoryTokenCountByEffect.isEmpty,
                  graph.texturesBySlot.values.allSatisfy({
                      $0.hazardTrackingMode != .untracked
                  }) else { return false }
            return submissionPins.values.allSatisfy { pin in
                guard let prior = pin.orderingContext else { return false }
                let current = orderingContext.commandBuffer
                let previous = prior.commandBuffer
                return current.status == .notEnqueued
                    && current !== previous
                    && ObjectIdentifier(current.commandQueue)
                        == ObjectIdentifier(previous.commandQueue)
                    && previous.status != .notEnqueued
            }
        }

        func historyOnlyEntry() -> Self? {
            if case .sceneColor = allocation, !sceneColorPins.isEmpty { return self }
            let tokens = historyTokens
            guard !tokens.isEmpty else { return nil }
            let history: SceneGraphHistoryResidency?
            switch allocation {
            case .layerGraph(let graph):
                history = graph.historyResidency(
                    tokensByEffect: historyTokensByEffect
                )
            case .history(let current):
                history = current.retaining(tokens: tokens)
            default:
                history = nil
            }
            guard let history else { return nil }
            var result = self
            result.allocation = .history(history)
            result.byteCost = history.byteCost
            return result
        }
    }

    enum ResidentKey: Hashable {
        case pending(UUID, SceneLayerGraphTargetPlan.Key)
        case current(Key)
        case history(SceneLayerGraphTargetPlan.Key, UInt64)
        case retired(UInt64)
    }
}

extension SceneOffscreenTextureAllocationCache {
    func consumeRetired(
        _ reservation: GraphReservation,
        candidate: SceneLayerGraphTargetAllocation,
        values: inout [ResidentKey: Entry]
    ) -> Bool {
        guard let generation = reservation.consumedRetiredGeneration else {
            return reservation.reusableAllocation == nil
        }
        let key = ResidentKey.retired(generation)
        guard let retired = values.removeValue(forKey: key),
              !retired.isPinned,
              !retired.isResetInvalidated,
              case .layerGraph(let old) = retired.allocation,
              old.generation == generation,
              old.plan.key == candidate.plan.key else { return false }
        guard let reusable = reservation.reusableAllocation else { return true }
        return reusable.generation == generation
            && candidate.generation != generation
            && reusable.plan == candidate.plan
            && old.plan == reusable.plan
            && old.plan.slots
                .filter { slot in
                    if case .fullFrame = slot.kind { return false }
                    return true
                }
                .allSatisfy { slot in
                    old.texturesBySlot[slot.id]
                        === candidate.texturesBySlot[slot.id]
                }
    }
}
