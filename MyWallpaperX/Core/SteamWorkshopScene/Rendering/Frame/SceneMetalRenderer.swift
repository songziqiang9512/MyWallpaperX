import Foundation
import Metal
import QuartzCore
import simd
struct SceneMetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderDescriptor: SceneRenderDescriptor
    let imageCompositor: SceneImageLayerCompositor
    // E2/Q1T: scene-level bloom post process (authored general.bloom).
    // Class instance so the enclosing struct stays value-semantics.
    let bloomPostProcess: SceneBloomPostProcess?
    // Terminal SDR mapping consumes a distinct, unmapped scene color source.
    let displayMappingPostProcess: SceneDisplayMappingPostProcess?
    let stockNoiseTextures: SceneStockNoiseTextureStore
    let pipelineRepository: SceneImageEffectPipelineRepository
    let visibleLayerIDs: Set<Int>
    let authoredLayers: [SceneRenderDescriptor.Layer]
    // Cached transforms propagate parent pivot/orientation without double-scaling child quads.
    let worldFramesByLayerID: [Int: simd_float4x4]
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let lightLayerIDs: [Int]
    /// Prepared group membership and execution order; passes remain frame-local.
    let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
    var utilityCaptureLayerIDs: Set<Int> { utilityExecution.captureLayerIDs }
    let effectAdmissionCatalog: SceneEffectAdmissionCatalog
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let staticModelResources: ScenePreparedStaticModelResources
    let spotLightRuntime: SceneSpotLightRuntime
    let dependencyRuntime: SceneDependencyFrameRuntime
    /// The dependency graph and authored order are launch-scoped facts. Keep
    /// the validated topological order with the renderer so normal frames do
    /// not rebuild the same order for admission and request preparation.
    let resolvedMaterialPreparationLayerIDs: [Int]?; let resolvedMaterialPreparationLayers: [SceneRenderDescriptor.Layer]?
    let textureRegistry = SceneFrameTextureRegistry()
    let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
    let effectExecutionTelemetry = SceneEffectExecutionTelemetry()
    let staticModelDepthTargetPool = SceneParticleDepthTargetPool()
    /// Dynamic layer descriptor projection is invalidated by the runtime's
    /// topology revision, not by every frame that reuses the same snapshot.
    let dynamicLayerTopologyCache = SceneDynamicLayerRenderTopologyCache()
    func renderFrame(
        imageTextures: SceneBaseImageTextureSnapshot,
        layerTopology: SceneScriptLayerTopologySnapshot? = nil,
        userPropertyTextures: [String: MTLTexture] = [:],
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot = .empty,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:],
        imagePipeline: SceneImageLayerPipeline?,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        particleBatches preparedParticleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        encodeSourceUpdates: ((
            MTLCommandBuffer, SceneSourceUpdateTransaction
        ) -> Void)? = nil,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        onDrawableWillPresent: ((CAMetalDrawable) -> Void)? = nil,
        displayOutput: SceneDisplayMappingPostProcess.Output = .sRGB,
        to drawable: CAMetalDrawable
    ) -> FrameOutcome {
        // Always-on renderer CPU time. Start is unconditional (the existing
        // cpuStart below is telemetry-gated); the defer covers every return
        // path including the resolved-material busy-guard below.
        let hubRenderStart = ProcessInfo.processInfo.systemUptime
        defer {
            ScenePerformanceCounterHub.shared.add(
                .rendererMicros,
                ScenePerformanceCounterHub.micros(since: hubRenderStart)
            )
        }
        var particleSubmissionCommandBuffer: MTLCommandBuffer? = nil
        var didTransferFrameOwnership = false
        guard !imageCompositor.shouldDeferResolvedMaterialFrame else {
            return .deferred(reasonCode: "resolved-material-frame-in-flight")
        }
        let cpuStart = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            performanceTelemetry?.recordCommandBufferUnavailable()
            return .deferred(reasonCode: "command-buffer-unavailable")
        }
        particleSubmissionCommandBuffer = commandBuffer
        let sourceUpdateTransaction = SceneSourceUpdateTransaction()
        // Unsubmitted source and registry state roll back together.
        defer {
            if !didTransferFrameOwnership {
                sourceUpdateTransaction.cancel()
                imageCompositor.cancelUnsubmittedResolvedMaterialFrame(on: commandBuffer)
                imageCompositor.resolvedMaterialRuntime?.endFrame()
                discardUnsubmittedFrameResources()
            }
        }
        // Submitted candidates remain provisional until the host barrier.
        var frameDepthLeases: [SceneParticleDepthTargetLease] = []
        defer { if !didTransferFrameOwnership { frameDepthLeases.forEach { $0.cancel() } } }
        let modelFrame = StaticModelFrame()
        defer { if !didTransferFrameOwnership { modelFrame.cancel() } }
        // M2 Patch A：effect 执行证据链（每帧 trace + SHA256 cohort）只属于
        // 诊断/基准模式（runtime-architecture §5.5）；正常播放为 nil，
        // 全部 record 调用点为 optional 旁路。
        let effectExecutionTrace: SceneEffectExecutionFrameTrace? =
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            ? effectExecutionTelemetry.makeFrame(frameIndex: frameContext.frameIndex)
            : nil
        beginTextureFrame(imageTextures, userPropertyTextures, userPropertyTextureStates,
                          mediaThumbnail, frameContext)
        let colorStart = encodeSceneColorStart(pool: offscreenTexturePool, target: drawable.texture,
            frameIndex: frameContext.frameIndex, clearEnabled: frameProjection.descriptor.camera.clearEnabled,
            commandBuffer: commandBuffer)
        if let failure = colorStart.failure { return failure }
        let sceneColor = colorStart.reservation
        let mainTarget = sceneColor?.raw ?? drawable.texture
        var particleBatches: [SceneParticleDrawBatch] = []
        var particlePerformanceObservations: [SceneParticlePerformanceObservation]? =
            performanceTelemetry == nil ? nil : []
        defer {
            if !didTransferFrameOwnership {
                if let commandBuffer = particleSubmissionCommandBuffer,
                   commandBuffer.status == .notEnqueued {
                    // A command accepted by Metal owns every marked slot until its
                    // completion handler. Only the pre-enqueue window may be rolled
                    // back after a synchronous renderer failure.
                    particleBatches.forEach {
                        _ = $0.instanceBuffer.cancelUncommittedSubmission(
                            on: commandBuffer
                        )
                    }
                    particleBatches.forEach {
                        _ = $0.instanceBuffer.cancelPending()
                    }
                } else if particleSubmissionCommandBuffer == nil {
                    particleBatches.forEach {
                        _ = $0.instanceBuffer.cancelPending()
                    }
                }
            }
        }
        var mainPassForSubmission: SceneMainPassEncoder?
        defer { if !didTransferFrameOwnership { mainPassForSubmission?.cancelCompositionPins() } }
        var reflectionFrame: ReflectionFrame?
        defer { if !didTransferFrameOwnership { reflectionFrame?.cancel() } }
        var compositionGroupRuntime: SceneCompositionGroupFrameRuntime?
        defer { if !didTransferFrameOwnership { compositionGroupRuntime?.cancel() } }
        if sceneColor?.requiresDraw != false {
            if let failure = encodeSceneDrawing(
                imageTextures: imageTextures,
                layerTopology: layerTopology,
                userPropertyTextures: userPropertyTextures,
                userPropertyTextureStates: userPropertyTextureStates,
                mediaThumbnail: mediaThumbnail,
                spriteAnimations: spriteAnimations,
                spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
                specializedBaseTextureSamplings: specializedBaseTextureSamplings,
                imagePipeline: imagePipeline,
                frameProjection: frameProjection,
                preparedParticleBatches: preparedParticleBatches,
                particlePipeline: particlePipeline,
                offscreenTexturePool: offscreenTexturePool,
                frameContext: frameContext,
                cameraFrame: cameraFrame,
                encodeSourceUpdates: encodeSourceUpdates,
                performanceTelemetry: performanceTelemetry,
                drawable: drawable,
                commandBuffer: commandBuffer,
                sourceUpdateTransaction: sourceUpdateTransaction,
                modelFrame: modelFrame,
                effectExecutionTrace: effectExecutionTrace,
                mainTarget: mainTarget,
                sceneColor: sceneColor,
                frameDepthLeases: &frameDepthLeases,
                particleBatches: &particleBatches,
                particlePerformanceObservations: &particlePerformanceObservations,
                mainPassForSubmission: &mainPassForSubmission,
                reflectionFrame: &reflectionFrame,
                compositionGroupRuntime: &compositionGroupRuntime
            ) { return failure }
        }
        performanceTelemetry?.beginStage("compositor-seal")
        let hubCompositorSealStart = ProcessInfo.processInfo.systemUptime
        if let failure = encodeReflectionSnapshot(reflectionFrame, source: mainTarget,
            commandBuffer: commandBuffer) { return failure }
        if let failure = encodeTerminalColor(sceneColor: sceneColor, target: drawable.texture,
            offscreenTexturePool: offscreenTexturePool, dynamicValues: frameContext.dynamicValues,
            commandBuffer: commandBuffer, output: displayOutput,
            compositionGroupRuntime: compositionGroupRuntime) { return failure }
        let preparedFrame = makePreparedFrame(
            commandBuffer: commandBuffer,
            drawable: drawable,
            encodeFrameReadback: encodeFrameReadback,
            onDrawableWillPresent: onDrawableWillPresent,
            effectExecutionTrace: effectExecutionTrace,
            particlePerformanceObservations: particlePerformanceObservations,
            performanceTelemetry: performanceTelemetry,
            compositionGroupRuntime: compositionGroupRuntime,
            sourceUpdateTransaction: sourceUpdateTransaction,
            frameDepthLeases: frameDepthLeases,
            reflectionFrame: reflectionFrame,
            modelFrame: modelFrame,
            mainPassForSubmission: mainPassForSubmission,
            particleBatches: particleBatches
        )
        didTransferFrameOwnership = true
        performanceTelemetry?.endStage("compositor-seal")
        hubStage(.compositorSealMicros, hubCompositorSealStart)
        if let cpuStart {
            performanceTelemetry?.recordCPUFrame(
                duration: ProcessInfo.processInfo.systemUptime - cpuStart
            )
        }
        return .prepared(preparedFrame)
    }
}
