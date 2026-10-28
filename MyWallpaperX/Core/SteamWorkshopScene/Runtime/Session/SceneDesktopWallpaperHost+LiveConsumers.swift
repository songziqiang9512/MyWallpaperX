import Foundation

extension SceneDesktopWallpaperHost {
    /// Shared preparation facts for user-property and scalar-script inputs.
    /// This projection never constructs a VM or waits for surface resources.
    static func imageLayerModulationConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        sourceMaterialCandidateConsumerLayerIDs: Set<Int>
    ) -> Set<SceneDynamicTarget> {
        let referencedProviderLayerIDs = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
                .map(\.providerLayerID)
        )
        return descriptor.layers.reduce(into: []) { targets, layer in
            guard layer.contentKind == "image" else { return }
            // Visibility changes composition, not the prepared consumer's
            // lifetime. Hidden sources retain their latest value.
            var hasColorConsumer = layer.supportsDirectLayerColorConsumer
            // Completed sources own their tint. Only an ordinary capture
            // retains this downstream layer multiplier.
            if !hasColorConsumer, layer.supportsUserPropertyLayerColorConsumer,
               !sourceMaterialCandidateConsumerLayerIDs.contains(layer.id),
               let claim = resolvedMaterialExecutionCapabilities.claim(layerID: layer.id),
               let capability = resolvedMaterialExecutionCapabilities.resolve(claim.token),
               case .capturedLayerTexture = capability.sourceRoute,
               case .none = capability.dependencyOwnership {
                hasColorConsumer = true
            }
            if hasColorConsumer {
                targets.insert(.layer(layerID: layer.id, field: .color))
            }
            if layer.supportsUserPropertyImageSourceModulationConsumer,
               !sourceMaterialCandidateConsumerLayerIDs.contains(layer.id),
               !referencedProviderLayerIDs.contains(layer.id), hasColorConsumer {
                targets.insert(.layer(layerID: layer.id, field: .brightness))
            }
        }
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
        preparedStaticModelLayerIDs: Set<Int>,
        preparedImageMaterialTargets: Set<SceneDynamicTarget>,
        preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget> = [],
        sourceMaterialCandidateConsumerLayerIDs: Set<Int> = [],
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        propertyVectorScriptProgram: SceneScriptVectorProgram,
        sceneScriptScalarProgram: SceneScriptScalarProgram,
        sceneScriptStringProgram: SceneScriptStringProgram,
        propertyDefinitions: [SceneUserPropertyDefinition] = []
    ) -> ScenePropertyLiveUpdateState {
        let scriptUserPropertyConsumerTargetsByKey = [
            propertyVectorScriptProgram.liveUserPropertyConsumerTargetsByKey,
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
                preparedImageMaterialTargets: preparedImageMaterialTargets,
                preparedDirectModelAnimationVisibilityTargets:
                    preparedDirectModelAnimationVisibilityTargets,
                sourceMaterialCandidateConsumerLayerIDs:
                    sourceMaterialCandidateConsumerLayerIDs,
                preparedParticleVisibilityLayerIDs:
                    preparedParticleVisibilityLayerIDs,
                propertyVectorScriptProgram: propertyVectorScriptProgram,
                sceneScriptScalarProgram: sceneScriptScalarProgram,
                sceneScriptStringProgram: sceneScriptStringProgram
            ),
            scriptUserPropertyConsumerTargetsByKey:
                scriptUserPropertyConsumerTargetsByKey,
            propertyDefinitions: propertyDefinitions
        )
    }

    static func activeLiveConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        soundPlaybackProgram: SceneSoundPlaybackProgram,
        preparedStaticModelLayerIDs: Set<Int>,
        preparedImageMaterialTargets: Set<SceneDynamicTarget>,
        preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget> = [],
        sourceMaterialCandidateConsumerLayerIDs: Set<Int> = [],
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
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
                case .zoom:
                    return hasOrthographicCamera && descriptor.camera.default2DInputLayerID != nil
                        ? instruction.target : nil
                case .origin, .eye, .center, .up:
                    return nil
                }
            }
        )
        let referencedProviderLayerIDs = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
                .map(\.providerLayerID)
        )
        let layerVisibilityTargets = Set(
            SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor,
                candidates: propertyBindingProgram.liveLayerVisibilityTargets,
                preparedStaticModelLayerIDs: preparedStaticModelLayerIDs
            ).filter { target in
                guard case let .layer(layerID, .visibility) = target else {
                    return false
                }
                if descriptor.layers.first(where: { $0.id == layerID })?.contentKind == "quad" {
                    guard let claim = resolvedMaterialExecutionCapabilities.claim(layerID: layerID),
                          let capability = resolvedMaterialExecutionCapabilities.resolve(claim.token),
                          case .transparentDirectDraw = capability.sourceRoute,
                          !capability.materials.isEmpty else { return false }
                    return true
                }
                if let layer = descriptor.layers.first(where: { $0.id == layerID }),
                   layer.contentKind == "composition",
                   !layer.dependencyLayerIDs.isEmpty {
                    // A future-visible source needs an actually prepared
                    // dependency closure, even while capture is skipped hidden.
                    return resolvedMaterialExecutionCapabilities.executionLayerIDs
                        .contains(layerID)
                }
                guard utilityPlans[layerID]?.kind == .fullscreen else {
                    return true
                }
                // A legal standalone fullscreen without any effects has no
                // output to prepare. Potentially active effects still require
                // the actual execution capability and capture below.
                if let layer = descriptor.layers.first(where: { $0.id == layerID }),
                   layer.effects.isEmpty, layer.authoredDependencies.isEmpty,
                   utilityPlans[layerID]?.requiresNamedTarget == false,
                   !referencedProviderLayerIDs.contains(layerID) {
                    return true
                }
                return resolvedMaterialExecutionCapabilities.executionLayerIDs
                    .contains(layerID)
                    && utilityPlans[layerID]?.shouldCapture == true
            }
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
                .union(imageLayerModulationConsumerTargets(
                    in: descriptor,
                    resolvedMaterialExecutionCapabilities:
                        resolvedMaterialExecutionCapabilities,
                    sourceMaterialCandidateConsumerLayerIDs:
                        sourceMaterialCandidateConsumerLayerIDs
                ))
                .union(propertyBindingProgram.instructions.compactMap {
                    guard case let .scene(field) = $0.target else { return nil }
                    switch field {
                    case .clearColor:
                        guard descriptor.camera.clearEnabled else { return nil }
                    case .bloomHDRStrength, .bloomHDRThreshold, .bloomHDRScatter,
                         .bloomHDRFeather, .bloomHDRIterations:
                        guard descriptor.camera.bloom.hdr != nil else { return nil }
                    case .bloomStrength, .bloomThreshold:
                        guard descriptor.camera.bloom.hdr == nil else { return nil }
                    default:
                        break
                    }
                    return $0.target
                })
                .union(cameraTargets)
                .union(lightTargets)
                .union(layerVisibilityTargets)
                .union(preparedParticleVisibilityLayerIDs.map {
                    .layer(layerID: $0, field: .visibility)
                })
                .union(modelMaterialTargets)
                .union(preparedImageMaterialTargets)
                .union(preparedDirectModelAnimationVisibilityTargets)
                .union(soundPlaybackProgram.liveConsumerTargets)
                .union(propertyVectorScriptProgram.livePropertyInputTargets)
                .union(sceneScriptScalarProgram.livePropertyInputTargets)
                .union(sceneScriptStringProgram.livePropertyInputTargets)
        ) { targets, layer in
            targets.insert(.layer(layerID: layer.id, field: .scale))
            switch layer.contentKind {
            case "image":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
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
                      layer.textStyle != nil else { return }
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
