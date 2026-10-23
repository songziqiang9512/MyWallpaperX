import Foundation

nonisolated private final class Surface {}

@main
nonisolated struct SceneInitialPresentationCohortHarness {
    static func main() throws {
        let a = Surface(), b = Surface(), replacement = Surface(), extra = Surface()
        let ia = ObjectIdentifier(a), ib = ObjectIdentifier(b)
        let ir = ObjectIdentifier(replacement), ix = ObjectIdentifier(extra)
        let members: [UInt32: ObjectIdentifier] = [9: ia, 2: ib]
        let swapped: [UInt32: ObjectIdentifier] = [9: ia, 2: ir]
        var output: [String: Any] = [:]

        do {
            var value = SceneInitialPresentationCohort()
            let token = value.beginAttempt(members: members)!
            let held = value.finishAttempt(token: token, qualifiedSubmitted: members)
            let first = value.complete(token: token, surface: 9, identity: ia)
            let duplicate = value.complete(token: token, surface: 9, identity: ia)
            let delivery = value.complete(token: token, surface: 2, identity: ib)
            let redelivery = value.complete(token: token, surface: 2, identity: ib)
            output["sameAttempt"] = ["held": held, "partialDelivered": first != nil,
                "duplicateDelivered": duplicate != nil, "delivery": delivery ?? [],
                "redelivered": redelivery != nil, "heldAfterDelivery": value.isHeld,
                "newAttemptBlocked": value.beginAttempt(members: swapped) == nil,
                "heldAfterBlockedAttempt": value.isHeld]
        }

        do {
            var results: [String: Bool] = [:]
            let submissions: [(String, [UInt32: ObjectIdentifier])] = [
                ("missing", [9: ia]), ("none", [:]), ("replacement", swapped),
                ("extra", [9: ia, 2: ib, 20: ix]), ("wrongIDs", [9: ia, 3: ib])]
            for (name, submitted) in submissions {
                var value = SceneInitialPresentationCohort()
                let token = value.beginAttempt(members: members)!
                _ = value.complete(token: token, surface: 9, identity: ia)
                let held = value.finishAttempt(token: token, qualifiedSubmitted: submitted)
                let late = value.complete(token: token, surface: 2, identity: ib)
                results[name] = held || value.isHeld || late != nil
            }
            var empty = SceneInitialPresentationCohort()
            let token = empty.beginAttempt(members: [:])!
            results["empty"] = empty.finishAttempt(token: token, qualifiedSubmitted: [:])
                || empty.takeCompletedCohort() != nil || empty.isHeld
            output["invalidSubmissions"] = results
        }

        do {
            var value = SceneInitialPresentationCohort()
            let old = value.beginAttempt(members: members)!
            _ = value.complete(token: old, surface: 9, identity: ia)
            let oldHeld = value.finishAttempt(token: old, qualifiedSubmitted: [9: ia])
            let newer = value.beginAttempt(members: members)!
            _ = value.complete(token: newer, surface: 2, identity: ib)
            let newerHeld = value.finishAttempt(token: newer, qualifiedSubmitted: [2: ib])
            let crossed = value.takeCompletedCohort()
            let current = value.beginAttempt(members: members)!
            let currentHeld = value.finishAttempt(token: current, qualifiedSubmitted: members)
            let staleA = value.complete(token: old, surface: 9, identity: ia)
            let staleB = value.complete(token: newer, surface: 2, identity: ib)
            let bOnly = value.complete(token: current, surface: 2, identity: ib)
            let delivery = value.complete(token: current, surface: 9, identity: ia)
            output["noCrossAttemptUnion"] = ["oldHeld": oldHeld, "newerHeld": newerHeld,
                "crossedDelivered": crossed != nil, "currentHeld": currentHeld,
                "staleADelivered": staleA != nil, "staleBDelivered": staleB != nil,
                "currentBOnlyDelivered": bOnly != nil, "delivery": delivery ?? [],
                "tokensIncrease": old.rawValue < newer.rawValue && newer.rawValue < current.rawValue]
        }

        do {
            var value = SceneInitialPresentationCohort()
            let token = value.beginAttempt(members: members)!
            let earlyA = value.complete(token: token, surface: 9, identity: ia)
            let earlyB = value.complete(token: token, surface: 2, identity: ib)
            let beforeSeal = value.takeCompletedCohort()
            let held = value.finishAttempt(token: token, qualifiedSubmitted: members)
            let delivery = value.takeCompletedCohort()
            let duplicate = value.takeCompletedCohort()
            output["completionBeforeSeal"] = ["earlyADelivered": earlyA != nil,
                "earlyBDelivered": earlyB != nil, "beforeSealDelivered": beforeSeal != nil,
                "held": held, "delivery": delivery ?? [], "redelivered": duplicate != nil,
                "stillHeld": value.isHeld]
        }

        do {
            var value = SceneInitialPresentationCohort()
            let old = value.beginAttempt(members: members)!
            _ = value.complete(token: old, surface: 9, identity: ia)
            let current = value.beginAttempt(members: swapped)!
            let held = value.finishAttempt(token: current, qualifiedSubmitted: swapped)
            let wrongObject = value.complete(token: current, surface: 2, identity: ib)
            let staleOld = value.complete(token: old, surface: 2, identity: ib)
            let unknownScreen = value.complete(token: current, surface: 20, identity: ix)
            let replacementOnly = value.complete(token: current, surface: 2, identity: ir)
            let delivery = value.complete(token: current, surface: 9, identity: ia)
            output["surfaceReplacement"] = ["held": held,
                "wrongObjectDelivered": wrongObject != nil, "staleOldDelivered": staleOld != nil,
                "unknownScreenDelivered": unknownScreen != nil,
                "replacementOnlyDelivered": replacementOnly != nil, "delivery": delivery ?? []]
        }

        do {
            var value = SceneInitialPresentationCohort()
            let old = value.beginAttempt(members: members)!
            _ = value.finishAttempt(token: old, qualifiedSubmitted: members)
            _ = value.complete(token: old, surface: 9, identity: ia)
            value.invalidate()
            let heldAfterInvalidate = value.isHeld
            let staleAfterInvalidate = value.complete(token: old, surface: 2, identity: ib)
            let current = value.beginAttempt(members: swapped)!
            _ = value.finishAttempt(token: current, qualifiedSubmitted: swapped)
            _ = value.complete(token: current, surface: 9, identity: ia)
            let delivery = value.complete(token: current, surface: 2, identity: ir)
            let heldAfterDelivery = value.isHeld
            value.reset()
            let heldAfterReset = value.isHeld
            let staleAfterReset = value.complete(token: current, surface: 2, identity: ir)
            let afterReset = value.beginAttempt(members: [2: ir])!
            _ = value.finishAttempt(token: afterReset, qualifiedSubmitted: [2: ir])
            let nextDelivery = value.complete(token: afterReset, surface: 2, identity: ir)
            output["releaseAndReset"] = ["heldAfterInvalidate": heldAfterInvalidate,
                "staleAfterInvalidateDelivered": staleAfterInvalidate != nil,
                "delivery": delivery ?? [], "heldAfterDelivery": heldAfterDelivery,
                "heldAfterReset": heldAfterReset, "staleAfterResetDelivered": staleAfterReset != nil,
                "tokensIncrease": old.rawValue < current.rawValue && current.rawValue < afterReset.rawValue,
                "nextDelivery": nextDelivery ?? []]
        }

        do {
            var value = SceneInitialPresentationCohort()
            let old = value.beginAttempt(members: members)!
            let current = value.beginAttempt(members: swapped)!
            let staleSeal = value.finishAttempt(token: old, qualifiedSubmitted: members)
            let held = value.finishAttempt(token: current, qualifiedSubmitted: swapped)
            let reseal = value.finishAttempt(token: current, qualifiedSubmitted: [:])
            _ = value.complete(token: current, surface: 9, identity: ia)
            let delivery = value.complete(token: current, surface: 2, identity: ir)
            output["staleAndRepeatedSeal"] = ["staleSealHeld": staleSeal, "held": held,
                "repeatedSealPreservedHold": reseal && value.isHeld, "delivery": delivery ?? []]
        }

        do {
            var value = SceneInitialPresentationCohort()
            var phases = [value.hasDelivered]
            let token = value.beginAttempt(members: members)!
            phases.append(value.hasDelivered)
            _ = value.finishAttempt(token: token, qualifiedSubmitted: members)
            phases.append(value.hasDelivered)
            _ = value.complete(token: token, surface: 9, identity: ia)
            phases.append(value.hasDelivered)
            _ = value.complete(token: token, surface: 2, identity: ib)
            phases.append(value.hasDelivered)
            value.invalidate()
            phases.append(value.hasDelivered)
            let stale = value.complete(token: token, surface: 9, identity: ia)
            phases.append(value.hasDelivered)
            let replacementToken = value.beginAttempt(members: [2: ir])!
            _ = value.finishAttempt(token: replacementToken, qualifiedSubmitted: [2: ir])
            _ = value.complete(token: replacementToken, surface: 2, identity: ir)
            phases.append(value.hasDelivered)
            value.reset()
            phases.append(value.hasDelivered)
            output["deliveredPhase"] = ["phases": phases, "staleDelivered": stale != nil,
                "heldAfterReset": value.isHeld]
        }

        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        withExtendedLifetime((a, b, replacement, extra)) {}
    }
}
