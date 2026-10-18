import Foundation
import QuartzCore

extension SceneDesktopWallpaperSession {
    /// Property events use the existing evaluator at the frozen scene time.
    /// Ordinary cadence remains responsible while playing; paused events only
    /// refresh affected mixed-volume owners and their prepared input lanes.
    func refreshPausedSoundProperties(
        in context: SceneDesktopWallpaperLaunchContext,
        candidate: ScenePropertyLiveUpdateState,
        changedPropertyKeys: Set<String>
    ) -> Bool {
        guard sceneClock.isPaused, candidate.revision != context.liveState.revision else { return true }
        let mixedTargets = Set(context.soundPlaybackProgram.bindings.compactMap { binding in
            binding.volumePropertyKey != nil
                && context.soundPlaybackProgram.scriptVolumeTargets.contains(binding.volumeTarget)
                ? binding.volumeTarget : nil
        })
        guard !mixedTargets.isEmpty else { return true }
        let changedInputs = Set(candidate.program.instructions.filter {
            changedPropertyKeys.contains($0.propertyKey)
        }.map(\.target)).union(changedPropertyKeys.flatMap {
            candidate.scriptUserPropertyConsumerTargetsByKey[$0] ?? []
        })
        let program = context.sceneScriptScalarProgram
        let owners = program.propertyRefreshOwnerTargets(consuming: changedInputs).intersection(mixedTargets)
        guard !owners.isEmpty else { return true }
        guard !surfaces.isEmpty, Set(surfaces.keys) == preparedSurfaceIDs,
              surfaces.values.allSatisfy({ $0.scriptGeneration == program.generation }),
              let catalogToken = context.frameSchema.sceneScriptLayerCatalogToken,
              let base = evaluationTransaction.committedSnapshot else { return false }
        // Missing declared properties keep their codec fallback; they have no
        // typed schema lane to replace. The publishing owners remain mandatory.
        let targets = owners.union(program.propertyRefreshInputTargets(for: owners).filter {
            base.authoredValue(for: $0) != nil
        })
        let userValues = candidate.userValues.filter { targets.contains($0.key) }
        guard let preliminary = evaluationTransaction.prepareScoped(
            replacing: targets, index: context.dynamicDefinitionIndex,
            userValues: userValues) else { return false }
        let frozenClock = sceneClock.advance(hostTime: CACurrentMediaTime(), wallDate: Date())
        let timing = SceneFrameTiming(frameIndex: base.frameIndex, hostTime: frozenClock.hostTime,
            sceneTime: frozenClock.sceneTime, rawFrameTime: 0, simulationFrameTime: 0,
            droppedFrameTime: 0, wallDate: frozenClock.wallDate)
        let frame = SceneScriptFrameInput(timing: timing,
            surface: surfaces.count == 1 ? surfaces.values.first?.metalView.sceneScriptSurfaceInput(
                timing: timing, dynamicValues: base) : nil)
        do {
            try program.domain?.publishSoundPlaybackSnapshot(base,
                descriptor: context.runtimeInput.renderDescriptor,
                soundPlaybackSnapshots: soundPlaybackRegistry?.sceneScriptSnapshots() ?? [:],
                catalogToken: catalogToken)
        } catch {
            return false
        }
        let previousState = program.frameStateSnapshot()
        // Unavailable storage rejects its own callbacks; unrelated owners still advance.
        _ = context.sceneScriptStorageSession?.beginFrameTransaction()
        var committed = false
        defer {
            if !committed {
                program.finalizeLayerMutations(committing: false)
                context.sceneScriptStorageSession?.discardFrameTransaction()
                program.domain?.discardCommittedLayerSnapshot()
            }
        }
        let json = context.propertyVectorScriptProgram.userPropertiesJSON(
            effectiveValues: candidate.effectiveValues, revision: candidate.revision)
        let inputs = preliminary.snapshot.typedValues(for: owners, valueTypes: [.scalar])
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: Set<SceneDynamicTarget> = []
        var effects: [SceneScriptOwnerEffects] = []
        for owner in program.bindings where owners.contains(owner.target) {
            let result = program.evaluate(inputs: inputs, frame: frame,
                effectivePropertyValues: candidate.effectiveValues, propertyRevision: candidate.revision,
                targetFilter: owner.target, propertyRefresh: true, userPropertiesJSON: json)
            values.merge(result.values) { _, current in current }
            failures.formUnion(result.failures.keys)
            effects.append(contentsOf: result.ownerEffects)
        }
        // The first paused envelope admits Sound commands and scalar results.
        // Other effects reject their entire owner, never disappear silently.
        for effect in effects where !effect.materialFunctionMutations.isEmpty
            || !effect.animationMutations.isEmpty || !effect.layerMutations.isEmpty
            || !effect.textureAnimationCommands.isEmpty || !effect.puppetBoneMutations.isEmpty
            || !effect.puppetAnimationCommands.isEmpty || effect.puppetAnimationCallbackRegistrations != 0
            || !effect.particlePlaybackCommands.isEmpty
            || effect.mediaPlaybackCommands.contains(where: { $0.destination != .soundLayer }) {
            failures.insert(effect.ownerTarget)
        }
        let fixedPoint = context.sceneScriptDynamicLayerRuntime.preflightOwnerEffectsToFixedPoint(
            effects, excludingOwners: failures,
            rejectingDependents: { context.sceneScriptStorageSession?.resolveRejectedOwners($0) ?? $0 }
        ) { admitted in
            Set(SceneScriptOwnerEffectsRuntimeValidation.failures(for: admitted,
                timelineRuntime: context.timelinePlaybackRuntime,
                textureAnimationRuntime: context.textureAnimationPlaybackRuntime,
                videoRegistry: videoTextureSourceRegistry, soundRegistry: soundPlaybackRegistry,
                timing: timing, puppetAnimationRuntime: context.puppetAnimationPlaybackRuntime).map(\.ownerTarget))
        }
        let rejected = fixedPoint.externallyRejectedOwners.union(
            fixedPoint.admission.rejectedOwners.compactMap(\.ownerTarget))
        let acceptedValues = values.filter { !rejected.contains($0.key) }
        guard let pending = evaluationTransaction.prepareScoped(replacing: targets,
            index: context.dynamicDefinitionIndex, userValues: userValues,
            sceneScriptValues: acceptedValues) else { return false }
        program.restoreFrameState(previousState, rejectedOwnerTargets: rejected)
        commitSceneScriptLayerPlan(context, plan: fixedPoint.admission.layerPlan, rejectedOwnerTargets: rejected)
        commitSceneMediaPlayback(fixedPoint.admission.admittedEffects.flatMap(\.mediaPlaybackCommands), timing: timing)
        commitSceneDynamicEvaluation(pending)
        context.sceneScriptStorageSession?.commitFrameTransaction()
        program.domain?.finalizeCommittedLayerSnapshot()
        committed = true
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            NSLog("MWX DEBUG SCENE: phase=sound-property-refresh owners=%d rejected=%d frame=%llu sceneTime=%.6f revision=%llu generation=%llu",
                owners.count, rejected.count, pending.snapshot.frameIndex, timing.sceneTime,
                candidate.revision, pending.snapshot.generation)
        }
#endif
        return true
    }
}
