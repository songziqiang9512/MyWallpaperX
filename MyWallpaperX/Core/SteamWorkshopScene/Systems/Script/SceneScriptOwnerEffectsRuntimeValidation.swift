import Foundation

nonisolated struct SceneScriptOwnerEffectsRuntimeFailure: Sendable {
    enum Subsystem: String, Sendable {
        case animation = "animationCommands"
        case mediaPlayback = "mediaPlaybackCommands"
        case textureAnimation = "textureAnimationCommands"
        case puppetBone = "puppetBoneMutations"
        case puppetAnimation = "puppetAnimationCommands"
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
    @MainActor static func failures(
        for effects: [SceneScriptOwnerEffects],
        timelineRuntime: SceneTimelinePlaybackRuntime,
        textureAnimationRuntime: SceneTextureAnimationPlaybackRuntime,
        videoRegistry: SceneVideoTextureSourceRegistry?,
        soundRegistry: SceneSoundPlaybackRegistry? = nil,
        timing: SceneFrameTiming,
        puppetAnimationRuntime: ScenePuppetAnimationPlaybackRuntime? = nil
    ) -> [SceneScriptOwnerEffectsRuntimeFailure] {
        var failures: [SceneScriptOwnerEffectsRuntimeFailure] = []
        let puppetOwners = effects.filter {
            !$0.puppetAnimationCommands.isEmpty || $0.puppetAnimationCallbackRegistrations != 0
        }
        let puppetCommandCount = puppetOwners.reduce(0) {
            $0 + $1.puppetAnimationCommands.count + $1.puppetAnimationCallbackRegistrations
        }
        for owner in puppetOwners {
            let reason: String?
            if owner.puppetAnimationCallbackRegistrations < 0 {
                reason = "invalid Puppet animation callback registration count"
            } else if puppetCommandCount > 64 {
                reason = "frame Puppet animation command budget exceeded"
            } else if let puppetAnimationRuntime {
                if let source = ScenePuppetAnimationPropertyTarget.source(for: owner.ownerTarget) {
                    switch puppetAnimationRuntime.validate(
                        owner.puppetAnimationCommands, sourceLayerID: source.layerID,
                        sourceAnimationLayerID: source.animationLayerID, frameIndex: timing.frameIndex
                    ) {
                    case .success: reason = nil
                    case let .failure(failure): reason = String(describing: failure)
                    }
                } else {
                    reason = "Puppet animation controls require a prepared nested owner"
                }
            } else { reason = "Puppet animation runtime unavailable" }
            if let reason {
                failures.append(.init(ownerTarget: owner.ownerTarget, subsystem: .puppetAnimation,
                    commandCount: owner.puppetAnimationCommands.count
                        + owner.puppetAnimationCallbackRegistrations, reason: reason))
            }
        }
        for owner in effects where !owner.puppetBoneMutations.isEmpty {
            let ownerLayerID: Int? = {
                switch owner.ownerTarget {
                case .camera(.origin): return owner.sourceLayerID
                case let .layer(id, _), let .text(id, _), let .particle(id, _),
                     let .effectConstant(id, _, _, _), let .effectVisibility(id, _),
                     let .scriptInstanceProperty(id, _): return id
                default: return nil
                }
            }()
            let valid = ownerLayerID != nil && owner.puppetBoneMutations.allSatisfy {
                guard $0.layerID == ownerLayerID && $0.boneIndex >= 0 else { return false }
                switch $0.operation {
                case let .matrix(matrix): return matrix.count == 16 && matrix.allSatisfy { Float($0).isFinite }
                case let .impulse(value):
                    let vector = SIMD3<Float>(value)
                    return vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
                }
            }
            if !valid {
                failures.append(.init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .puppetBone,
                    commandCount: owner.puppetBoneMutations.count,
                    reason: "invalid Puppet bone mutation identity or payload"
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

        let mediaOwners = effects.filter { !$0.mediaPlaybackCommands.isEmpty }
        let mediaCommandCount = mediaOwners.reduce(0) {
            $0 + $1.mediaPlaybackCommands.count
        }
        if mediaCommandCount > 64 {
            failures.append(contentsOf: mediaOwners.map { owner in
                .init(
                    ownerTarget: owner.ownerTarget,
                    subsystem: .mediaPlayback,
                    commandCount: owner.mediaPlaybackCommands.count,
                    reason: "frame media playback command budget exceeded"
                )
            })
            return failures
        }
        for owner in mediaOwners {
            let video = owner.mediaPlaybackCommands.filter { $0.destination == .videoTexture }
            let sound = owner.mediaPlaybackCommands.filter { $0.destination == .soundLayer }
            var reason: String?
            if !video.isEmpty {
                if let videoRegistry {
                    if case let .failure(failure) = videoRegistry.validate(video, timing: timing) {
                        reason = String(describing: failure)
                    }
                } else { reason = "video registry unavailable" }
            }
            if reason == nil, !sound.isEmpty {
                if let soundRegistry {
                    if case let .failure(failure) = soundRegistry.validate(sound) {
                        reason = String(describing: failure)
                    }
                } else { reason = "sound registry unavailable" }
            }
            if let reason {
                failures.append(.init(ownerTarget: owner.ownerTarget, subsystem: .mediaPlayback,
                    commandCount: owner.mediaPlaybackCommands.count, reason: reason))
            }
        }
        return failures
    }
}
