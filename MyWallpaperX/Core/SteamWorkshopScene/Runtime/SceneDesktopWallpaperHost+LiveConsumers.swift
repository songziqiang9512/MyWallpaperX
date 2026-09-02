import Foundation

extension SceneDesktopWallpaperHost {
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
        guard surfaces.values.allSatisfy({ surface in
            pending.layerIDs.allSatisfy {
                surface.metalView.adoptPreparedDeferredBaseImage(layerID: $0)
            }
        }) else { return }

        var candidateLiveState = context.liveState
        guard candidateLiveState.apply(
            replacements: pending.replacements,
            changedPropertyKeys: pending.changedPropertyKeys,
            unavailableConsumerTargets:
                Self.unavailableLiveScriptPropertyTargets(in: context)
        ), soundPlaybackRegistry?.canApply(
            userValues: candidateLiveState.userValues
        ) != false else {
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
        guard Self.usesDebugEvidenceWindow else { return }
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

    static func unavailableLiveScriptPropertyTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> {
        let all = context.propertyVectorScriptProgram.livePropertyInputTargets
            .union(context.sceneScriptScalarProgram.livePropertyInputTargets)
            .union(context.sceneScriptStringProgram.livePropertyInputTargets)
        let active = context.propertyVectorScriptProgram
            .activeLivePropertyInputTargets
            .union(
                context.sceneScriptScalarProgram.activeLivePropertyInputTargets
            )
            .union(
                context.sceneScriptStringProgram.activeLivePropertyInputTargets
            )
        return all.subtracting(active)
    }

    static func makeLivePropertyState(
        runtimeInput: SceneRuntimeInput,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram
    ) -> ScenePropertyLiveUpdateState {
        ScenePropertyLiveUpdateState(
            program: runtimeInput.propertyBindingProgram,
            effectiveValues: runtimeInput.effectivePropertyValues,
            activeConsumerTargets: activeLiveConsumerTargets(
                in: runtimeInput.renderDescriptor,
                propertyBindingProgram: runtimeInput.propertyBindingProgram,
                resolvedMaterialExecutionCapabilities:
                    resolvedMaterialExecutionCapabilities,
                soundPlaybackProgram: soundPlaybackProgram,
                propertyVectorScriptProgram: propertyVectorScriptProgram,
                sceneScriptScalarProgram: sceneScriptScalarProgram,
                sceneScriptStringProgram: sceneScriptStringProgram
            )
        )
    }

    static func activeLiveConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram
    ) -> Set<SceneDynamicTarget> {
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: descriptor,
            resolvedMaterialLayerIDs:
                resolvedMaterialExecutionCapabilities.executionLayerIDs
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let effectTargets = resolvedMaterialExecutionCapabilities.liveConsumerTargets
        let layerVisibilityTargets =
            SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor,
                candidates: propertyBindingProgram.liveLayerVisibilityTargets
            )
        return descriptor.layers.reduce(
            into: effectTargets
                .union(layerVisibilityTargets)
                .union(soundPlaybackProgram.liveConsumerTargets)
                .union(propertyVectorScriptProgram.livePropertyInputTargets)
                .union(sceneScriptScalarProgram.livePropertyInputTargets)
                .union(sceneScriptStringProgram.livePropertyInputTargets)
        ) { targets, layer in
            switch layer.contentKind {
            case "image":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                if layer.supportsDirectLayerColorConsumer,
                   visibleLayerIDs.contains(layer.id) {
                    targets.insert(.layer(layerID: layer.id, field: .color))
                }
                for animationLayer in layer.puppetAnimationLayers
                    where animationLayer.visibilityBinding != nil {
                    guard let animationLayerID = animationLayer.id else { continue }
                    targets.insert(ScenePuppetAnimationPropertyTarget.visibility(
                        layerID: layer.id,
                        animationLayerID: animationLayerID
                    ))
                }
            case "text":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                guard layer.text != nil,
                      layer.textStyle != nil,
                      visibleLayerIDs.contains(layer.id) else { return }
                targets.insert(.text(layerID: layer.id, field: .content))
                targets.insert(.text(layerID: layer.id, field: .pointSize))
                targets.insert(.text(layerID: layer.id, field: .color))
                if layer.textStyle?.limitWidth == true {
                    targets.insert(.text(layerID: layer.id, field: .maxWidth))
                }
            case "solid":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                targets.insert(.layer(layerID: layer.id, field: .color))
            case "spotLight", "directionalLight":
                if visibleLayerIDs.contains(layer.id) {
                    targets.insert(.layer(layerID: layer.id, field: .color))
                }
            case "particle":
                let fields: [SceneDynamicParticleField] = [
                    .alpha, .size, .lifetime, .rate, .speed, .count,
                    .brightness, .normalizedColor,
                ]
                targets.formUnion(fields.map {
                    .particle(layerID: layer.id, field: $0)
                })
            case "composition", "project", "fullscreen":
                if utilityPlans[layer.id]?.shouldCapture == true {
                    targets.insert(.layer(layerID: layer.id, field: .alpha))
                }
            default:
                break
            }
        }
    }
}
