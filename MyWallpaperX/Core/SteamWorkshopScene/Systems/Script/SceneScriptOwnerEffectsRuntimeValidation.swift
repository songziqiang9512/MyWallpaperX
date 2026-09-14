import Foundation

nonisolated struct SceneScriptOwnerEffectsRuntimeFailure: Sendable {
    enum Subsystem: Sendable {
        case animation
        case video
        case textureAnimation
        case puppetBone
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
        textureAnimationRuntime: SceneTextureAnimationPlaybackRuntime,
        videoRegistry: SceneVideoTextureSourceRegistry?,
        timing: SceneFrameTiming
    ) -> [SceneScriptOwnerEffectsRuntimeFailure] {
        var failures: [SceneScriptOwnerEffectsRuntimeFailure] = []
        for owner in effects where !owner.puppetBoneMutations.isEmpty {
            let ownerLayerID: Int? = {
                switch owner.ownerTarget {
                case let .layer(id, _), let .text(id, _), let .particle(id, _),
                     let .effectConstant(id, _, _, _), let .effectVisibility(id, _),
                     let .scriptInstanceProperty(id, _): return id
                default: return nil
                }
            }()
            let valid = ownerLayerID != nil && owner.puppetBoneMutations.allSatisfy {
                $0.layerID == ownerLayerID && $0.boneIndex >= 0 && $0.matrix.count == 16 && $0.matrix.allSatisfy(\.isFinite)
            }
            if !valid {
                failures.append(.init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .puppetBone,
                    commandCount: owner.puppetBoneMutations.count,
                    reason: "invalid Puppet bone mutation identity or matrix"
                ))
            }
        }
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

        let textureAnimationOwners = effects.filter {
            !$0.textureAnimationCommands.isEmpty
        }
        let textureAnimationCommandCount = textureAnimationOwners.reduce(0) {
            $0 + $1.textureAnimationCommands.count
        }
        if textureAnimationCommandCount > 64 {
            failures.append(contentsOf: textureAnimationOwners.map { owner in
                .init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .textureAnimation,
                    commandCount: owner.textureAnimationCommands.count,
                    reason: "frame texture animation command budget exceeded"
                )
            })
        } else {
            for owner in textureAnimationOwners {
                if case let .failure(failure) = textureAnimationRuntime.validate(
                    owner.textureAnimationCommands,
                    sceneTime: timing.sceneTime
                ) {
                    failures.append(.init(
                        ownerTarget: owner.ownerTarget,
                        subsystem: .textureAnimation,
                        commandCount: owner.textureAnimationCommands.count,
                        reason: String(describing: failure)
                    ))
                }
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
