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
    let effectAdmissionCatalog: SceneEffectAdmissionCatalog
    let spotLightRuntime: SceneSpotLightRuntime
    let dependencyRuntime: SceneDependencyFrameRuntime
    let textureRegistry = SceneFrameTextureRegistry()
    let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
    private let effectExecutionTelemetry = SceneEffectExecutionTelemetry()
    init?(
        renderDescriptor: SceneRenderDescriptor,
        effectAdmissionCatalog: SceneEffectAdmissionCatalog,
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
        self.effectAdmissionCatalog = effectAdmissionCatalog
        self.spotLightRuntime = SceneSpotLightRuntime(descriptor: renderDescriptor, pipeline: pipelineRepository.spotLight())
        let resolvedMaterialLayerIDs = resolvedMaterialRuntime?.executionLayerIDs ?? []
        let executableUtilityConsumerLayerIDs = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: renderDescriptor,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        self.dependencyRuntime = SceneDependencyFrameRuntime(
            descriptor: renderDescriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            verifiedXRayStageKeys: effectAdmissionCatalog.verifiedXRayStageKeys,
            device: device
        )
        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderDescriptor,
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
        layerTopology: SceneScriptLayerTopologySnapshot? = nil,
        userPropertyTextures: [String: MTLTexture] = [:],
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot = .empty,
        spriteAnimations: [Int: SceneSpriteAnimation],
        imagePipeline: SceneImageLayerPipeline?,
        particleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        encodeSourceUpdates: ((
            MTLCommandBuffer, SceneSourceUpdateTransaction
        ) -> Void)? = nil,
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
        let frameDescriptor = layerTopology.map(renderDescriptor.applying) ?? renderDescriptor
        let frameLayersByID = Dictionary(
            uniqueKeysWithValues: frameDescriptor.layers.map { ($0.id, $0) }
        )
        let frameStaticWorldFrames = SceneLayerWorldFrameResolver.compute(
            descriptor: frameDescriptor, byID: frameLayersByID
        )
        let frameWorldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: frameDescriptor, byID: frameLayersByID,
            snapshot: frameContext.dynamicValues,
            staticFrames: frameStaticWorldFrames
        )
        let viewportSize = frameContext.screenSize
        let time = Float(frameContext.sceneTime)
        let parallaxMouseNormalized = frameContext.cameraParallaxPosition
        let parallaxConfiguration = parallaxConfiguration(
            cameraFrame: cameraFrame,
            viewportSize: viewportSize
        )
        let orderedLayers = frameDescriptor.renderOrderLayerIDs.compactMap {
            frameLayersByID[$0]
        }
        let frameVisibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: frameDescriptor,
            snapshot: frameContext.dynamicValues
        )
        let particleBatchesByID = Dictionary(grouping: particleBatches, by: \.layerID)
        guard let resolvedMaterialFrameTargetPlans = admitResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            spriteAnimations: spriteAnimations,
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
        var stopsAfterClaimedFailure = false
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: drawable.texture,
            clearColor: sceneClearColor
        )
        frameLayers: for layer in orderedLayers {
            defer {
                if !stopsAfterClaimedFailure { renderUtilityPlans(triggeredBy: layer.id,
                    imagePipeline: imagePipeline,
                    offscreenTexturePool: offscreenTexturePool, frameContext: frameContext,
                    worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration, viewportSize: viewportSize,
                    time: time, mainPass: mainPass, commandBuffer: commandBuffer,
                    effectExecutionTrace: effectExecutionTrace,
                    resolvedMaterialFrameTargetPlans:
                        resolvedMaterialFrameTargetPlans) }
            }
            if let providerGraphEncoded = executeDependencyGraphProviderIfRequired(
                layer: layer,
                framePlan: resolvedMaterialFrameTargetPlans[layer.id],
                textureRegistry: textureRegistry,
                dependencyRuntime: dependencyRuntime,
                mainPass: mainPass,
                commandBuffer: commandBuffer,
                executionTrace: effectExecutionTrace
            ) {
                if !providerGraphEncoded {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                continue
            }
            if let imagePipeline, dependencyRuntime.requiresCapture(for: layer.id) {
                let providerModel = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(
                        for: layer.id
                    ),
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                _ = dependencyRuntime.captureProviderIfRequired(
                    layer: layer,
                    sourceTexture: imageTextures[layer.id],
                    sourceCandidate: imageTextures[layer.id].flatMap {
                        imageTextures.candidate(for: layer.id, matching: $0)
                    },
                    layerMVP: cameraFrame.orthographicViewProjection * providerModel,
                    viewportSize: viewportSize,
                    pipeline: imagePipeline,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
                )
            }
            guard frameVisibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let texture = imageTextures[layer.id] else { continue }
                let resolvedFramePlan = resolvedMaterialFrameTargetPlans[layer.id]
                let requiresDependencyEffect = resolvedFramePlan?
                    .consumesExternalPrimaryDependency
                    ?? dependencyRuntime.requiresEffect(for: layer.id)
                let dependencyEffect: SceneDependencyEffectInput?
                let resolvedDependencyFailure: (
                    reasonCode: String,
                    isOrdinaryUnavailable: Bool
                )?
                if requiresDependencyEffect, resolvedFramePlan != nil {
                    switch dependencyRuntime.resolvedMaterialEffectInputResolution(
                        for: layer.id,
                        textureRegistry: textureRegistry
                    ) {
                    case let .ready(input):
                        dependencyEffect = input
                        resolvedDependencyFailure = nil
                    case let .unavailable(reasonCode):
                        dependencyEffect = nil
                        resolvedDependencyFailure = (reasonCode, true)
                    case let .invalid(reasonCode):
                        dependencyEffect = nil
                        resolvedDependencyFailure = (reasonCode, false)
                    }
                } else {
                    dependencyEffect = dependencyRuntime.effectInput(
                        for: layer.id,
                        textureRegistry: textureRegistry
                    )
                    resolvedDependencyFailure = nil
                }
                let layerAlpha = SceneDynamicLayerValues.alpha(
                    layerID: layer.id, authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                )
                let model = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(
                        for: layer.id
                    ),
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
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    baseTextureCandidate: imageTextures.candidate(
                        for: layer.id,
                        matching: texture
                    ),
                    masks: .empty,
                    textureFrame: spriteAnimations[layer.id]?.transform(at: time) ?? .identity,
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
                        resolvedFramePlan,
                    offscreenSize: layer.contentKind == "solid" ? SceneCaptureGeometryResolver.projectedPixelSize(layerMVP: mvp, viewportSize: viewportSize) : nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: dependencyEffect,
                    requiresDependencyEffect: requiresDependencyEffect,
                    blocksStaticLayerSourcePassthrough:
                        dependencyRuntime.blocksStaticLayerSourcePassthrough(
                            for: layer.id
                        ),
                    dynamicValues: frameContext.dynamicValues,
                    audioSpectrum: frameContext.audioSpectrum,
                    authoredShaderFrameInputs: .init(frameContext: frameContext)
                )
                let explicitLayerSourcePublication = imageTextures
                    .explicitLayerSourcePublication(
                        for: layer.id,
                        matching: texture
                    )
                let resolvedMaterialGraphOutputPublisher: ((MTLTexture) -> Bool)?
                if dependencyRuntime.requiresGraphOutputCapture(for: layer.id) {
                    resolvedMaterialGraphOutputPublisher = { graphOutput in
                        dependencyRuntime.publishGraphOutputIfRequired(
                            layerID: layer.id,
                            texture: graphOutput,
                            textureRegistry: textureRegistry,
                            commandBuffer: commandBuffer
                        ) == true
                    }
                } else {
                    resolvedMaterialGraphOutputPublisher = nil
                }
                if let failure = resolvedDependencyFailure {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    if failure.isOrdinaryUnavailable,
                       imageCompositor
                        .rejectResolvedMaterialDependencySubgraphLocally(
                            layerID: layer.id,
                            reasonCode: failure.reasonCode
                        ) {
                        continue
                    }
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        failure.reasonCode
                    )
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                if request.requiresDependencyEffect,
                   request.dependencyEffect == nil {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    continue
                }
                let drawOutcome = imageCompositor.drawOutcome(
                    request,
                    explicitLayerSourcePublication: explicitLayerSourcePublication,
                    resolvedMaterialGraphOutputPublisher:
                        resolvedMaterialGraphOutputPublisher,
                    pipeline: imagePipeline,
                    mainPass: mainPass,
                    executionTrace: effectExecutionTrace,
                    executionOrigin: Self.effectExecutionOrigin(
                        for: layer.contentKind
                    )
                )
                dependencyRuntime.recordBindingIfRequired(
                    for: layer.id,
                    encoded: drawOutcome.consumedDependency,
                    on: commandBuffer
                )
                if !drawOutcome.encoded,
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
                    imagePipeline: imagePipeline,
                    frameContext: frameContext, worldFramesByLayerID: frameWorldFrames,
                    cameraFrame: cameraFrame, parallaxConfiguration: parallaxConfiguration,
                    mainPass: mainPass,
                    executionTrace: effectExecutionTrace
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

    /// Executes an effectful hidden dependency provider through the same
    /// resolved graph runtime as a visible image layer, then publishes that
    /// intermediate output to the existing named-target registry. It never
    /// composites the hidden provider directly into the main target.
    private func executeDependencyGraphProviderIfRequired(
        layer: SceneRenderDescriptor.Layer,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        textureRegistry: SceneFrameTextureRegistry,
        dependencyRuntime: SceneDependencyFrameRuntime,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool? {
        guard dependencyRuntime.requiresGraphOutputCapture(
            for: layer.id
        ) else { return nil }
        guard layer.visible == false else { return nil }
        // A visual frame-local fallback intentionally publishes nothing. Any
        // downstream consumer then takes the ordinary provider-miss path.
        guard framePlan != nil else { return true }

        let dependencyEffect: SceneDependencyEffectInput?
        if dependencyRuntime.requiresEffect(for: layer.id) {
            switch dependencyRuntime.resolvedMaterialEffectInputResolution(
                for: layer.id,
                textureRegistry: textureRegistry
            ) {
            case let .ready(input):
                dependencyEffect = input
            case let .unavailable(reasonCode):
                dependencyRuntime.recordBindingFailure(for: layer.id)
                return imageCompositor
                    .rejectResolvedMaterialDependencySubgraphLocally(
                        layerID: layer.id,
                        reasonCode: reasonCode
                    )
            case let .invalid(reasonCode):
                dependencyRuntime.recordBindingFailure(for: layer.id)
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    reasonCode
                )
                return false
            }
        } else {
            dependencyEffect = nil
        }

        // Resolve an external provider before consuming the execution claim.
        // An ordinary missing publication can then remove this unencoded
        // transaction locally and let the same rule cascade through later
        // hidden providers without invalidating independent frame work.
        let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
        switch imageCompositor.resolvedMaterialClaim(layerID: layer.id) {
        case let .claimed(value):
            claim = value
        case .localFallback:
            return true
        case .unclaimed, .rejected:
            return false
        }

        guard let resolvedMaterialRuntime = imageCompositor.resolvedMaterialRuntime
        else { return false }
        let executed = imageCompositor.executeResolvedMaterialClaim(
            runtime: resolvedMaterialRuntime,
            claim: claim,
            framePlan: framePlan,
            layerID: layer.id,
            dependencyEffect: dependencyEffect,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: .image
        )
        let texture: MTLTexture
        let ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
        switch executed {
        case let .encoded(value, executionTicket):
            texture = value
            ticket = executionTicket
        case .failed:
            return false
        }
        let published = dependencyRuntime.publishGraphOutputIfRequired(
            layerID: layer.id,
            texture: texture,
            textureRegistry: textureRegistry,
            commandBuffer: commandBuffer
        ) == true
        dependencyRuntime.recordBindingIfRequired(
            for: layer.id,
            encoded: ticket.consumesExternalPrimaryDependency,
            on: commandBuffer
        )
        return imageCompositor.consumeResolvedMaterialNamedPublication(
            ticket,
            texture: texture,
            published: published,
            layerID: layer.id,
            executionTrace: executionTrace,
            executionOrigin: .image
        ) && published
    }
}
