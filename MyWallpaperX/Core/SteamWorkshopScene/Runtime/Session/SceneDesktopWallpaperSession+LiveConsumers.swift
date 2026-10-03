import Foundation

extension SceneDesktopWallpaperSession {
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

    func unavailableLiveConsumerTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> {
        let particleTargets = context.preparedParticleVisibilityLayerIDs
            .filter { !particleVisibilityResourcesPrepared(layerID: $0, context: context) }
            .map { SceneDynamicTarget.layer(layerID: $0, field: .visibility) }
        return SceneDesktopWallpaperHost.unavailableLiveScriptPropertyTargets(in: context)
            .union(particleTargets)
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
        guard candidateLiveState.apply(
            replacements: replacements,
            changedPropertyKeys: changedPropertyKeys,
            unavailableConsumerTargets: unavailableTargets
        ), soundPlaybackRegistry?.canApply(
            userValues: candidateLiveState.userValues
        ) != false else {
            return false
        }
        var deferredLayerIDs = deferredLayerVisibilitySelection(
            in: context,
            effectiveValues: candidateLiveState.effectiveValues,
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
                unavailableConsumerTargets: unavailableTargets
            ), soundPlaybackRegistry?.canApply(
                userValues: candidateLiveState.userValues
            ) != false else {
                return false
            }
            deferredLayerIDs = deferredLayerVisibilitySelection(
                in: context,
                effectiveValues: candidateLiveState.effectiveValues,
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
        context.liveState = candidateLiveState
        soundPlaybackRegistry?.apply(userValues: candidateLiveState.userValues)
        launchContext = context
        return true
    }

    func deferredLayerVisibilitySelection(
        in context: SceneDesktopWallpaperLaunchContext,
        effectiveValues: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>
    ) -> Set<Int> {
        let selectedValues = context.runtimeInput.propertyBindingProgram.evaluate(
            effectiveValues: effectiveValues
        ).userValues
        let deferredLayerIDs = context.preparedDeviceResources.baseImages
            .deferredLayerIDs
        return Set(
            context.runtimeInput.propertyBindingProgram.instructions.compactMap {
                instruction -> Int? in
                guard changedPropertyKeys.contains(instruction.propertyKey),
                      instruction.condition != nil,
                      case let .layer(layerID, .visibility) = instruction.target,
                      deferredLayerIDs.contains(layerID),
                      case .bool(true)? = selectedValues[instruction.target]
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
            unavailableConsumerTargets: unavailableLiveConsumerTargets(in: context)
        ), soundPlaybackRegistry?.canApply(
            userValues: candidateLiveState.userValues
        ) != false else {
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
