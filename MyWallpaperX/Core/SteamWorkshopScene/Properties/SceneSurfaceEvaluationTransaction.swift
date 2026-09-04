import Foundation

nonisolated struct SceneSurfaceEvaluationTransaction {
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
        let resolution = resolver.resolve(
            frameIndex: frameIndex,
            generation: generation,
            index: index,
            userValues: userValues,
            timelineValues: timelineValues,
            sceneScriptValues: sceneScriptValues
        )
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

        generation = nextGeneration
        lastSnapshot = snapshot
        return SceneDynamicSnapshotResolution(
            snapshot: snapshot,
            diagnostics: resolution.diagnostics
        )
    }
}
