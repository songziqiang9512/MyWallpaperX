import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    /// Produces frame-local passes and leases into renderFrame's rollback
    /// scope; admission and prepass never acquire submission ownership.
    func encodeSceneDrawing(
        imageTextures: SceneBaseImageTextureSnapshot,
        layerTopology: SceneScriptLayerTopologySnapshot?,
        userPropertyTextures: [String: MTLTexture],
        userPropertyTextureStates: [SceneUserPropertyTextureIdentity: SceneTextureProviderState],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        specializedBaseTextureSamplings: [Int: SceneTextureSampling],
        imagePipeline: SceneImageLayerPipeline?,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        preparedParticleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        encodeSourceUpdates: ((MTLCommandBuffer, SceneSourceUpdateTransaction) -> Void)?,
        performanceTelemetry: SceneFramePerformanceTelemetry?,
        drawable: CAMetalDrawable,
        commandBuffer: MTLCommandBuffer,
        sourceUpdateTransaction: SceneSourceUpdateTransaction,
        modelFrame: StaticModelFrame,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        mainTarget: MTLTexture,
        sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
        displayMappingInput: inout SceneDisplayMappingPostProcess.Input,
        frameDepthLeases: inout [SceneParticleDepthTargetLease],
        particleBatches: inout [SceneParticleDrawBatch],
        particlePerformanceObservations: inout [SceneParticlePerformanceObservation]?,
        mainPassForSubmission: inout SceneMainPassEncoder?,
        reflectionFrame: inout ReflectionFrame?,
        compositionGroupRuntime: inout SceneCompositionGroupFrameRuntime?
    ) -> FrameOutcome? {
        var imageTextures = imageTextures
#if DEBUG
        performanceTelemetry?.beginStage("source-update")
#endif

#if DEBUG
        let hubSourceUpdateStart = ProcessInfo.processInfo.systemUptime
#endif
        encodeSourceUpdates?(commandBuffer, sourceUpdateTransaction)
#if DEBUG
        performanceTelemetry?.endStage("source-update")
#endif

#if DEBUG
        hubStage(.sourceUpdateMicros, hubSourceUpdateStart)
#endif
#if DEBUG
        performanceTelemetry?.beginStage("world-resolve")
#endif

#if DEBUG
        let hubWorldResolveStart = ProcessInfo.processInfo.systemUptime
#endif
        let frameDescriptor = frameProjection.descriptor
        let frameLayersByID = frameProjection.layersByID
        let frameWorldFrames = frameProjection.worldFrames
#if DEBUG
        performanceTelemetry?.endStage("world-resolve")
#endif

#if DEBUG
        hubStage(.worldResolveMicros, hubWorldResolveStart)
#endif
#if DEBUG
        performanceTelemetry?.beginStage("prologue")
#endif

#if DEBUG
        let hubPrologueStart = ProcessInfo.processInfo.systemUptime
#endif
        let viewportSize = frameContext.screenSize
        let time = Float(frameContext.sceneTime)
        let parallaxMouseNormalized = frameContext.cameraParallaxPosition
        let parallaxConfiguration = parallaxConfiguration(
            cameraFrame: cameraFrame,

            viewportSize: viewportSize,
            dynamicValues: frameContext.dynamicValues
        )
        let orderedLayers = frameProjection.orderedLayers
        let frameVisibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: frameDescriptor, layersByID: frameLayersByID,
            snapshot: frameContext.dynamicValues)
        let activeStaticModelNamedAlbedoLayerIDs = frameVisibleLayerIDs
            .intersection(staticModelResources.namedAlbedoLayerIDs)
        let dynamicLightColors = Dictionary(uniqueKeysWithValues: frameProjection.lightLayerIDs.compactMap { layerID -> (Int, SIMD3<Float>)? in
                guard let layer = frameLayersByID[layerID] else { return nil }
                return (
                    layer.id,
                    SceneDynamicLayerValues.color(
                        layerID: layer.id,
                        authoredValue: layer.colorRGB,
                        snapshot: frameContext.dynamicValues
                    )
                )
            }
        )
        let frameLightSnapshot = SceneLightSnapshot.make(
            descriptor: frameDescriptor,
            worldFramesByLayerID: frameWorldFrames, dynamicLayerColors: dynamicLightColors,
            dynamicSnapshot: frameContext.dynamicValues,
            candidateLayerIDs: frameProjection.lightLayerIDs,
            layersByID: frameLayersByID,
            visibleLayerIDs: frameVisibleLayerIDs
        )
#if DEBUG
        performanceTelemetry?.beginStage("prepass-encoder")
#endif

        let sourceGeometriesByRootID = Dictionary(uniqueKeysWithValues:
            frameProjection.utilityExecution.localSourceRootIDs.compactMap { rootID -> (Int, SceneCompositionSourceGeometry)? in
                guard let layer = frameLayersByID[rootID] else { return nil }
                let model = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                )
                return SceneCompositionSourceGeometry(
                    authoredRenderSizeWH: layer.renderSizeWH,
                    worldMVP: cameraFrame.viewProjection(for: layer) * model
                ).map { (rootID, $0) }
            })
        let (mainPass, groups) = makeScenePass(target: mainTarget,
            clearEnabled: frameDescriptor.camera.clearEnabled || (sceneColor != nil && sceneColor?.previous == nil),
            dynamicValues: frameContext.dynamicValues,
            pool: offscreenTexturePool,
            viewportSize: viewportSize, commandBuffer: commandBuffer,
            utilityExecution: frameProjection.utilityExecution,
            sourceGeometriesByRootID: sourceGeometriesByRootID)
        compositionGroupRuntime = groups
        mainPassForSubmission = mainPass
#if DEBUG
        performanceTelemetry?.endStage("prepass-encoder")
#endif

        let reflection = ReflectionFrame(pool: offscreenTexturePool, mainPass: mainPass,
            groupRuntime: compositionGroupRuntime, commandBuffer: commandBuffer,
            frameEpoch: textureRegistry.frameEpoch)
        reflectionFrame = reflection
        let environmentSource: (MTLCommandBuffer) -> SceneFrameTextureResource? = reflection.resolve
#if DEBUG
        performanceTelemetry?.beginStage("frame-admission")
#endif

#if DEBUG
        let hubFrameAdmissionStart = ProcessInfo.processInfo.systemUptime
#endif
        let resolvedMaterialFrameAdmission = admitResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
            frameVisibleLayerIDs: frameVisibleLayerIDs,
            performanceTelemetry: performanceTelemetry,
            specializedBaseTextureSamplings: specializedBaseTextureSamplings,
            imagePipeline: imagePipeline,
            userPropertyTextures: userPropertyTextures,
            userPropertyStates: userPropertyTextureStates,
            mediaThumbnail: mediaThumbnail,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            worldFramesByLayerID: frameWorldFrames,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            mainTarget: mainTarget,
            commandBuffer: commandBuffer,
            environmentSource: environmentSource,
            frameLightSnapshot: frameLightSnapshot,
            compositionGroupRuntime: compositionGroupRuntime,
            preparationLayers: frameProjection.preparationLayers,
            utilityExecution: frameProjection.utilityExecution
        )
#if DEBUG
        performanceTelemetry?.endStage("frame-admission")
#endif

#if DEBUG
        hubStage(.frameAdmissionMicros, hubFrameAdmissionStart)
#endif
        let resolvedMaterialFrameTargetPlans: [Int: SceneResolvedMaterialFrameTargetPlan]
        var preparationRequests: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]
        let resourceBundle: SceneResolvedMaterialFrameResourceBundle?
        switch resolvedMaterialFrameAdmission {
        case let .ready(plans, requests, bundle):
            resolvedMaterialFrameTargetPlans = plans
            preparationRequests = requests
            resourceBundle = bundle
        case let .deferred(reasonCode):
            return .deferred(reasonCode: reasonCode)
        case let .rejected(reasonCode):
            return .dropped(reasonCode: reasonCode)
        }
        defer { resourceBundle?.cancel() }
#if DEBUG
        performanceTelemetry?.endStage("prologue")
#endif

#if DEBUG
        hubStage(.prologueMicros, hubPrologueStart)
#endif
#if DEBUG
        performanceTelemetry?.beginStage("prepass")
#endif

#if DEBUG
        let hubPrepassStart = ProcessInfo.processInfo.systemUptime
#endif
        // Sub-stages exist so the composite prepass cost can be attributed
        // before any optimization; they are additive observations only.
#if DEBUG
        performanceTelemetry?.beginStage("prepass-particles")
#endif

        // CPU simulation produces immutable instances even while a display is
        // unavailable. Update even empty batches to clear stale current slots;
        // only the actual uploaded draw set may request depth or background copies.
        particleBatches = preparedParticleBatches.filter {
            $0.instanceBuffer.update(device: device, instances: $0.instances)
                && $0.instanceBuffer.currentDrawState() != nil
        }
        let particleBatchesByID = Dictionary(grouping: particleBatches, by: \.layerID)
#if DEBUG
        performanceTelemetry?.endStage("prepass-particles")
#endif

        let shadowLights = frameLightSnapshot.shadowLights
        let hasShadowReceiver = !shadowLights.isEmpty && orderedLayers.contains { layer in
            frameVisibleLayerIDs.contains(layer.id)
                && staticModelResources[layer.id]?.contains(where: { $0.material.receivesLighting }) == true
        }
        let preparesNamedModelShadow = hasShadowReceiver && !activeStaticModelNamedAlbedoLayerIDs.isEmpty
        let shadowCandidates = hasShadowReceiver && !preparesNamedModelShadow
            ? shadowDrawCandidates(orderedLayers: orderedLayers, visible: frameVisibleLayerIDs,
                worldFrames: frameWorldFrames, snapshot: frameContext.dynamicValues,
                groups: compositionGroupRuntime) : nil
        // All callers inspect the same pre-source image/plan facts. Preserve
        // their short cuts while avoiding duplicate reflection-demand scans.
        var reflectionDemand: Bool?
        func requiresReflection() -> Bool {
            if let reflectionDemand { return reflectionDemand }
            let needed = hasReflectionConsumers(imageTextures: imageTextures,
                framePlans: resolvedMaterialFrameTargetPlans, visibleLayerIDs: frameVisibleLayerIDs,
                orderedLayers: orderedLayers)
            reflectionDemand = needed
            return needed
        }
        displayMappingInput = displayMappingPostProcess?.input(for: drawable.texture,
            clearEnabled: frameDescriptor.camera.clearEnabled,
            hasPersistentSceneColor: sceneColor != nil, hasShadowReceiver: hasShadowReceiver,
            hasSourceMaterials: imageCompositor.resolvedMaterialRuntime?.sourceMaterials.isEmpty == false,
            requiresReflection: requiresReflection) ?? .textureSource
        var scratchReady = false
        var optionalScratch: [SceneOffscreenTexturePool.PinnedTexture]?
        if let pool = offscreenTexturePool,
           let targets = reserveOptionalEffectScratch(requiresShadow: shadowCandidates != nil,
            requiresReflection: requiresReflection,
            pool: pool, imageTextures: imageTextures,
            frameContext: frameContext, framePlans: resolvedMaterialFrameTargetPlans,
            visibleLayerIDs: frameVisibleLayerIDs, orderedLayers: orderedLayers,
            worldFrames: frameWorldFrames, cameraFrame: cameraFrame, parallax: parallaxConfiguration,
            terminalExtent: sceneColor == nil && displayMappingPostProcess != nil
                ? (drawable.texture.width, drawable.texture.height) : nil,
            commandBuffer: commandBuffer) {
            optionalScratch = targets; scratchReady = true
        }
        if scratchReady, let shadowCandidates, let pool = offscreenTexturePool {
            prepareModelShadow(state: modelFrame, candidates: shadowCandidates, lights: shadowLights,
                orderedLayers: orderedLayers, visible: frameVisibleLayerIDs,
                batches: particleBatchesByID, particlePipeline: particlePipeline,
                mainPass: mainPass, groups: compositionGroupRuntime, pool: pool,
                commandBuffer: commandBuffer, leases: &frameDepthLeases,
                mandatoryCapacity: {
                    prepareTerminalCapacity(sceneColor: sceneColor,
                        target: drawable.texture, dynamicValues: frameContext.dynamicValues)
                    && prepareFramebufferSnapshotCapacity(orderedLayers: orderedLayers,
                        visible: frameVisibleLayerIDs, framePlans: resolvedMaterialFrameTargetPlans,
                        imageTextures: imageTextures, frameContext: frameContext,
                        batches: particleBatchesByID, particlePipeline: particlePipeline,
                        mainPass: mainPass, groups: compositionGroupRuntime,
                        utilityExecution: frameProjection.utilityExecution)
                },
                recordsEvidence: SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2,
                cameraFrame: cameraFrame)
        }
        var preparedEnvironment: SceneFrameTextureResource?
        if let targets = optionalScratch {
            var history: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?
            // The late named-shadow owner prepares its own ordered depth set.
            // Do not pre-acquire leases that it would replace on this frame.
            if !preparesNamedModelShadow,
               requiresReflection(),
               let pool = offscreenTexturePool,
               let candidates = shadowDrawCandidates(orderedLayers: orderedLayers,
                visible: frameVisibleLayerIDs, worldFrames: frameWorldFrames,
                snapshot: frameContext.dynamicValues, groups: compositionGroupRuntime),
               prepareMandatoryDepth(state: modelFrame, candidates: candidates,
                orderedLayers: orderedLayers, visible: frameVisibleLayerIDs,
                batches: particleBatchesByID, particlePipeline: particlePipeline,
                mainPass: mainPass, groups: compositionGroupRuntime, leases: &frameDepthLeases),
               prepareTerminalCapacity(sceneColor: sceneColor, target: drawable.texture,
                dynamicValues: frameContext.dynamicValues),
               prepareFramebufferSnapshotCapacity(orderedLayers: orderedLayers,
                visible: frameVisibleLayerIDs, framePlans: resolvedMaterialFrameTargetPlans,
                imageTextures: imageTextures, frameContext: frameContext,
                batches: particleBatchesByID, particlePipeline: particlePipeline,
                mainPass: mainPass, groups: compositionGroupRuntime,
                utilityExecution: frameProjection.utilityExecution) {
                history = sceneColor ?? imageCompositor.resolvedMaterialRuntime?.reserveSceneColor(
                    pool: pool, width: mainTarget.width, height: mainTarget.height,
                    frameIndex: frameContext.frameIndex, commandBuffer: commandBuffer, intent: .snapshot)
            }
            reflection.admit(targets, sceneColor: history)
            // history is assigned only after the complete mandatory-capacity gate.
            if history != nil { preparedEnvironment = reflection.resolve(commandBuffer) }
        }
        // No coordinator lock is held here. Late named dependencies retain
        // their ordered preparation; they cannot promise early environment capacity.
        if let runtime = imageCompositor.resolvedMaterialRuntime {
            let atom: SceneFrameTextureLookupStatus = preparedEnvironment.map { .ready($0) } ?? .unavailable
            let snapshot = SceneFrameTextureRegistrySnapshot(frameEpoch: textureRegistry.frameEpoch,
                frameIndex: frameContext.frameIndex, entries: [.sceneEnvironment: atom])
            guard runtime.overlayPreparedSceneEnvironment(from: snapshot) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure("frame-environment-overlay-rejected")
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .dropped(reasonCode: "frame-environment-overlay-rejected")
            }
        }
#if DEBUG
        performanceTelemetry?.beginStage("frame-admission")
#endif

        // Source evaluation is optional until its complete atom is ready.
        // Protect graph/display/named-capture capacity first, then replace only
        // the same unlit source used to prepare the already-reserved requests.
        if let runtime = imageCompositor.resolvedMaterialRuntime, !runtime.sourceMaterials.isEmpty,
           prepareTerminalCapacity(sceneColor: sceneColor, target: drawable.texture,
                dynamicValues: frameContext.dynamicValues),
           prepareFramebufferSnapshotCapacity(orderedLayers: orderedLayers,
                visible: frameVisibleLayerIDs, framePlans: resolvedMaterialFrameTargetPlans,
                imageTextures: imageTextures, frameContext: frameContext,
                batches: particleBatchesByID, particlePipeline: particlePipeline,
                mainPass: mainPass, groups: compositionGroupRuntime,
                utilityExecution: frameProjection.utilityExecution) {
            let activeConsumers = Set(resolvedMaterialFrameTargetPlans.keys)
            let demanded = orderedLayers.compactMap { layer -> SceneResolvedMaterialRuntimeBridge.SourceMaterialConsumer? in
                guard let consumer = runtime.sourceMaterialConsumer(layerID: layer.id, modelPath: layer.imagePath) else { return nil }
                let needed = frameVisibleLayerIDs.contains(layer.id)
                    || dependencyRuntime.providerBindingsByLayerID[layer.id]?.contains {
                        activeConsumers.contains($0.consumerLayerID)
                    } == true
                    || dependencyRuntime.staticModelConsumerLayerIDsByProviderLayerID[layer.id]
                        .map { !$0.isDisjoint(with: activeStaticModelNamedAlbedoLayerIDs) } == true
                return needed ? consumer : nil
            }
            let terminalPins: [SceneOffscreenTexturePool.PinnedTexture]?
            if !demanded.isEmpty, sceneColor == nil, displayMappingPostProcess != nil {
                // Reserve the existing neutral composition slot, not the
                // coordinator's one-shot display-export token. Terminal encode
                // later claims the same pending-buffer allocation.
                terminalPins = offscreenTexturePool?.reserveCompositionTargets(
                    dimensions: [(drawable.texture.width, drawable.texture.height)],
                    commandBuffer: commandBuffer)
            } else { terminalPins = [] }
            if let terminalPins {
                terminalPins.forEach { mainPass.retainCompositionPin($0.pin) }
                let originalSources = imageTextures
                imageTextures = runtime.prepareSourceMaterials(imageTextures: imageTextures,
                    consumers: demanded, registry: textureRegistry, pool: offscreenTexturePool,
                    mainPass: mainPass, commandBuffer: commandBuffer)
                preparationRequests = preparationRequests.map { request in
                    request.replacingSource(original: originalSources, prepared: imageTextures)
                }
            }
        }
#if DEBUG
        let hubFrameFinalizationStart = ProcessInfo.processInfo.systemUptime
#endif
        let finalized = finalizeResolvedMaterialFrameTargets(preparationRequests,
            resourceBundle: resourceBundle, pool: offscreenTexturePool,
            commandBuffer: commandBuffer, performanceTelemetry: performanceTelemetry)
#if DEBUG
        performanceTelemetry?.endStage("frame-admission")
#endif

#if DEBUG
        hubStage(.frameAdmissionMicros, hubFrameFinalizationStart)
#endif
        guard finalized else {
            return .dropped(reasonCode: "resolved-material-frame-preparation-rejected")
        }
        var stopsAfterClaimedFailure = false
        var forwardGraphProviderLayerIDs: Set<Int> = []
        if let imagePipeline {
#if DEBUG
            performanceTelemetry?.beginStage("prepass-forward-providers")
#endif

            if let prepared = prepareForwardDependencyProviders(
                orderedLayers: orderedLayers, layersByID: frameLayersByID,
                imageTextures: imageTextures,
                imagePipeline: imagePipeline,
                frameContext: frameContext,
                worldFramesByLayerID: frameWorldFrames,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration,
                viewportSize: viewportSize,
                mainPass: mainPass,
                framePlans: resolvedMaterialFrameTargetPlans,
                activeStaticModelConsumerLayerIDs:
                    activeStaticModelNamedAlbedoLayerIDs,
                commandBuffer: commandBuffer,
                executionTrace: effectExecutionTrace
            ) {
                forwardGraphProviderLayerIDs = prepared
            } else {
                stopsAfterClaimedFailure = true
            }
#if DEBUG
            performanceTelemetry?.endStage("prepass-forward-providers")
#endif

        }
        if !stopsAfterClaimedFailure, preparesNamedModelShadow,
           let pool = offscreenTexturePool, let imagePipeline {
            if let reason = prepareOrderedModelShadow(state: modelFrame, lights: shadowLights, lighting: frameLightSnapshot,
                orderedLayers: orderedLayers, visible: frameVisibleLayerIDs,
                activeNamedModels: activeStaticModelNamedAlbedoLayerIDs,
                forwardGraphProviders: forwardGraphProviderLayerIDs,
                framePlans: resolvedMaterialFrameTargetPlans, imageTextures: imageTextures,
                imagePipeline: imagePipeline, frameContext: frameContext, worldFrames: frameWorldFrames,
                cameraFrame: cameraFrame, parallax: parallaxConfiguration, viewportSize: viewportSize,
                batches: particleBatchesByID, particlePipeline: particlePipeline,
                mainPass: mainPass, groups: compositionGroupRuntime,
                utilityExecution: frameProjection.utilityExecution, pool: pool,
                commandBuffer: commandBuffer, leases: &frameDepthLeases,
                terminalCapacity: {
                    guard prepareTerminalCapacity(sceneColor: sceneColor, target: drawable.texture,
                        dynamicValues: frameContext.dynamicValues) else { return false }
                    if sceneColor == nil, displayMappingPostProcess != nil {
                        // Only capacity/pin here. The coordinator's one-shot
                        // display reservation still belongs to terminal encode.
                        guard let targets = pool.reserveCompositionTargets(
                            dimensions: [(drawable.texture.width, drawable.texture.height)],
                            commandBuffer: commandBuffer) else { return false }
                        targets.forEach { mainPass.retainCompositionPin($0.pin) }
                    }
                    return true
                }, recordsEvidence: SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2,
                executionTrace: effectExecutionTrace,
                environmentSource: reflection.scratchReady ? environmentSource : nil) {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(reason)
                stopsAfterClaimedFailure = true
            }
        }
#if DEBUG
        performanceTelemetry?.endStage("prepass")
#endif

#if DEBUG
        hubStage(.prepassMicros, hubPrepassStart)
#endif
        return encodeOrderedLayers(
            orderedLayers: orderedLayers,
            initiallyStopped: stopsAfterClaimedFailure,
            forwardGraphProviderLayerIDs: forwardGraphProviderLayerIDs,
            frameVisibleLayerIDs: frameVisibleLayerIDs,
            activeStaticModelNamedAlbedoLayerIDs: activeStaticModelNamedAlbedoLayerIDs,
            imageTextures: imageTextures,
            imagePipeline: imagePipeline,
            specializedBaseTextureSamplings: specializedBaseTextureSamplings,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
            resolvedMaterialFrameTargetPlans: resolvedMaterialFrameTargetPlans,
            frameContext: frameContext,
            frameWorldFrames: frameWorldFrames,
            cameraFrame: cameraFrame,
            parallaxMouseNormalized: parallaxMouseNormalized,
            parallaxConfiguration: parallaxConfiguration,
            viewportSize: viewportSize,
            time: time,
            offscreenTexturePool: offscreenTexturePool,
            frameLightSnapshot: frameLightSnapshot,
            reflection: reflection,
            environmentSource: environmentSource,
            modelFrame: modelFrame,
            mainPass: mainPass,
            compositionGroupRuntime: compositionGroupRuntime,
            commandBuffer: commandBuffer,
            effectExecutionTrace: effectExecutionTrace,
            particleBatchesByID: particleBatchesByID,
            particlePipeline: particlePipeline,
            frameDepthLeases: &frameDepthLeases,
            particlePerformanceObservations: &particlePerformanceObservations,
            performanceTelemetry: performanceTelemetry,
            sceneColor: sceneColor,
            frameProjection: frameProjection,
            layerTopology: layerTopology
        )
    }
}
