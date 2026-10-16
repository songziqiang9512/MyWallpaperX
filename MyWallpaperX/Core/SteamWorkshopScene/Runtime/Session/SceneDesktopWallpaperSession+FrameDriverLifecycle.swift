import AppKit
import QuartzCore

/// Owner-local callback admission may reject typed effects. Presentation
/// failure never restores these watermarks or replays an executed VM frame.
struct SceneScriptProgramFrameStates {
    let scalar: SceneScriptProgramFrameState
    let string: SceneScriptProgramFrameState
    let vector: SceneScriptProgramFrameState
}

extension SceneDesktopWallpaperSession {
    /// Prepare the shared callback inputs before any VM family can create a
    /// text instance. These projections belong to the current simulation frame.
    func prepareSceneScriptFrame(
        _ context: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneScriptFrameInput {
        let surface = surfaces.count == 1
            ? surfaces.values.first?.metalView.sceneScriptSurfaceInput(
                timing: timing, dynamicValues: dynamicValues) : nil
        let failures = context.sceneScriptStringProgram.preparePreparedTextCloneInputs(
            userValues: context.liveState.userValues,
            effectivePropertyValues: context.liveState.effectiveValues,
            propertyRevision: context.liveState.revision)
        for (target, failure) in failures {
            NSLog("MWX SceneScript VM: target=%@ preparation=text-template-input failure=%@ code=%@",
                String(describing: target), String(describing: failure), failure.code)
        }
        return .init(timing: timing, surface: surface)
    }

    func sceneScriptProgramFrameState(
        _ context: SceneDesktopWallpaperLaunchContext
    ) -> SceneScriptProgramFrameStates {
        .init(
            scalar: context.sceneScriptScalarProgram.frameStateSnapshot(),
            string: context.sceneScriptStringProgram.frameStateSnapshot(),
            vector: context.propertyVectorScriptProgram.frameStateSnapshot()
        )
    }

    func restoreSceneScriptProgramFrameState(
        _ context: SceneDesktopWallpaperLaunchContext,
        _ state: SceneScriptProgramFrameStates,
        rejectedOwnerTargets: Set<SceneDynamicTarget>? = nil
    ) {
        context.sceneScriptScalarProgram.restoreFrameState(state.scalar, rejectedOwnerTargets: rejectedOwnerTargets)
        context.sceneScriptStringProgram.restoreFrameState(state.string, rejectedOwnerTargets: rejectedOwnerTargets)
        context.propertyVectorScriptProgram.restoreFrameState(state.vector, rejectedOwnerTargets: rejectedOwnerTargets)
    }

    func finalizeSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext,
        committing: Bool,
        rejectedOwnerTargets: Set<SceneDynamicTarget> = []
    ) {
        context.sceneScriptScalarProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.sceneScriptStringProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.sceneScriptCursorProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.propertyVectorScriptProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func discardSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext
    ) {
        finalizeSceneScriptLayerMutations(context, committing: false)
    }

    func discardSceneScriptLayerSnapshot(
        _ context: SceneDesktopWallpaperLaunchContext
    ) {
        context.propertyVectorScriptProgram.domain?
            .discardCommittedLayerSnapshot()
    }

    func finalizeSceneScriptLayerSnapshot(
        _ context: SceneDesktopWallpaperLaunchContext
    ) {
        context.propertyVectorScriptProgram.domain?
            .finalizeCommittedLayerSnapshot()
    }

    func commitSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        finalizeSceneScriptLayerMutations(
            context, committing: true,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func commitSceneScriptLayerPlan(
        _ context: SceneDesktopWallpaperLaunchContext,
        plan: SceneScriptLayerMutationPlan,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        context.sceneScriptDynamicLayerRuntime.commit(plan)
        commitSceneScriptLayerMutations(
            context, rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func commitSimulatedSceneFrame(
        _ context: SceneDesktopWallpaperLaunchContext,
        pendingEvaluation: SceneEvaluationTransaction.PendingEvaluation,
        pendingSharedLayerAlpha: SceneSharedLayerAlphaRuntime.PendingValues,
        animationMutations: [SceneTimelinePlaybackMutation],
        mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand],
        textureAnimationCommands:
            [SceneTextureAnimationCommand],
        puppetAnimationCommands: [ScenePuppetAnimationCommand],
        scriptFrame: SceneScriptFrameInput,
        timing: SceneFrameTiming,
        layerPlan: SceneScriptLayerMutationPlan,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        sharedLayerAlphaRuntime.commitValues(pendingSharedLayerAlpha)
        if !animationMutations.isEmpty,
           case .success = context.timelinePlaybackRuntime.apply(
               animationMutations, sceneTime: timing.sceneTime
           ) {
            NSLog(
                "MWX SceneScript VM: animationCommands=%d callback=committed frame=%llu projection=same-frame route=generic-only",
                animationMutations.count,
                timing.frameIndex
            )
        }
        commitSceneMediaPlayback(mediaPlaybackCommands, timing: timing)
        if !textureAnimationCommands.isEmpty,
           case .success = context.textureAnimationPlaybackRuntime.apply(
               textureAnimationCommands,
               sceneTime: timing.sceneTime
           ) {
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                NSLog(
                    "MWX SceneScript VM: textureAnimationCommands=%d callback=committed nextFrame=true route=generic-only",
                    textureAnimationCommands.count
                )
            }
#endif
        }
        if !puppetAnimationCommands.isEmpty,
           case .success = context.puppetAnimationPlaybackRuntime.apply(
               puppetAnimationCommands, frameIndex: timing.frameIndex) {
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                let controls = puppetAnimationCommands.map { command in
                    let identity = command.identity
                    return "\(identity.layerID):\(identity.animationLayerIndex):"
                        + "\(identity.animationLayerID.map(String.init) ?? "none")=\(command.action)"
                }.joined(separator: ",")
                NSLog("MWX DEBUG SCENE: puppetAnimationCommands=%d callback=committed frame=%llu nextFrame=true controls=%@",
                    puppetAnimationCommands.count, timing.frameIndex, controls)
            }
#endif
        }
        commitSceneScriptLayerPlan(
            context, plan: layerPlan,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        let adoption = context.sceneScriptStringProgram.adoptCommittedPreparedTextClones(
            frame: scriptFrame, liveTextTemplates: layerPlan.textTemplateIdentitiesByLayerID)
        context.frameSchema.registerStatefulTargets(Set(adoption.definitions.map(\.target)))
        for (target, failure) in adoption.failures {
            NSLog("MWX SceneScript VM: target=%@ lifecycle=text-clone-adoption failure=%@ code=%@",
                  String(describing: target), String(describing: failure), failure.code)
        }
        if let failure = adoption.queueFailure {
            NSLog("MWX SceneScript VM: lifecycle=text-clone-adoption failure=%@ code=%@",
                  String(describing: failure), failure.code)
        }
        let committedEvaluation: SceneEvaluationTransaction.PendingEvaluation
        if layerPlan.createdPreparedTextValues.isEmpty {
            committedEvaluation = pendingEvaluation
        } else {
            // A birth is the only point where the committed schema expands.
            // Seed its accepted init result in the existing snapshot owner so
            // next update(value) receives it; the authored fallback stays raw.
            let targets = Set(context.frameSchema.dynamicDefinitions.map(\.target))
            let snapshot = pendingEvaluation.snapshot
            var scripts = snapshot.values(for: targets, source: .sceneScript)
            for (target, value) in layerPlan.createdPreparedTextValues {
                guard case let .text(layerID, .content) = target,
                      let identity = layerPlan.textTemplateIdentitiesByLayerID[layerID],
                      context.sceneScriptStringProgram.preparedTextTemplates[identity]?.kind == .script else { continue }
                scripts[target] = value
            }
            let resolution = SceneDynamicSnapshotResolver().resolve(
                frameIndex: snapshot.frameIndex, generation: snapshot.generation,
                index: context.frameSchema.dynamicDefinitionIndex,
                userValues: context.sceneScriptDynamicLayerRuntime.projectPreparedTextUserValues(
                    from: context.liveState.userValues, previousValue: evaluationTransaction.previousValue(for:)),
                timelineValues: snapshot.values(for: targets, source: .timeline),
                sceneScriptValues: scripts
            )
            let expanded = evaluationTransaction.prepare(
                frameIndex: snapshot.frameIndex, resolution: resolution)
            committedEvaluation = expanded
        }
        commitSceneDynamicEvaluation(committedEvaluation,
            excludingLayerIDs: layerPlan.destroyedAuthoredLayerIDs.union(layerPlan.retiredDynamicLayerIDs))
        soundPlaybackRegistry?.retire(layerIDs: layerPlan.destroyedAuthoredLayerIDs)
        finalizeSceneScriptLayerSnapshot(context)
        retireDestroyedSceneScriptOwners(
            context, layerIDs: layerPlan.destroyedAuthoredLayerIDs.union(layerPlan.retiredDynamicLayerIDs),
            frame: scriptFrame
        )
        context.sceneScriptStorageSession?.commitFrameTransaction()
    }

    func commitSceneMediaPlayback(
        _ mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand], timing: SceneFrameTiming
    ) {
        for command in mediaPlaybackCommands {
            switch command.destination {
            case .videoTexture: _ = videoTextureSourceRegistry?.apply([command], timing: timing)
            case .soundLayer: _ = soundPlaybackRegistry?.apply([command])
            }
        }
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow, !mediaPlaybackCommands.isEmpty {
            NSLog("MWX DEBUG SCENE: mediaPlaybackCommands=%@ callback=committed frame=%llu",
                String(describing: mediaPlaybackCommands), timing.frameIndex)
        }
#endif
    }

    /// Both cadence and property events publish through the same transaction
    /// and gain consumer; neither path can write a named script input directly.
    func commitSceneDynamicEvaluation(
        _ pending: SceneEvaluationTransaction.PendingEvaluation,
        excludingLayerIDs: Set<Int> = []
    ) {
        evaluationTransaction.commit(pending)
        soundPlaybackRegistry?.apply(snapshot: pending.snapshot, excludingLayerIDs: excludingLayerIDs)
    }

    private func retireDestroyedSceneScriptOwners(
        _ context: SceneDesktopWallpaperLaunchContext,
        layerIDs: Set<Int>,
        frame: SceneScriptFrameInput
    ) {
        guard !layerIDs.isEmpty else { return }
        // All owner journals have finalized. Retire against the last live
        // snapshot before the next cadence publishes the accepted tombstones.
        // Programs remember quiescent cohorts; failed cleanup can retry without
        // running destroy callbacks or consumed frame commands a second time.
        let values = context.liveState.effectiveValues
        let userPropertiesJSON = context.propertyVectorScriptProgram
            .userPropertiesJSON(effectiveValues: values, revision: context.liveState.revision)
        let outcomes = context.sceneScriptScalarProgram.retire(
            layerIDs: layerIDs, frame: frame,
            effectivePropertyValues: values, userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptStringProgram.retire(
            layerIDs: layerIDs, frame: frame,
            effectivePropertyValues: values, userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptCursorProgram.retire(
            layerIDs: layerIDs, frame: frame,
            effectivePropertyValues: values, userPropertiesJSON: userPropertiesJSON
        ) + context.propertyVectorScriptProgram.retire(
            layerIDs: layerIDs, frame: frame,
            effectivePropertyValues: values, userPropertiesJSON: userPropertiesJSON
        )
        if !outcomes.isEmpty {
            let retiredTargets = context.sceneScriptStatefulTargets.filter { target in
                SceneScriptLayerMutationBridge.layerID(for: target).map(layerIDs.contains) ?? false
            }
            context.frameSchema.retireStatefulTargets(retiredTargets)
            NSLog("MWX SceneScript VM: lifecycle=layer-retirement owners=%d destroyCallbacks=%d quiescent=%d failures=%d sceneTime=%.3f",
                outcomes.count, outcomes.filter(\.destroyCallbackInvoked).count,
                outcomes.filter(\.snapshot.isQuiescent).count,
                outcomes.compactMap(\.failure).count, frame.runtime)
        }
    }

    func teardownSceneScriptOwners(
        _ context: SceneDesktopWallpaperLaunchContext,
        reason: SceneGraphExecutionResetReason
    ) {
        // Stop/switch is a scene-wide barrier.  Release every owner journal
        // before destroy callbacks so dynamic topology removal cannot be
        // blocked by a provisional owner from the last frame.
        discardSceneScriptLayerMutations(context)
        discardSceneScriptLayerSnapshot(context)
        context.sceneScriptStorageSession?.discardFrameTransaction()
        let hostTime = CACurrentMediaTime()
#if DEBUG
        let wallDate = Self.debugWallDateOverride ?? Date()
#else
        let wallDate = Date()
#endif
        let frame = SceneScriptFrameInput(timing: .init(
            frameIndex: 0,
            hostTime: hostTime,
            sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
            rawFrameTime: 0,
            simulationFrameTime: 0,
            droppedFrameTime: 0,
            wallDate: wallDate
        ))
        let userPropertiesJSON = context.propertyVectorScriptProgram
            .userPropertiesJSON(
                effectiveValues: context.liveState.effectiveValues,
                revision: context.liveState.revision
            )
        let outcomes = context.sceneScriptScalarProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptStringProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptCursorProgram.teardown(
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        ) + context.propertyVectorScriptProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        )
        let destroyCallbacks = outcomes.filter(\.destroyCallbackInvoked).count
        let quiescent = outcomes.filter(\.snapshot.isQuiescent).count
        let failures = outcomes.compactMap(\.failure)
        NSLog(
            "MWX SceneScript VM: lifecycle=teardown reason=%@ owners=%d destroyCallbacks=%d quiescent=%d failures=%d timers=%d jobs=%d mutations=%d dynamicLayers=%d route=generic-only",
            String(describing: reason), outcomes.count, destroyCallbacks,
            quiescent, failures.count,
            outcomes.reduce(0) { $0 + $1.snapshot.activeTimerCount },
            outcomes.filter(\.snapshot.hasJobResidue).count,
            outcomes.reduce(0) { $0 + $1.snapshot.pendingLayerMutationCount },
            outcomes.reduce(0) { $0 + $1.snapshot.activeDynamicLayerCount }
        )
    }
}
