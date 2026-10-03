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
        frameDepthLeases: inout [SceneParticleDepthTargetLease],
        particleBatches: inout [SceneParticleDrawBatch],
        particlePerformanceObservations: inout [SceneParticlePerformanceObservation]?,
        mainPassForSubmission: inout SceneMainPassEncoder?,
        reflectionFrame: inout ReflectionFrame?,
        compositionGroupRuntime: inout SceneCompositionGroupFrameRuntime?
    ) -> FrameOutcome? {
        performanceTelemetry?.beginStage("source-update")
        let hubSourceUpdateStart = ProcessInfo.processInfo.systemUptime
        encodeSourceUpdates?(commandBuffer, sourceUpdateTransaction)
        performanceTelemetry?.endStage("source-update")
        hubStage(.sourceUpdateMicros, hubSourceUpdateStart)
        performanceTelemetry?.beginStage("world-resolve")
        let hubWorldResolveStart = ProcessInfo.processInfo.systemUptime
        let frameDescriptor = frameProjection.descriptor
        let frameLayersByID = frameProjection.layersByID
        let frameWorldFrames = frameProjection.worldFrames
        performanceTelemetry?.endStage("world-resolve")
        hubStage(.worldResolveMicros, hubWorldResolveStart)
        performanceTelemetry?.beginStage("prologue")
        let hubPrologueStart = ProcessInfo.processInfo.systemUptime
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
        performanceTelemetry?.beginStage("prepass-encoder")
        let (mainPass, groups) = makeScenePass(target: mainTarget,
            clearEnabled: frameDescriptor.camera.clearEnabled || (sceneColor != nil && sceneColor?.previous == nil),
            pool: offscreenTexturePool, visibleLayerIDs: frameVisibleLayerIDs,
            viewportSize: viewportSize, commandBuffer: commandBuffer)
        compositionGroupRuntime = groups
        mainPassForSubmission = mainPass
        performanceTelemetry?.endStage("prepass-encoder")
        let reflection = ReflectionFrame(pool: offscreenTexturePool, mainPass: mainPass,
            groupRuntime: compositionGroupRuntime, commandBuffer: commandBuffer,
            frameEpoch: textureRegistry.frameEpoch)
        reflectionFrame = reflection
        let environmentSource: (MTLCommandBuffer) -> SceneFrameTextureResource? = reflection.resolve
        performanceTelemetry?.beginStage("frame-admission")
        let hubFrameAdmissionStart = ProcessInfo.processInfo.systemUptime
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
            compositionGroupRuntime: compositionGroupRuntime
        )
        performanceTelemetry?.endStage("frame-admission")
        hubStage(.frameAdmissionMicros, hubFrameAdmissionStart)
        let resolvedMaterialFrameTargetPlans: [Int: SceneResolvedMaterialFrameTargetPlan]
        switch resolvedMaterialFrameAdmission {
        case let .ready(plans):
            resolvedMaterialFrameTargetPlans = plans
        case let .deferred(reasonCode):
            return .deferred(reasonCode: reasonCode)
        case let .rejected(reasonCode):
            return .dropped(reasonCode: reasonCode)
        }
        performanceTelemetry?.endStage("prologue")
        hubStage(.prologueMicros, hubPrologueStart)
        performanceTelemetry?.beginStage("prepass")
        let hubPrepassStart = ProcessInfo.processInfo.systemUptime
        // Sub-stages exist so the composite prepass cost can be attributed
        // before any optimization; they are additive observations only.
        performanceTelemetry?.beginStage("prepass-particles")
        // CPU simulation produces immutable instances even while a display is
        // unavailable. Update even empty batches to clear stale current slots;
        // only the actual uploaded draw set may request depth or background copies.
        particleBatches = preparedParticleBatches.filter {
            $0.instanceBuffer.update(device: device, instances: $0.instances)
                && $0.instanceBuffer.currentDrawState() != nil
        }
        let particleBatchesByID = Dictionary(grouping: particleBatches, by: \.layerID)
        performanceTelemetry?.endStage("prepass-particles")
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
        var scratchReady = false
        if let pool = offscreenTexturePool,
           let targets = reserveOptionalEffectScratch(requiresShadow: shadowCandidates != nil,
            pool: pool, imageTextures: imageTextures,
            frameContext: frameContext, framePlans: resolvedMaterialFrameTargetPlans,
            visibleLayerIDs: frameVisibleLayerIDs, orderedLayers: orderedLayers,
            worldFrames: frameWorldFrames, cameraFrame: cameraFrame, parallax: parallaxConfiguration,
            terminalExtent: sceneColor == nil && displayMappingPostProcess != nil
                ? (drawable.texture.width, drawable.texture.height) : nil,
            commandBuffer: commandBuffer) {
            reflection.admit(targets); scratchReady = true
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
                        mainPass: mainPass, groups: compositionGroupRuntime)
                },
                recordsEvidence: SceneDesktopWallpaperHost.usesDebugEvidenceWindow && frameContext.frameIndex <= 2)
        }
        var stopsAfterClaimedFailure = false
        var forwardGraphProviderLayerIDs: Set<Int> = []
        if let imagePipeline {
            performanceTelemetry?.beginStage("prepass-forward-providers")
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
            performanceTelemetry?.endStage("prepass-forward-providers")
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
                mainPass: mainPass, groups: compositionGroupRuntime, pool: pool,
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
        performanceTelemetry?.endStage("prepass")
        hubStage(.prepassMicros, hubPrepassStart)
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
