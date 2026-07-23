import Foundation

nonisolated struct SceneSurfaceEvaluationTransaction {
    private var generation: UInt64 = 0
    private var lastSnapshot: SceneDynamicSnapshot?
    private let resolver = SceneDynamicSnapshotResolver()

    nonisolated init() {}

    nonisolated mutating func evaluate(
        frameIndex: UInt64,
        definitions: [SceneDynamicTargetDefinition],
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        let resolution = resolver.resolve(
            frameIndex: frameIndex,
            generation: generation,
            definitions: definitions,
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
