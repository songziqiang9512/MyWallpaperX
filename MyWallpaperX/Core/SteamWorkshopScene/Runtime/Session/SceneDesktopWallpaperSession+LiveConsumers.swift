import Foundation

extension SceneDesktopWallpaperSession {
    func preparedCallbackPropertyKeys(
        definitions: [SceneUserPropertyDefinition]
    ) -> Set<String> {
        guard let context = launchContext, !surfaces.isEmpty,
              Set(surfaces.keys) == preparedSurfaceIDs,
              context.sceneScriptScalarProgram.generation == context.propertyVectorScriptProgram.generation,
              context.sceneScriptStringProgram.generation == context.propertyVectorScriptProgram.generation,
              surfaces.values.allSatisfy({
                  $0.scriptGeneration == context.propertyVectorScriptProgram.generation
              }) else { return [] }
        let state = context.liveState
        let unavailable = unavailableLiveConsumerTargets(in: context)
        let retiredCallbacks = retiredPropertyCallbackTargets(
            in: context, propertyKeys: Set(definitions.map(\.key)))
        let rebuild = Set(state.program.rebuildRequiredPropertyKeys)
        let instructions = Dictionary(grouping: state.program.instructions, by: \.propertyKey)
        return Set(Dictionary(grouping: definitions, by: \.key).compactMap { key, definitions in
            guard definitions.count == 1, let definition = definitions.first,
                  let targets = state.scriptUserPropertyConsumerTargetsByKey[key]?
                    .subtracting(retiredCallbacks), !targets.isEmpty,
                  !rebuild.contains(key),
                  targets.union((instructions[key] ?? []).map(\.target)).allSatisfy({
                      state.activeConsumerTargets.contains($0) && !unavailable.contains($0)
                  }),
                  let current = state.effectiveValues[key], let fallback = definition.defaultValue
            else { return nil }
            switch (definition.kind, fallback, current) {
            case (.bool, .bool, .bool), (.slider, .number, .number),
                 (.color, .string, .string), (.textInput, .string, .string):
                return key
            case (.combo, .string, .string), (.combo, .number, .number), (.combo, .bool, .bool):
                return key
            default:
                return nil
            }
        })
    }

    func particleVisibilityResourcesPrepared(
        layerID: Int,
        context: SceneDesktopWallpaperLaunchContext
    ) -> Bool {
        !surfaces.isEmpty && Set(surfaces.keys) == preparedSurfaceIDs
            && surfaces.values.allSatisfy {
                $0.scriptGeneration == context.propertyVectorScriptProgram.generation
                    && $0.metalView.preparedParticleLayerIDs.contains(layerID)
            }
    }

    func layerVisibilityResourcesPrepared(
        layerID: Int,
        context: SceneDesktopWallpaperLaunchContext
    ) -> Bool {
        let requirements = context.particleVisibilityRequirements[layerID]
            ?? (context.particleLayerIDs.contains(layerID) ? [layerID] : [])
        return requirements.allSatisfy {
            particleVisibilityResourcesPrepared(layerID: $0, context: context)
        }
    }

    func unavailableLiveConsumerTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> {
        let particleTargets = context.particleVisibilityRequirements.keys
            .filter { !layerVisibilityResourcesPrepared(layerID: $0, context: context) }
            .map { SceneDynamicTarget.layer(layerID: $0, field: .visibility) }
        return SceneDesktopWallpaperHost.unavailableLiveScriptPropertyTargets(in: context)
            .union(particleTargets)
    }

    /// Only committed authored deletions end launch-registered callbacks.
    /// This does not retire their prepared value inputs or retryable peers.
    func retiredPropertyCallbackTargets(
        in context: SceneDesktopWallpaperLaunchContext,
        propertyKeys: Set<String>
    ) -> Set<SceneDynamicTarget> {
        let destroyed = context.sceneScriptDynamicLayerRuntime.snapshot().destroyedAuthoredLayerIDs
        guard !destroyed.isEmpty else { return [] }
        return propertyKeys.reduce(into: []) { result, key in
            for target in context.liveState.scriptUserPropertyConsumerTargetsByKey[key] ?? [] {
                if let layerID = SceneScriptLayerMutationBridge.layerID(for: target),
                   destroyed.contains(layerID) { result.insert(target) }
            }
        }
    }

    @discardableResult
    func applyUserPropertyValue(
        _ value: SceneUserPropertyValue,
        forPropertyKey propertyKey: String,
        recordID: String?
    ) -> Bool {
        applyUserPropertyValues(
            [propertyKey: value],
            changedPropertyKeys: [propertyKey],
            recordID: recordID
        )
    }

    @discardableResult
    func applyUserPropertyValues(
        _ replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>,
        recordID: String?
    ) -> Bool {
        guard var context = launchContext,
              context.recordID == recordID else {
            return false
        }
        var candidateLiveState = context.liveState
        let unavailableTargets = unavailableLiveConsumerTargets(in: context)
        let retiredCallbacks = retiredPropertyCallbackTargets(
            in: context, propertyKeys: changedPropertyKeys)
        guard candidateLiveState.apply(
            replacements: replacements,
            changedPropertyKeys: changedPropertyKeys,
            unavailableConsumerTargets: unavailableTargets,
            retiredScriptCallbackTargets: retiredCallbacks
        ) else {
#if DEBUG
            logLivePropertyRejection(keys: changedPropertyKeys, state: context.liveState,
                unavailable: unavailableTargets, retiredCallbacks: retiredCallbacks,
                reason: "value-or-consumer-admission")
#endif
            return false
        }
        guard soundPlaybackRegistry?.canApply(
            userValues: candidateLiveState.userValues
        ) != false else {
#if DEBUG
            logLivePropertyRejection(keys: changedPropertyKeys, state: context.liveState,
                unavailable: unavailableTargets, retiredCallbacks: retiredCallbacks,
                reason: "sound-input-admission")
#endif
            return false
        }
        var deferredLayerIDs = deferredLayerVisibilitySelection(
            in: context,
            userValues: candidateLiveState.userValues,
            changedPropertyKeys: changedPropertyKeys
        )
        var acceptedReplacements = replacements
        var acceptedKeys = changedPropertyKeys
        let pending = pendingDeferredLayerVisibilityUpdate
        let mergesPending = pending.map {
            !deferredLayerIDs.isEmpty
                || !$0.changedPropertyKeys.isDisjoint(with: changedPropertyKeys)
        } ?? false
        if mergesPending, let pending {
            // Independent edits that need no resource stay immediate. Edits
            // sharing this transaction preserve all accepted pending keys;
            // the latest replacement (including removal) wins for each key.
            acceptedReplacements = pending.replacements
            acceptedKeys.formUnion(pending.changedPropertyKeys)
            for key in changedPropertyKeys {
                acceptedReplacements[key] = replacements[key]
            }
            candidateLiveState = context.liveState
            guard candidateLiveState.apply(
                replacements: acceptedReplacements,
                changedPropertyKeys: acceptedKeys,
                unavailableConsumerTargets: unavailableTargets,
                retiredScriptCallbackTargets: retiredPropertyCallbackTargets(
                    in: context, propertyKeys: acceptedKeys)
            ), soundPlaybackRegistry?.canApply(
                userValues: candidateLiveState.userValues
            ) != false else {
                return false
            }
            deferredLayerIDs = deferredLayerVisibilitySelection(
                in: context,
                userValues: candidateLiveState.userValues,
                changedPropertyKeys: acceptedKeys
            )
        }
        if !deferredLayerIDs.isEmpty {
            guard nextDeferredPropertyGeneration < UInt64.max else {
                return false
            }
            nextDeferredPropertyGeneration += 1
            let generation = nextDeferredPropertyGeneration
            let resources = context.preparedDeviceResources.baseImages
            for layerID in deferredLayerIDs.sorted() {
                resources.requestDeferredBaseImage(
                    layerID: layerID,
                    requestGeneration: generation
                )
            }
            if let superseded = pendingDeferredLayerVisibilityUpdate {
                logDeferredLayerVisibilityTransition(
                    generation: superseded.generation,
                    layerIDs: superseded.layerIDs,
                    state: "superseded"
                )
            }
            pendingDeferredLayerVisibilityUpdate = .init(
                generation: generation,
                replacements: acceptedReplacements,
                changedPropertyKeys: acceptedKeys,
                layerIDs: deferredLayerIDs,
                recordID: recordID
            )
            logDeferredLayerVisibilityTransition(
                generation: generation,
                layerIDs: deferredLayerIDs,
                state: "pending"
            )
            promotePendingDeferredLayerVisibilityIfReady()
            return true
        }
        if mergesPending, let pending {
            logDeferredLayerVisibilityTransition(
                generation: pending.generation,
                layerIDs: pending.layerIDs,
                state: "superseded"
            )
            pendingDeferredLayerVisibilityUpdate = nil
        }
        guard refreshPausedSoundProperties(in: context, candidate: candidateLiveState,
            changedPropertyKeys: acceptedKeys) else { return false }
        context.liveState = candidateLiveState
        soundPlaybackRegistry?.apply(userValues: candidateLiveState.userValues)
        launchContext = context
        return true
    }

    func deferredLayerVisibilitySelection(
        in context: SceneDesktopWallpaperLaunchContext,
        userValues: [SceneDynamicTarget: SceneDynamicValue],
        changedPropertyKeys: Set<String>
    ) -> Set<Int> {
        let deferredLayerIDs = context.preparedDeviceResources.baseImages
            .deferredLayerIDs
        return Set(
            context.runtimeInput.propertyBindingProgram.instructions.compactMap {
                instruction -> Int? in
                guard changedPropertyKeys.contains(instruction.propertyKey),
                      instruction.condition != nil,
                      case let .layer(layerID, .visibility) = instruction.target,
                      deferredLayerIDs.contains(layerID),
                      case .bool(true)? = userValues[instruction.target]
                else { return nil }
                return layerID
            }
        )
    }

    func promotePendingDeferredLayerVisibilityIfReady() {
        guard let pending = pendingDeferredLayerVisibilityUpdate,
              var context = launchContext,
              context.recordID == pending.recordID else { return }
        let resources = context.preparedDeviceResources.baseImages
        let statuses = pending.layerIDs.map {
            resources.deferredStatus(for: $0)
        }
        if let failure = statuses.compactMap({ status -> String? in
            guard case let .failed(code) = status else { return nil }
            return code
        }).first {
            pendingDeferredLayerVisibilityUpdate = nil
            logDeferredLayerVisibilityTransition(
                generation: pending.generation,
                layerIDs: pending.layerIDs,
                state: "failed:\(failure)"
            )
            return
        }
        guard statuses.allSatisfy({ $0 == .ready }), !surfaces.isEmpty else {
            return
        }
        var adoptedSurfaces: [Surface] = []
        for surface in surfaces.values {
            guard pending.layerIDs.allSatisfy({
                surface.metalView.adoptPreparedDeferredBaseImage(layerID: $0)
            }) else {
                surface.metalView.discardPreparedDeferredBaseImages(
                    layerIDs: pending.layerIDs
                )
                adoptedSurfaces.forEach {
                    $0.metalView.discardPreparedDeferredBaseImages(
                        layerIDs: pending.layerIDs
                    )
                }
                return
            }
            adoptedSurfaces.append(surface)
        }

        var candidateLiveState = context.liveState
        guard candidateLiveState.apply(
            replacements: pending.replacements,
            changedPropertyKeys: pending.changedPropertyKeys,
            unavailableConsumerTargets: unavailableLiveConsumerTargets(in: context),
            retiredScriptCallbackTargets: retiredPropertyCallbackTargets(
                in: context, propertyKeys: pending.changedPropertyKeys)
        ), soundPlaybackRegistry?.canApply(
            userValues: candidateLiveState.userValues
        ) != false, refreshPausedSoundProperties(in: context, candidate: candidateLiveState,
            changedPropertyKeys: pending.changedPropertyKeys) else {
            adoptedSurfaces.forEach {
                $0.metalView.discardPreparedDeferredBaseImages(
                    layerIDs: pending.layerIDs
                )
            }
            pendingDeferredLayerVisibilityUpdate = nil
            logDeferredLayerVisibilityTransition(
                generation: pending.generation,
                layerIDs: pending.layerIDs,
                state: "failed:commit-validation"
            )
            return
        }
        context.liveState = candidateLiveState
        soundPlaybackRegistry?.apply(userValues: candidateLiveState.userValues)
        adoptedSurfaces.forEach {
            $0.metalView.commitPreparedDeferredBaseImages(
                layerIDs: pending.layerIDs
            )
        }
        launchContext = context
        guard pendingDeferredLayerVisibilityUpdate?.generation
                == pending.generation else { return }
        pendingDeferredLayerVisibilityUpdate = nil
        logDeferredLayerVisibilityTransition(
            generation: pending.generation,
            layerIDs: pending.layerIDs,
            state: "committed"
        )
    }

#if DEBUG
    private func logLivePropertyRejection(
        keys: Set<String>, state: ScenePropertyLiveUpdateState,
        unavailable: Set<SceneDynamicTarget>, retiredCallbacks: Set<SceneDynamicTarget>, reason: String
    ) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let targets = Set(state.program.instructions.lazy.filter {
            keys.contains($0.propertyKey)
        }.map(\.target)).union(keys.reduce(into: Set<SceneDynamicTarget>()) { result, key in
            result.formUnion(state.scriptUserPropertyConsumerTargetsByKey[key] ?? [])
        }.subtracting(retiredCallbacks))
        NSLog("MWX live property rejection: reason=%@ keys=%@ revision=%llu inactive=%@ unavailable=%@",
            reason, keys.sorted().joined(separator: ","), state.revision,
            targets.subtracting(state.activeConsumerTargets).map { String(describing: $0) }.sorted().joined(separator: ";"),
            targets.intersection(unavailable).map { String(describing: $0) }.sorted().joined(separator: ";"))
    }
#endif

    func logDeferredLayerVisibilityTransition(
        generation: UInt64,
        layerIDs: Set<Int>,
        state: String
    ) {
#if DEBUG
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
#else
        guard state.hasPrefix("failed") else { return }
#endif
        NSLog(
            "MWX deferred property transition: schema=deferred-property-transition-v1 generation=%llu layers=%@ state=%@",
            generation,
            layerIDs.sorted().map(String.init).joined(separator: ","),
            state
        )
    }

}
