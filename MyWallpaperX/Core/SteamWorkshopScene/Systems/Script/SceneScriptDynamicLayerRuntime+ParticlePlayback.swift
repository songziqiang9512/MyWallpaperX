import Foundation

extension SceneScriptDynamicLayerRuntime {
    /// Recomputed inside the existing owner fixed point; it never mutates an
    /// instance. Callback epochs recover event order after owner grouping.
    func particlePlaybackPlan(
        for effects: [SceneScriptOwnerEffects],
        observations: [Int: SceneParticlePlaybackObservation],
        layerPlan: SceneScriptLayerMutationPlan
    ) -> SceneScriptLayerMutationPlan {
        var plan = layerPlan
        let owners = effects.filter { !$0.particlePlaybackCommands.isEmpty }
        let count = owners.reduce(0) { $0 + $1.particlePlaybackCommands.count }
        let bundles = Dictionary(grouping: effects, by: \.ownerTarget)
        var failures: [SceneScriptLayerMutationOwnerFailure] = []
        var visited = Set<SceneDynamicTarget>()
        for owner in owners where visited.insert(owner.ownerTarget).inserted {
            let ownerBundles = bundles[owner.ownerTarget] ?? []
            let commands = ownerBundles.flatMap(\.particlePlaybackCommands)
            let aggregateCount = ownerBundles.reduce(0) { total, bundle in
                total + bundle.particlePlaybackCommands.count + bundle.layerMutations.count
                    + bundle.animationMutations.count + bundle.materialFunctionMutations.count
                    + bundle.videoCommands.count + bundle.textureAnimationCommands.count
                    + bundle.puppetBoneMutations.count
            }
            guard count <= 64, commands.count <= 64, aggregateCount <= 256 else {
                failures.append(.init(ownerTarget: owner.ownerTarget,
                    failure: .mutationOverflow("particle playback command budget exceeded")))
                continue
            }
            let valid = commands.allSatisfy { command in
                guard let observation = observations[command.layerID],
                      !plan.destroyedAuthoredLayerIDs.contains(command.layerID) else { return false }
                let current = particlePlayback[command.layerID] ?? .init()
                return observation.intent == current.intent && observation.revision == current.revision
            }
            if !valid {
                failures.append(.init(ownerTarget: owner.ownerTarget,
                    failure: .invalidArgument("particle playback observation unavailable")))
            }
        }
        if failures.isEmpty {
            var commands: [(SceneDynamicTarget, SceneScriptParticlePlaybackCommand)] = []
            for owner in owners {
                for command in owner.particlePlaybackCommands { commands.append((owner.ownerTarget, command)) }
            }
            commands.sort { left, right in
                if left.1.callbackEpoch != right.1.callbackEpoch { return left.1.callbackEpoch < right.1.callbackEpoch }
                return left.1.ordinal < right.1.ordinal
            }
            for (owner, command) in commands {
                let previous = plan.particlePlayback[command.layerID] ?? .init()
                guard previous.revision < UInt64.max else {
                    failures.append(.init(ownerTarget: owner, failure: .staleOwner)); continue
                }
                let intent: SceneParticlePlaybackIntent
                switch command.action { case .play: intent = .playing; case .pause: intent = .paused; case .stop: intent = .stopped; case .emit: intent = previous.intent }
                let next = SceneParticlePlaybackSnapshot(intent: intent, revision: previous.revision + 1)
                plan.particlePlayback[command.layerID] = next
                plan.particleTransitions.append(.init(layerID: command.layerID, action: command.action, revision: next.revision, count: command.count, callbackEpoch: command.callbackEpoch, ordinal: command.ordinal))
            }
        }
        plan.outcome = .init(committedMutationCount: plan.outcome.committedMutationCount,
            committedDynamicMutationCount: plan.outcome.committedDynamicMutationCount,
            failures: plan.outcome.failures + failures)
        return plan
    }
}
