import Foundation

extension SceneDesktopWallpaperHost {
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
        preparedStaticModelLayerIDs: Set<Int>,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram
    ) -> ScenePropertyLiveUpdateState {
        let scriptUserPropertyConsumerTargetsByKey = [
            sceneScriptScalarProgram.liveUserPropertyConsumerTargetsByKey,
            sceneScriptStringProgram.liveUserPropertyConsumerTargetsByKey,
        ].reduce(into: [String: Set<SceneDynamicTarget>]()) { result, program in
            for (key, targets) in program {
                result[key, default: []].formUnion(targets)
            }
        }
        return ScenePropertyLiveUpdateState(
            program: runtimeInput.propertyBindingProgram,
            effectiveValues: runtimeInput.effectivePropertyValues,
            activeConsumerTargets: activeLiveConsumerTargets(
                in: runtimeInput.renderDescriptor,
                propertyBindingProgram: runtimeInput.propertyBindingProgram,
                resolvedMaterialExecutionCapabilities:
                    resolvedMaterialExecutionCapabilities,
                soundPlaybackProgram: soundPlaybackProgram,
                preparedStaticModelLayerIDs: preparedStaticModelLayerIDs,
                propertyVectorScriptProgram: propertyVectorScriptProgram,
                sceneScriptScalarProgram: sceneScriptScalarProgram,
                sceneScriptStringProgram: sceneScriptStringProgram
            ),
            scriptUserPropertyConsumerTargetsByKey:
                scriptUserPropertyConsumerTargetsByKey
        )
    }

    static func activeLiveConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        preparedStaticModelLayerIDs: Set<Int>,
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram
    ) -> Set<SceneDynamicTarget> {
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: descriptor,
            resolvedMaterialLayerIDs:
                resolvedMaterialExecutionCapabilities.executionLayerIDs,
            admittedResolvedMaterialReferences:
                resolvedMaterialExecutionCapabilities
                    .admittedResolvedMaterialReferences
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let effectTargets = resolvedMaterialExecutionCapabilities.liveConsumerTargets
        let lightTargets = SceneLightSnapshot.liveConsumerTargets(
            descriptor: descriptor
        )
        let hasOrthographicCamera = descriptor.camera.orthoWidth.map {
            $0.isFinite && $0 > 0
        } == true && descriptor.camera.orthoHeight.map {
            $0.isFinite && $0 > 0
        } == true
        let cameraTargets = Set(
            propertyBindingProgram.instructions.compactMap {
                instruction -> SceneDynamicTarget? in
                guard case let .camera(field) = instruction.target else {
                    return nil
                }
                switch field {
                case .parallaxEnabled, .parallaxAmount, .parallaxDelay,
                     .parallaxMouseInfluence:
                    return instruction.target
                case .shakeEnabled, .shakeAmplitude, .shakeRoughness,
                     .shakeSpeed:
                    return hasOrthographicCamera ? instruction.target : nil
                case .origin, .zoom:
                    return nil
                }
            }
        )
        let layerVisibilityTargets =
            SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor,
                candidates: propertyBindingProgram.liveLayerVisibilityTargets
            )
        let modelMaterialTargets = Set<SceneDynamicTarget>(
            propertyBindingProgram.instructions.compactMap { instruction in
                guard case let .materialConstant(layerID, _, _, _) =
                        instruction.target,
                      preparedStaticModelLayerIDs.contains(layerID) else {
                    return nil
                }
                return instruction.target
            }
        )
        return descriptor.layers.reduce(
            into: effectTargets
                .union(propertyBindingProgram.instructions.compactMap {
                    guard case .scene = $0.target else { return nil }
                    return $0.target
                })
                .union(cameraTargets)
                .union(lightTargets)
                .union(layerVisibilityTargets)
                .union(modelMaterialTargets)
                .union(soundPlaybackProgram.liveConsumerTargets)
                .union(propertyVectorScriptProgram.livePropertyInputTargets)
                .union(sceneScriptScalarProgram.livePropertyInputTargets)
                .union(sceneScriptStringProgram.livePropertyInputTargets)
        ) { targets, layer in
            targets.insert(.layer(layerID: layer.id, field: .scale))
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
                targets.insert(.layer(layerID: layer.id, field: .alpha))
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
