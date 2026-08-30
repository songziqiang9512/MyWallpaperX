import Foundation

/// Rebuilds the shared VM in fresh domains until a disabled media route no
/// longer discovers an executable media owner. Each iteration removes at least
/// one pass admission or vector target, so authored shared state cannot revive
/// an owner that the launch-frozen route disabled.
nonisolated struct SceneScriptVectorMediaRouteCandidate: @unchecked Sendable {
    let programs: SceneScriptQuickJSProgramCandidate
    let admittedPassTargets: Set<SceneDynamicTarget>
    let mediaOwnerTargets: Set<SceneDynamicTarget>

    static func compile(
        initialPassTargets: Set<SceneDynamicTarget>,
        route: SceneScriptVectorMediaRouteState,
        cancellationCheck: () throws -> Void,
        builder: (
            Set<SceneDynamicTarget>, Set<SceneDynamicTarget>
        ) throws ->
            SceneScriptQuickJSProgramCandidate
    ) throws -> Self? {
        var admitted = initialPassTargets
        var excludedVectorTargets: Set<SceneDynamicTarget> = []
        var mediaTargets: Set<SceneDynamicTarget> = []
        var programs: SceneScriptQuickJSProgramCandidate? = try builder(
            admitted, excludedVectorTargets
        )
        while let candidate = programs {
            mediaTargets.formUnion(candidate.vectorProgram.mediaThumbnailTargets)
            let nextAdmitted = route.admittedVectorPassTargets(
                initialPassTargets, mediaOwnerTargets: mediaTargets
            )
            let nextExcluded = route.excludedVectorOwnerTargets(
                mediaOwnerTargets: mediaTargets
            )
            guard nextAdmitted != admitted
                    || nextExcluded != excludedVectorTargets else { break }
            guard nextAdmitted.isSubset(of: admitted),
                  nextExcluded.isSuperset(of: excludedVectorTargets),
                  nextAdmitted.count < admitted.count
                    || nextExcluded.count > excludedVectorTargets.count else {
                return nil
            }
            programs = nil
            try cancellationCheck()
            admitted = nextAdmitted
            excludedVectorTargets = nextExcluded
            programs = try builder(admitted, excludedVectorTargets)
        }
        guard let programs else { return nil }
        return .init(
            programs: programs,
            admittedPassTargets: admitted,
            mediaOwnerTargets: mediaTargets
        )
    }
}
