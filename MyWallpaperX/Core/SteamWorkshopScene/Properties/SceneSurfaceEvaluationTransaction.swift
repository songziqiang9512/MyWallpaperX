import Foundation

nonisolated struct SceneSurfaceEvaluationTransaction {
    nonisolated struct PendingEvaluation: Sendable {
        fileprivate let nextGeneration: UInt64
        let snapshot: SceneDynamicSnapshot
        let diagnostics: [SceneDynamicSnapshotDiagnostic]

        var resolution: SceneDynamicSnapshotResolution {
            SceneDynamicSnapshotResolution(
                snapshot: snapshot,
                diagnostics: diagnostics
            )
        }
    }

    private var generation: UInt64 = 0
    private var lastSnapshot: SceneDynamicSnapshot?
    private let resolver = SceneDynamicSnapshotResolver()

    nonisolated init() {}

    /// Values published by the preceding frame for stateful SceneScript
    /// owners.  The accessor is intentionally read-only and target-scoped so
    /// the host can feed callback state forward without exposing or replacing
    /// the transaction's atomic snapshot publication.
    nonisolated func previousValues(
        for targets: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        lastSnapshot?.values(for: targets, source: .sceneScript) ?? [:]
    }

    nonisolated mutating func evaluate(
        frameIndex: UInt64,
        definitions: [SceneDynamicTargetDefinition],
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        evaluate(
            frameIndex: frameIndex,
            index: SceneDynamicSnapshotResolver.prepare(
                definitions: definitions
            ),
            userValues: userValues,
            timelineValues: timelineValues,
            sceneScriptValues: sceneScriptValues
        )
    }

    nonisolated mutating func evaluate(
        frameIndex: UInt64,
        index: SceneDynamicSnapshotDefinitionIndex,
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        let pending = prepare(
            frameIndex: frameIndex,
            index: index,
            userValues: userValues,
            timelineValues: timelineValues,
            sceneScriptValues: sceneScriptValues
        )
        commit(pending)
        return pending.resolution
    }

    /// Resolves a candidate without publishing it. The host commits the
    /// candidate only after every surface has submitted the same frame, so a
    /// drawable/preflight failure cannot become SceneScript `previous-current`.
    nonisolated mutating func prepare(
        frameIndex: UInt64,
        index: SceneDynamicSnapshotDefinitionIndex,
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> PendingEvaluation {
        let resolution = resolver.resolve(
            frameIndex: frameIndex,
            generation: generation,
            index: index,
            userValues: userValues,
            timelineValues: timelineValues,
            sceneScriptValues: sceneScriptValues
        )
        return prepare(frameIndex: frameIndex, resolution: resolution)
    }

    /// Reuses a host-shared typed payload while retaining this surface's own
    /// generation/last-snapshot publication state.
    nonisolated mutating func prepare(
        frameIndex: UInt64,
        resolution: SceneDynamicSnapshotResolution
    ) -> PendingEvaluation {
        let nextGeneration: UInt64
        if let lastSnapshot {
            nextGeneration = lastSnapshot.hasSameValuePayload(as: resolution.snapshot)
                ? generation
                : generation + 1
        } else {
            nextGeneration = resolution.snapshot.count == 0 ? 0 : 1
        }
        let snapshot = resolution.snapshot.replacingIdentity(
            frameIndex: frameIndex,
            generation: nextGeneration
        )

        return PendingEvaluation(
            nextGeneration: nextGeneration,
            snapshot: snapshot,
            diagnostics: resolution.diagnostics
        )
    }

    /// Publishes one previously prepared candidate. This is intentionally a
    /// small value commit owned by the surface transaction; no second state
    /// store or alternate compositor path is introduced.
    nonisolated mutating func commit(_ pending: PendingEvaluation) {
        generation = pending.nextGeneration
        lastSnapshot = pending.snapshot
    }
}
