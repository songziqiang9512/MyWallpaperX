import Foundation

nonisolated struct SceneScriptQuickJSCandidateBoundaryInterruption: Error {}

nonisolated final class SceneScriptQuickJSCandidateControl: @unchecked Sendable {
    private let cancellationCheck: @Sendable () throws -> Void
    private var pendingCancellation: Error?

    init(cancellationCheck: @escaping @Sendable () throws -> Void) {
        self.cancellationCheck = cancellationCheck
    }

    func checkBoundary() throws {
        if let pendingCancellation { throw pendingCancellation }
        try cancellationCheck()
    }

    func checkOwnerBoundary() throws {
        if pendingCancellation != nil {
            throw SceneScriptQuickJSCandidateBoundaryInterruption()
        }
        do {
            try cancellationCheck()
        } catch {
            if pendingCancellation == nil { pendingCancellation = error }
            throw SceneScriptQuickJSCandidateBoundaryInterruption()
        }
    }
}

/// Tracks only owner constructors that actually start. A failed owner can
/// force a fresh domain, but later families that never started are not charged.
nonisolated final class SceneScriptConstructionWorkBudget: @unchecked Sendable {
    private let limit: Int
    private let plannedOwnerUpperBound: Int
    private(set) var consumed = 0
    private(set) var exceeded = false

    init(limit: Int, plannedOwnerUpperBound: Int) {
        self.limit = limit
        self.plannedOwnerUpperBound = plannedOwnerUpperBound
    }

    @discardableResult
    func consume() -> Bool {
        guard consumed < limit else {
            exceeded = true
            return false
        }
        consumed += 1
        return true
    }

    var failure: SceneScriptScalarRuntimeFailure {
        .budgetExceeded(
            "SceneScript candidate aggregate construction work exceeds 4096 "
                + "consumed=\(consumed) limit=\(limit) "
                + "plannedOwnerUpperBound=\(plannedOwnerUpperBound)"
        )
    }
}

nonisolated struct SceneScriptQuickJSProgramConstructionReport: Sendable {
    let expectedVectorTargets: Set<SceneDynamicTarget>
    let instantiatedVectorTargets: Set<SceneDynamicTarget>
    let vectorFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedScalarTargets: Set<SceneDynamicTarget>
    let instantiatedScalarTargets: Set<SceneDynamicTarget>
    let scalarFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedStringTargets: Set<SceneDynamicTarget>
    let instantiatedStringTargets: Set<SceneDynamicTarget>
    let stringFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let expectedCursorLayerIDs: Set<Int>
    let instantiatedCursorLayerIDs: Set<Int>
    let cursorFailures: [Int: SceneScriptScalarRuntimeFailure]

    var isComplete: Bool {
        Self.isComplete(
            expectedVectorTargets,
            instantiatedVectorTargets,
            Set(vectorFailures.keys)
        ) && Self.isComplete(
            expectedScalarTargets,
            instantiatedScalarTargets,
            Set(scalarFailures.keys)
        ) && Self.isComplete(
            expectedStringTargets,
            instantiatedStringTargets,
            Set(stringFailures.keys)
        ) && Self.isComplete(
            expectedCursorLayerIDs,
            instantiatedCursorLayerIDs,
            Set(cursorFailures.keys)
        )
    }

    private static func isComplete<Identity: Hashable>(
        _ expected: Set<Identity>,
        _ instantiated: Set<Identity>,
        _ failed: Set<Identity>
    ) -> Bool {
        instantiated.isDisjoint(with: failed)
            && instantiated.union(failed) == expected
    }
}
