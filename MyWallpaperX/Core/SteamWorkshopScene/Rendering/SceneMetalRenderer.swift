import Metal
import QuartzCore
import simd
struct SceneMetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderDescriptor: SceneRenderDescriptor
    let imageCompositor: SceneImageLayerCompositor
    private let pipelineRepository: SceneImageEffectPipelineRepository
    let visibleLayerIDs: Set<Int>
    // Cached transforms propagate parent pivot/orientation without double-scaling child quads.
    let worldFramesByLayerID: [Int: simd_float4x4]
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let utilityPlansByTriggerLayerID: [Int: [SceneUtilityLayerRuntimePlan]]
    let utilityCaptureLayerIDs: Set<Int>
    let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    let sceneScriptAudioBarsPlansByLayerID: [Int: SceneScriptAudioBarsPlan]
    let spotLightRuntime: SceneSpotLightRuntime
    let dependencyRuntime: SceneDependencyFrameRuntime
    let textureRegistry = SceneFrameTextureRegistry()
    let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
    let authoredEffectTelemetry = SceneGPUCompletionTelemetry(phase: "authored-effect-graph")
    private let sceneScriptAudioBarsTelemetry = SceneGPUCompletionTelemetry(phase: "scene-script-audio-bars")
    private let effectExecutionTelemetry = SceneEffectExecutionTelemetry()
    init?(
        renderDescriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        sceneScriptAudioBarsProgram: SceneScriptAudioBarsProgram = .empty,
        pipelineRepository: SceneImageEffectPipelineRepository,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil
    ) {
        let device = pipelineRepository.device
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.renderDescriptor = renderDescriptor
        self.pipelineRepository = pipelineRepository
        self.imageCompositor = SceneImageLayerCompositor(
            pipelineRepository: pipelineRepository,
            resolvedMaterialRuntime: resolvedMaterialRuntime
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: renderDescriptor)
        self.visibleLayerIDs = visibleLayerIDs
        self.authoredEffectCatalog = authoredEffectCatalog
        self.sceneScriptAudioBarsPlansByLayerID = Dictionary(uniqueKeysWithValues: sceneScriptAudioBarsProgram.plans.map { ($0.layerID, $0) })
        self.spotLightRuntime = SceneSpotLightRuntime(descriptor: renderDescriptor, pipeline: pipelineRepository.spotLight())
        let resolvedMaterialLayerIDs = resolvedMaterialRuntime?.executionLayerIDs ?? []
        let executableUtilityConsumerLayerIDs = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: renderDescriptor,
                authoredEffectCatalog: authoredEffectCatalog,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        self.dependencyRuntime = SceneDependencyFrameRuntime(
            descriptor: renderDescriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            device: device
        )
        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        self.utilityPlansByTriggerLayerID = Dictionary(
            grouping: utilityPlans.values.filter(\.shouldCapture),
            by: \.triggerLayerID
        )
        self.utilityCaptureLayerIDs = Set(utilityPlans.values.filter(\.shouldCapture).map(\.layerID))
        self.worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            descriptor: renderDescriptor, byID: byID
        )
        self.parallaxByLayerID = SceneLayerParallax.resolveAll(layersByID: byID)
    }

    func renderFrame(
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]] = [:],
        userPropertyTextures: [String: MTLTexture] = [:],
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot = .empty,
        spriteAnimations: [Int: SceneSpriteAnimation],
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline?,
        particleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        encodeSourceUpdates: ((
            MTLCommandBuffer, SceneSourceUpdateTransaction
        ) -> Void)? = nil,
        encodeLayerSourceUpdates: ((
            MTLCommandBuffer, SceneSourceUpdateTransaction
        ) -> [Int: SceneTextureProviderPublication])? = nil,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        to drawable: CAMetalDrawable
    ) {
        guard !imageCompositor.shouldDeferResolvedMaterialFrame else { return }
        let cpuStart = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            performanceTelemetry?.recordCommandBufferUnavailable()
            return
        }
        let sourceUpdateTransaction = SceneSourceUpdateTransaction()
        defer { sourceUpdateTransaction.cancel() }
        let effectExecutionTrace = effectExecutionTelemetry.makeFrame(
            frameIndex: frameContext.frameIndex
        )
        encodeSourceUpdates?(commandBuffer, sourceUpdateTransaction)
        let imageTextures = imageTextures.replacingLayerSources(
            encodeLayerSourceUpdates?(
                commandBuffer, sourceUpdateTransaction
            ) ?? [:]
        )
        let frameWorldFrames = SceneLayerDynamicWorldFrameResolver.resolve(descriptor: renderDescriptor,
            byID: layersByID, snapshot: frameContext.dynamicValues, staticFrames: worldFramesByLayerID)
        let viewportSize = frameContext.screenSize
        let time = Float(frameContext.sceneTime)
        let parallaxMouseNormalized = frameContext.cameraParallaxPosition
        let camera = renderDescriptor.camera
        let parallaxConfiguration = parallaxConfiguration(
            cameraFrame: cameraFrame,
            viewportSize: viewportSize
        )
        let orderedLayers = renderDescriptor.renderOrderLayerIDs.compactMap { layersByID[$0] }
        let particleBatchesByID = Dictionary(grouping: particleBatches, by: \.layerID)
        guard let resolvedMaterialFrameTargetPlans = admitResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            dynamicTextRenderSizes: dynamicTextRenderSizes,
            spriteAnimations: spriteAnimations,
            effectTextures: effectTextures,
            imagePipeline: imagePipeline,
            userPropertyTextures: userPropertyTextures,
            userPropertyStates: userPropertyTextureStates,
            mediaThumbnail: mediaThumbnail,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            worldFramesByLayerID: frameWorldFrames,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            mainTarget: drawable.texture,
            commandBuffer: commandBuffer
        ) else { return }
        guard let legacyAuthoredFrameTables = Self.prepareAndRegisterLegacyAuthoredBatch(
            renderer: self, resolvedMaterialPlans: resolvedMaterialFrameTargetPlans,
            offscreenTexturePool: offscreenTexturePool, imageTextures: imageTextures,
            dynamicTextRenderSizes: dynamicTextRenderSizes, frameContext: frameContext,
            worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration, commandBuffer: commandBuffer,
            compositor: imageCompositor, transaction: sourceUpdateTransaction
        ) else { return }
        var stopsAfterClaimedFailure = false
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: drawable.texture,
            clearColor: sceneClearColor
        )
        frameLayers: for layer in orderedLayers {
            defer {
                if !stopsAfterClaimedFailure { renderUtilityPlans(triggeredBy: layer.id,
                    effectTextures: effectTextures, imagePipeline: imagePipeline,
                    offscreenTexturePool: offscreenTexturePool, frameContext: frameContext,
                    worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration, viewportSize: viewportSize,
                    time: time, mainPass: mainPass, commandBuffer: commandBuffer,
                    frameTransaction: sourceUpdateTransaction,
                    effectExecutionTrace: effectExecutionTrace,
                    resolvedMaterialFrameTargetPlans:
                        resolvedMaterialFrameTargetPlans,
                    legacyAuthoredFrameTables: legacyAuthoredFrameTables) }
            }
            if let imagePipeline, dependencyRuntime.requiresCapture(for: layer.id) {
                let providerModel = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: dynamicTextRenderSizes[layer.id],
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                _ = dependencyRuntime.captureProviderIfRequired(
                    layer: layer,
                    layerMVP: cameraFrame.orthographicViewProjection * providerModel,
                    viewportSize: viewportSize,
                    pipeline: imagePipeline,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
                )
            }
            guard visibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let texture = imageTextures[layer.id] else { continue }
                if let plan = sceneScriptAudioBarsPlansByLayerID[layer.id] {
                    let encoded = renderSceneScriptAudioBars(
                        plan: plan, layer: layer, texture: texture, pipeline: imagePipeline,
                        frameContext: frameContext, sceneOrthoHeight: camera.orthoHeight,
                        viewProjection: cameraFrame.orthographicViewProjection,
                        mainPass: mainPass
                    )
                    sceneScriptAudioBarsTelemetry.record(
                        layerID: layer.id, encoded: encoded, on: commandBuffer
                    )
                    continue
                }
                let authoredEffectChain = authoredEffectChain(for: layer.id)
                let suppressesLegacyEffectFallback = authoredEffectCatalog
                    .legacyEffectFallbackSuppressedLayerIDs.contains(layer.id)
                let dependencyEffect = dependencyRuntime.effectInput(
                    for: layer.id,
                    textureRegistry: textureRegistry
                )
                if dependencyRuntime.requiresEffect(for: layer.id),
                   dependencyEffect == nil {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    continue
                }
                let preparedTexture = dependencyRuntime.preparedSourceTexture(
                    for: layer.id,
                    sourceTexture: texture,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
                )
                let layerAlpha = SceneDynamicLayerValues.alpha(
                    layerID: layer.id, authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                )
                let model = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: dynamicTextRenderSizes[layer.id],
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                let mvp = cameraFrame.orthographicViewProjection * model
                let cursorUV = SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: frameContext.pointer.current,
                    modelViewProjection: mvp
                )
                let previousCursorUV = SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: frameContext.pointer.previous,
                    modelViewProjection: mvp
                )
                var request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: preparedTexture,
                    baseTextureCandidate: imageTextures.candidate(for: layer.id, matching: preparedTexture),
                    masks: effectMasks(for: layer.id, in: effectTextures),
                    textureFrame: spriteAnimations[layer.id]?.transform(at: time, wallDate: frameContext.wallDate) ?? .identity,
                    mvp: mvp,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: layerAlpha,
                        cursorUV: cursorUV ?? .zero,
                        previousCursorUV: previousCursorUV ?? cursorUV ?? .zero,
                        cursorIsInside: frameContext.pointer.isInside && cursorUV != nil,
                        previousCursorIsInside: frameContext.pointer.isInside
                            && previousCursorUV != nil,
                        primaryButtonIsDown: frameContext.pointer.isPrimaryButtonDown,
                        frameTime: Float(frameContext.frameTime),
                        tint: SceneDynamicLayerValues.color(
                            layerID: layer.id, authoredValue: layer.colorRGB,
                            snapshot: frameContext.dynamicValues
                        )
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlans[layer.id],
                    offscreenSize: layer.contentKind == "solid" ? SceneCaptureGeometryResolver.projectedPixelSize(layerMVP: mvp, viewportSize: viewportSize) : nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: dependencyEffect,
                    // A single-stage projection is already represented by the
                    // chain. Do not publish it as a second product owner.
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: blocksLegacyGaussianBlur(for: layer.id),
                    authoredEffectChain: authoredEffectChain,
                    dynamicValues: frameContext.dynamicValues,
                    audioSpectrum: frameContext.audioSpectrum,
                    authoredShaderFrameInputs: .init(frameContext: frameContext)
                )
                request.legacyAuthoredFrameTables = legacyAuthoredFrameTables[layer.id]
                request.suppressesLegacyEffectFallback =
                    suppressesLegacyEffectFallback
                var selectedLegacyAuthoredRoute = false
                let encoded = imageCompositor.draw(
                    request,
                    pipeline: imagePipeline,
                    mainPass: mainPass,
                    frameTransaction: sourceUpdateTransaction,
                    executionTrace: effectExecutionTrace,
                    executionOrigin: Self.effectExecutionOrigin(
                        for: layer.contentKind
                    ),
                    onLegacyAuthoredRouteSelected: {
                        selectedLegacyAuthoredRoute = true
                    }
                )
                if selectedLegacyAuthoredRoute {
                    authoredEffectTelemetry.record(layerID: layer.id, encoded: encoded, on: commandBuffer)
                }
                dependencyRuntime.recordBindingIfRequired(
                    for: layer.id,
                    encoded: encoded,
                    on: commandBuffer
                )
                if !encoded,
                   request.resolvedMaterialFrameTargetPlan != nil {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
            case "composition", "project", "fullscreen":
                break
            case "quad":
                if !drawQuadLayer(
                    layer: layer,
                    resolvedFramePlan: resolvedMaterialFrameTargetPlans[layer.id],
                    imagePipeline: imagePipeline, effectTextures: effectTextures,
                    frameContext: frameContext, worldFramesByLayerID: frameWorldFrames,
                    cameraFrame: cameraFrame, parallaxConfiguration: parallaxConfiguration,
                    time: time, mainPass: mainPass, commandBuffer: commandBuffer,
                    executionTrace: effectExecutionTrace,
                    makeLightShaftsPipeline: { pipelineRepository.lightShafts() }
                ) {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
            case "spotLight":
                spotLightRuntime.render(
                    layerID: layer.id, worldFrame: frameWorldFrames[layer.id],
                    frame: .init(
                        frameContext: frameContext, cameraFrame: cameraFrame,
                        mainPass: mainPass, commandBuffer: commandBuffer
                    )
                )
            case "particle":
                guard let particlePipeline,
                      let layerBatches = particleBatchesByID[layer.id] else { continue }
                let model = particleModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                renderParticleBatches(
                    layerBatches,
                    pipeline: particlePipeline,
                    model: model,
                    cameraFrame: cameraFrame,
                    viewportSize: SIMD2(
                        Float(viewportSize.width),
                        Float(viewportSize.height)
                    ),
                    mainPass: mainPass,
                    commandBuffer: commandBuffer
                )
            default:
                continue
            }
        }

        mainPass.finishEnsuringClear()
        encodeFrameReadback?(drawable.texture, commandBuffer)
        guard imageCompositor.endResolvedMaterialFrame(on: commandBuffer) else {
            return
        }
        commandBuffer.present(drawable)
        effectExecutionTelemetry.observeSharedCommandBuffer(
            for: effectExecutionTrace,
            on: commandBuffer
        )
        performanceTelemetry?.recordSubmitted(on: commandBuffer)
        sourceUpdateTransaction.arm(on: commandBuffer)
        commandBuffer.commit()
        sourceUpdateTransaction.didSubmit()
        if let cpuStart {
            performanceTelemetry?.recordCPUFrame(
                duration: ProcessInfo.processInfo.systemUptime - cpuStart
            )
        }
    }
}
