import Foundation

/// Rebuilds the shared VM in fresh domains until a disabled media route no
/// longer discovers an executable media owner. Each iteration must remove at
/// least one pass target, so authored shared state cannot revive an owner.
nonisolated struct SceneScriptVectorMediaRouteCandidate: @unchecked Sendable {
    let programs: SceneScriptQuickJSProgramCandidate
    let admittedPassTargets: Set<SceneDynamicTarget>
    let mediaPassTargets: Set<SceneDynamicTarget>

    static func compile(
        initialPassTargets: Set<SceneDynamicTarget>,
        route: SceneScriptVectorMediaRouteState,
        cancellationCheck: () throws -> Void,
        builder: (Set<SceneDynamicTarget>) throws ->
            SceneScriptQuickJSProgramCandidate
    ) throws -> Self? {
        var admitted = initialPassTargets
        var mediaTargets: Set<SceneDynamicTarget> = []
        var programs: SceneScriptQuickJSProgramCandidate? = try builder(admitted)
        while let candidate = programs {
            mediaTargets.formUnion(
                candidate.vectorProgram.mediaThumbnailTargets.intersection(admitted)
            )
            let next = route.admittedVectorPassTargets(
                initialPassTargets, mediaOwnerTargets: mediaTargets
            )
            guard next != admitted else { break }
            guard next.isStrictSubset(of: admitted) else { return nil }
            programs = nil
            try cancellationCheck()
            admitted = next
            programs = try builder(admitted)
        }
        guard let programs else { return nil }
        return .init(
            programs: programs,
            admittedPassTargets: admitted,
            mediaPassTargets: mediaTargets
        )
    }
}
