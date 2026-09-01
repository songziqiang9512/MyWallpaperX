import Foundation

nonisolated struct SceneScriptOwnerEffectsRuntimeFailure: Sendable {
    enum Subsystem: Sendable {
        case animation
        case video
    }

    let ownerTarget: SceneDynamicTarget
    let subsystem: Subsystem
    let commandCount: Int
    let reason: String
}

/// Side-effect-free validation for the non-layer parts of one SceneScript
/// owner transaction. Layer admission drives the fixed-point loop; these
/// results only decide which complete owner bundles must be removed.
nonisolated enum SceneScriptOwnerEffectsRuntimeValidation {
    static func failures(
        for effects: [SceneScriptOwnerEffects],
        timelineRuntime: SceneTimelinePlaybackRuntime,
        videoRegistry: SceneVideoTextureSourceRegistry?,
        timing: SceneFrameTiming
    ) -> [SceneScriptOwnerEffectsRuntimeFailure] {
        var failures: [SceneScriptOwnerEffectsRuntimeFailure] = []
        for owner in effects where !owner.animationMutations.isEmpty {
            if case let .failure(failure) = timelineRuntime.validate(
                owner.animationMutations,
                sceneTime: timing.sceneTime
            ) {
                failures.append(.init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .animation,
                    commandCount: owner.animationMutations.count,
                    reason: String(describing: failure)
                ))
            }
        }

        let videoOwners = effects.filter { !$0.videoCommands.isEmpty }
        let videoCommandCount = videoOwners.reduce(0) {
            $0 + $1.videoCommands.count
        }
        if videoCommandCount > 64 {
            failures.append(contentsOf: videoOwners.map { owner in
                .init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .video,
                    commandCount: owner.videoCommands.count,
                    reason: "frame video command budget exceeded"
                )
            })
            return failures
        }
        for owner in videoOwners {
            guard let videoRegistry else {
                failures.append(.init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .video,
                    commandCount: owner.videoCommands.count,
                    reason: "registry unavailable"
                ))
                continue
            }
            if case let .failure(failure) = videoRegistry.validate(
                owner.videoCommands,
                timing: timing
            ) {
                failures.append(.init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .video,
                    commandCount: owner.videoCommands.count,
                    reason: String(describing: failure)
                ))
            }
        }
        return failures
    }
}
