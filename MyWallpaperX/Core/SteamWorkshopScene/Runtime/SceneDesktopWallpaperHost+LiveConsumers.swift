extension SceneDesktopWallpaperHost {
    static func unavailableLiveScriptPropertyTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> {
        let all = context.propertyVectorScriptProgram.livePropertyInputTargets
            .union(context.sceneScriptScalarProgram.livePropertyInputTargets)
        let active = context.propertyVectorScriptProgram
            .activeLivePropertyInputTargets
            .union(
                context.sceneScriptScalarProgram.activeLivePropertyInputTargets
            )
        return all.subtracting(active)
    }

    static func makeLivePropertyState(
        runtimeInput: SceneRuntimeInput,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram
    ) -> ScenePropertyLiveUpdateState {
        ScenePropertyLiveUpdateState(
            program: runtimeInput.propertyBindingProgram,
            effectiveValues: runtimeInput.effectivePropertyValues,
            activeConsumerTargets: activeLiveConsumerTargets(
                in: runtimeInput.renderDescriptor,
                resolvedMaterialExecutionCapabilities:
                    resolvedMaterialExecutionCapabilities,
                soundPlaybackProgram: soundPlaybackProgram,
                propertyVectorScriptProgram: propertyVectorScriptProgram,
                sceneScriptScalarProgram: sceneScriptScalarProgram
            )
        )
    }

    static func activeLiveConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram
    ) -> Set<SceneDynamicTarget> {
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: descriptor,
            resolvedMaterialLayerIDs:
                resolvedMaterialExecutionCapabilities.executionLayerIDs
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let effectTargets = resolvedMaterialExecutionCapabilities.liveConsumerTargets
        return descriptor.layers.reduce(
            into: effectTargets
                .union(soundPlaybackProgram.liveConsumerTargets)
                .union(propertyVectorScriptProgram.livePropertyInputTargets)
                .union(sceneScriptScalarProgram.livePropertyInputTargets)
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
