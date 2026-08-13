import Foundation
import Metal

/// Pure whole-frame residency simulation. It mirrors graph replacement,
/// history demotion, the two-generation ceiling, and LRU pressure before any
/// Metal texture is allocated or any capability-owned layer is claimed.
enum SceneOffscreenTextureFramePreflight {
    enum Result: Equatable {
        case ready
        case temporarilyBlocked
        case rejected(reasonCode: String)
    }

    enum Location: Equatable {
        case currentGraph(SceneLayerGraphTargetPlan.Key)
        case currentOther
        case retired
        case history
    }

    struct Resident {
        let id: Int
        var location: Location
        var graphPlan: SceneLayerGraphTargetPlan?
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

        var isFullGraph: Bool { graphPlan != nil }
        var isTransientBlocker: Bool {
            existedBeforeFrame
                && (submissionPinCount > 0 || isResetInvalidated)
        }
    }

    static func evaluate(
        plans: [SceneLayerGraphTargetPlan],
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
        _ plan: SceneLayerGraphTargetPlan,
        values: inout [Resident],
        nextID: Int,
        access: UInt64,
        byteBudget: Int
    ) -> Result? {
        let currentIDs = values.filter {
            $0.location == .currentGraph(plan.key)
        }.map(\.id)
        guard currentIDs.count <= 1 else {
            return .rejected(reasonCode: "frame-target-current-ambiguous")
        }
        let pinCounts = values.compactMap {
            $0.graphPlan?.key == plan.key ? $0.submissionPinCount : nil
        }
        guard SceneResolvedMaterialInFlightCapacity.admitsNewSubmission(pinCounts)
        else { return blocked(values, byteBudget: byteBudget) }
        let currentID = currentIDs.first
        if let currentID, let index = index(of: currentID, in: values),
           values[index].graphPlan == plan, plan.historyEffects.isEmpty,
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
                && $0.graphPlan?.key == plan.key
        }.sorted {
            ($0.lastAccess, $0.id) < ($1.lastAccess, $1.id)
        }
        let reusable = idle.first { $0.graphPlan == plan }
        let consumed = reusable ?? idle.first
        var replacementIDs = Set<Int>()
        if let currentID, let index = index(of: currentID, in: values),
           values[index].submissionPinCount == 0 {
            replacementIDs.insert(currentID)
        }
        if let consumed { replacementIDs.insert(consumed.id) }
        let retainedCount = values.filter {
            $0.isFullGraph && $0.graphPlan?.key == plan.key
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
            location: .currentGraph(plan.key),
            graphPlan: plan,
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
                        || isCurrentGraph($0.location))
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
            if value.requiredByFrame {
                residual.append(value)
                continue
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
        result.graphPlan = nil
        result.history = history
        result.demotedHistory = nil
        result.byteCost = history.byteCost
        result.submissionPinCount = 0
        result.permitsOrderedReuse = false
        result.requiredByFrame = false
        return result
    }

    private static func isCurrentGraph(_ location: Location) -> Bool {
        guard case .currentGraph = location else { return false }
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
