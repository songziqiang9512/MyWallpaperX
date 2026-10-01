import Foundation

extension SceneDesktopWallpaperSession {
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
            unavailableConsumerTargets:
                SceneDesktopWallpaperHost.unavailableLiveScriptPropertyTargets(in: context)
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
