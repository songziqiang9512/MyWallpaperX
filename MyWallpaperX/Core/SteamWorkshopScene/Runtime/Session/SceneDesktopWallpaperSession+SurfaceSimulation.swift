import CoreGraphics
import simd

extension SceneDesktopWallpaperSession.Surface {
    /// Scoped paused property publication can change snapshot generation
    /// without advancing simulation. Reuse its frozen pose, not a stale camera.
    func sceneScriptPausedSurfaceInput(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot
    ) -> SceneScriptSurfaceInput? {
        guard let frame = simulationFrame else { return nil }
        let worlds: [Int: simd_float4x4]
        if !metalView.requiresSceneScriptCameraWorldFrames {
            worlds = [:]
        } else if frame.context.dynamicValues.generation == dynamicValues.generation,
                  frame.context.dynamicValues.frameIndex == dynamicValues.frameIndex {
            worlds = frame.projection.worldFrames
        } else {
            worlds = metalView.renderer.resolveFrameWorldProjection(layerTopology: frame.topology,
                dynamicValues: dynamicValues, puppetAttachmentFrames: frame.attachmentFrames).worldFrames
        }
        return metalView.sceneScriptSurfaceInput(timing: timing, dynamicValues: dynamicValues,
            descriptor: frame.projection.descriptor, layersByID: frame.projection.layersByID,
            worldFrames: worlds)
    }

    func updateSimulation(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
        puppetAnimationFrame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot,
        spriteTimes: [Int: Float],
        layerTopology: SceneScriptLayerTopologySnapshot,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = [],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = [],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        mediaInputGeneration: UInt64,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) {
        for playback in puppetPlaybackStates.values {
            playback.apply(scriptBoneMutations: puppetBoneMutations)
        }
        let cameraProperty = dynamicValues.cameraPropertyProjection()
        let parallaxDelay = cameraProperty.parallaxDelay
            ?? metalView.renderer.renderDescriptor.camera.parallaxDelay
        let parallaxMouseNormalized = metalView.parallaxPointerSmoother.advance(
            delta: timing.simulationFrameTime,
            delay: parallaxDelay
        )
        let frameContext = metalView.makeFrameContext(
            timing: timing, dynamicValues: dynamicValues,
            materialFunctionMutations: materialFunctionMutations,
            parallax: parallaxMouseNormalized, audioSpectrum: audioSpectrum
        )
        let spriteAnimationPlaybackTimes = spriteTimes
        // Paused redraws still consume the previous adopted frame's source and particle resources.
        if simulationFrame?.topology.topologyRevision != layerTopology.topologyRevision {
            let retired = layerTopology.destroyedAuthoredLayerIDs.subtracting(
                simulationFrame?.topology.destroyedAuthoredLayerIDs ?? [])
            if !retired.isEmpty {
                metalView.retireSpriteAnimations(layerIDs: retired)
                metalView.particlePipeline?.retire(layerIDs: retired)
            }
        }
        assert(
            metalView.spriteAnimationLayerIDs.allSatisfy {
                spriteAnimationPlaybackTimes[$0] != nil
            },
            "prepared texture animation is missing typed playback state"
        )
        metalView.pointerState.previous = metalView.pointerState.current
        let attachmentFrames = ScenePuppetAttachmentFrameSnapshot(
            framesByParentLayerID: puppetPlaybackStates.reduce(into: [:]) { result, entry in
                guard let samples = puppetAnimationFrame[entry.key] else { return }
                result[entry.key] = entry.value.prepareFrame(animationFrame: samples)
            }
        )
        let frameProjection = metalView.renderer.resolveFrameWorldProjection(
            layerTopology: layerTopology, dynamicValues: dynamicValues,
            puppetAttachmentFrames: attachmentFrames
        )
        let cameraFrame = metalView.renderer.makeCameraFrame(
            frameContext: frameContext, descriptor: frameProjection.descriptor,
            layersByID: frameProjection.layersByID, worldFrames: frameProjection.worldFrames
        )
        let particleBatches = advanceParticles(
            timing: timing, dynamicValues: dynamicValues,
            frameContext: frameContext, cameraFrame: cameraFrame,
            frameProjection: frameProjection, performanceTelemetry: performanceTelemetry
        )
        simulationFrame = SceneMetalView.SimulationFrame(
            timing: timing, context: frameContext, camera: cameraFrame,
            projection: frameProjection, particles: particleBatches,
            topology: layerTopology,
            mediaThumbnail: mediaThumbnail, mediaInputGeneration: mediaInputGeneration,
            spriteTimes: spriteAnimationPlaybackTimes, puppetAnimationFrame: puppetAnimationFrame,
            puppetRenderFrames: puppetPlaybackStates.compactMapValues { $0.renderFrame },
            attachmentFrames: attachmentFrames
        )
    }

}
