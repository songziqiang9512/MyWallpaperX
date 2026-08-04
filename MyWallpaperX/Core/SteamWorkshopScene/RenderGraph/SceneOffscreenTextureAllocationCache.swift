import Foundation
import Metal

/// Shared byte-accounted residency for legacy offscreen targets and R4 chain
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
    var residentByteCost: Int { locked { cost(residents) ?? Int.max } }

    func preflightChains(
        _ plans: [SceneGraphRenderTargetChainPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil,
        requiredSharedPairKeys: Set<Key> = []
    ) -> SceneOffscreenTextureFramePreflight.Result {
        locked {
            guard orderingContext?.isPending != false else {
                return .rejected(reasonCode: "frame-target-ordering-context-invalid")
            }
            guard
                  plans.allSatisfy({ plan in
                      guard plan.pairStorage == .shared else { return true }
                      guard let dimensions = plan.sharedPairDimensions else {
                          return false
                      }
                      return requiredSharedPairKeys.contains(
                          .pair(width: dimensions.width, height: dimensions.height)
                      )
                  }),
                  requiredSharedPairKeys.allSatisfy({ key in
                      guard case .pair = key,
                            let entry = residents[.current(key)] else {
                          return false
                      }
                      return if case .pair = entry.allocation { true } else { false }
            }) else {
                return .rejected(reasonCode: "frame-target-shared-pair-unavailable")
            }
            let snapshot = residents.enumerated().map { offset, value in
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
                            for: $0, orderingContext: orderingContext
                        )
                    } ?? false,
                    isResetInvalidated: entry.isResetInvalidated,
                    lastAccess: entry.lastAccess,
                    existedBeforeFrame: true,
                    requiredByFrame: requiredByFrame
                )
            }
            for plan in plans where plan.pairStorage == .shared {
                guard let dimensions = plan.sharedPairDimensions,
                      let entry = residents[.current(.pair(
                          width: dimensions.width, height: dimensions.height
                      ))],
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
                byteBudget: byteBudget
            )
        }
    }

    func commit(_ candidates: [Candidate]) -> Bool {
        locked {
            guard let staged = stageLegacy(candidates) else { return false }
            apply(staged)
            return true
        }
    }

    private func stageLegacy(_ candidates: [Candidate]) -> Staged? {
        guard !candidates.isEmpty,
              Set(candidates.map(\.key)).count == candidates.count,
              candidates.allSatisfy({ $0.byteCost >= 0 && $0.keyMatchesAllocation }) else {
            return nil
        }
        var next = residents
        var access = accessCounter
        let protected = Set(candidates.map(\.key))
        for candidate in candidates {
            next.removeValue(forKey: .current(candidate.key))
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
        let victims = values.compactMap { key, entry -> (ResidentKey, Entry)? in
            guard entry.submissionPins.isEmpty,
                  !entry.isResetInvalidated else { return nil }
            switch key {
            case .current(let current) where protected.contains(current): return nil
            case .current, .retired: break
            case .history: return nil
            }
            return (key, entry)
        }.sorted { $0.1.lastAccess < $1.1.lastAccess }
        for victim in victims where total > byteBudget {
            values.removeValue(forKey: victim.0)
            let chainKey: SceneGraphRenderTargetChainPlan.Key? = switch victim.1.allocation {
            case .chain(let chain): chain.plan.key
            case .history(let history): history.plan.key
            default: nil
            }
            if let chainKey, let history = victim.1.historyOnlyEntry() {
                values[.history(chainKey, history.allocation.generation)] = history
                total -= victim.1.byteCost - history.byteCost
            } else {
                total -= victim.1.byteCost
            }
        }
        return total <= byteBudget
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
    typealias ChainReservation = SceneGraphChainAllocationReservation
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
            }) else { return }
            let key = located.key
            var entry = located.value
            entry.submissionPins.removeValue(forKey: identity)
            entry.historyPins.removeValue(forKey: identity)
            residents.removeValue(forKey: key)
            switch key {
            case .current(.chain), .current(.pair):
                residents[key] = entry
            case .history(let chainKey, _):
                if let history = entry.historyOnlyEntry() {
                    residents[.history(chainKey, history.allocation.generation)] = history
                }
            case .retired(let generation):
                if !entry.submissionPins.isEmpty { residents[key] = entry }
                else if let history = entry.historyOnlyEntry() {
                    if entry.isResetInvalidated { residents[key] = history }
                    else if case .history(let value) = history.allocation {
                        residents[.history(value.plan.key, generation)] = history
                    }
                } else if !entry.isResetInvalidated,
                          case .chain = entry.allocation { residents[key] = entry }
            case .current:
                break
            }
            revision = UUID()
        }
    }

    func reset() {
        locked {
            var retained: [ResidentKey: Entry] = [:]
            for entry in residents.values where entry.isPinned {
                var value = !entry.submissionPins.isEmpty
                    ? Optional(entry) : entry.historyOnlyEntry()
                value?.isResetInvalidated = true
                if let value {
                    retained[.retired(value.allocation.generation)] = value
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
        case pair(width: Int, height: Int)
        case authoredPair(width: Int, height: Int)
        case graph(EffectKey)
        case chain(SceneGraphRenderTargetChainPlan.Key)
    }

    enum Allocation {
        case pair(SceneOffscreenTexturePool.Pair, PhysicalIdentity)
        case graph(SceneGraphRenderTargetLease)
        case chain(SceneGraphRenderTargetChainAllocation)
        case history(SceneGraphHistoryResidency)

        var generation: UInt64 {
            switch self {
            case .pair(_, let identity): identity.generation
            case .graph(let lease): lease.generation
            case .chain(let chain): chain.generation
            case .history(let history): history.generation
            }
        }

        var textureCount: Int {
            switch self {
            case .pair: 3
            case .graph(let lease): lease.table.residentTextureCount
            case .chain(let chain): chain.textureCount
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
        var isResetInvalidated = false
        var lastAccess: UInt64
        var isPinned: Bool { !submissionPins.isEmpty || !historyPins.isEmpty }
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
            for plan: SceneGraphRenderTargetChainPlan,
            orderingContext: SceneGraphCommandQueueOrderingContext?
        ) -> Bool {
            guard let orderingContext,
                  !isResetInvalidated,
                  !submissionPins.isEmpty,
                  submissionPins.count
                    < SceneResolvedMaterialInFlightCapacity.maximumSubmissions,
                  historyPins.isEmpty,
                  historyTokens.isEmpty,
                  plan.historyEffects.isEmpty,
                  plan.stages.allSatisfy({ $0.historyClosureIdentities.isEmpty }),
                  case .chain(let chain) = allocation,
                  chain.plan == plan,
                  chain.historyEligibleTokensByEffect.isEmpty,
                  chain.requiredHistoryTokenCountByEffect.isEmpty,
                  chain.texturesBySlot.values.allSatisfy({
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
            let tokens = historyTokens
            guard !tokens.isEmpty else { return nil }
            let history: SceneGraphHistoryResidency?
            switch allocation {
            case .chain(let chain):
                history = chain.historyResidency(
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
        case current(Key)
        case history(SceneGraphRenderTargetChainPlan.Key, UInt64)
        case retired(UInt64)
    }
}
