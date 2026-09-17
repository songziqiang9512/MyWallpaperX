import Foundation
import Metal
import QuartzCore
import simd
struct SceneMetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderDescriptor: SceneRenderDescriptor
    let imageCompositor: SceneImageLayerCompositor
    let pipelineRepository: SceneImageEffectPipelineRepository
    let visibleLayerIDs: Set<Int>
    let authoredLayers: [SceneRenderDescriptor.Layer]
    // Cached transforms propagate parent pivot/orientation without double-scaling child quads.
    let worldFramesByLayerID: [Int: simd_float4x4]
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let lightLayerIDs: [Int]
    let utilityPlansByTriggerLayerID: [Int: [SceneUtilityLayerRuntimePlan]]
    let utilityCaptureLayerIDs: Set<Int>
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
        particleBatchesProvider: () -> [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        encodeSourceUpdates: ((
            MTLCommandBuffer, SceneSourceUpdateTransaction
        ) -> ScenePuppetAttachmentFrameSnapshot)? = nil,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        onDrawableWillPresent: ((CAMetalDrawable) -> Void)? = nil,
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
        var didCommitParticleSubmission = false
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
            sourceUpdateTransaction.cancel()
            if !didCommitParticleSubmission { discardUnsubmittedFrameResources() }
        }
        // Submitted candidates remain provisional until the host barrier.
        var frameDepthLeases: [SceneParticleDepthTargetLease] = []
        defer { frameDepthLeases.forEach { $0.cancel() } }
        var staticModelDepthLease: SceneParticleDepthTargetLease?
        var staticModelDepthWasCleared = false
        var staticModelDepthPlan = SceneStaticModelDepthPlan()
        // M2 Patch A：effect 执行证据链（每帧 trace + SHA256 cohort）只属于
        // 诊断/基准模式（runtime-architecture §5.5）；正常播放为 nil，
        // 全部 record 调用点为 optional 旁路。
        let effectExecutionTrace: SceneEffectExecutionFrameTrace? =
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            ? effectExecutionTelemetry.makeFrame(frameIndex: frameContext.frameIndex)
            : nil
        // Always-on stage timings mirror the telemetry-gated stages below;
        // each is bypass-only accumulation with no control-flow effect.
        @inline(__always) func hubStage(
            _ metric: ScenePerformanceMetric, _ start: TimeInterval
        ) {
            ScenePerformanceCounterHub.shared.add(
                metric, ScenePerformanceCounterHub.micros(since: start)
            )
        }
        performanceTelemetry?.beginStage("source-update")
        let hubSourceUpdateStart = ProcessInfo.processInfo.systemUptime
        let puppetAttachmentFrames = encodeSourceUpdates?(
            commandBuffer, sourceUpdateTransaction
        ) ?? .empty
        performanceTelemetry?.endStage("source-update")
        hubStage(.sourceUpdateMicros, hubSourceUpdateStart)
        performanceTelemetry?.beginStage("world-resolve")
        let hubWorldResolveStart = ProcessInfo.processInfo.systemUptime
        let frameProjection = resolveFrameWorldProjection(
            layerTopology: layerTopology,
            dynamicValues: frameContext.dynamicValues,
            puppetAttachmentFrames: puppetAttachmentFrames
        )
        let frameDescriptor = frameProjection.descriptor
        let frameLayersByID = frameProjection.layersByID
        let frameWorldFrames = frameProjection.worldFrames
        let frameDynamicLayerIDs = frameProjection.dynamicLayerIDs
#if DEBUG
        var dynamicEncodedLayerCount = 0
        var dynamicPassthroughLayerCount = 0
#endif
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
            candidateLayerIDs: frameProjection.lightLayerIDs,
            layersByID: frameLayersByID
        )
        performanceTelemetry?.beginStage("frame-admission")
        let hubFrameAdmissionStart = ProcessInfo.processInfo.systemUptime
        let resolvedMaterialFrameAdmission = admitResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
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
            mainTarget: drawable.texture,
            commandBuffer: commandBuffer
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
        let particleBatches = particleBatchesProvider()
        let particleBatchesByID = Dictionary(grouping: particleBatches, by: \.layerID)
        performanceTelemetry?.endStage("prepass-particles")
        defer {
            if !didCommitParticleSubmission {
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
        var stopsAfterClaimedFailure = false
        performanceTelemetry?.beginStage("prepass-encoder")
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: drawable.texture,
            clearColor: sceneClearColor,
            clearEnabled: frameDescriptor.camera.clearEnabled
        )
        performanceTelemetry?.endStage("prepass-encoder")
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
        performanceTelemetry?.endStage("prepass")
        hubStage(.prepassMicros, hubPrepassStart)
        performanceTelemetry?.beginStage("layer-loop")
        let hubLayerLoopStart = ProcessInfo.processInfo.systemUptime
        frameLayers: for layer in orderedLayers {
            if stopsAfterClaimedFailure { break frameLayers }
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
            // Its graph was already executed and published before an earlier
            // consumer. Keep authored trigger order, but never consume the
            // same launch/frame claim twice.
            if forwardGraphProviderLayerIDs.contains(layer.id) { continue }
            let baseSelection: SceneBaseMaterialTextureSelection
            switch layer.contentKind {
            case "image", "solid", "text":
                baseSelection = baseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        )
                )
            default:
                baseSelection = .missing
            }
            let baseSource = baseSelection.source
            if let reasonCode = baseSelection.rejectedProviderReason {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-provider-rejected",
                    outcome: .failed(reasonCode: reasonCode)
                )
            } else if baseSource?.usesSystemProvider == true {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-system-provider",
                    outcome: .encoded
                )
            } else if baseSource?.usesUserPropertyProvider == true {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-user-property-provider",
                    outcome: .encoded
                )
            }
            if let providerGraphEncoded = executeDependencyGraphProviderIfRequired(
                layer: layer,
                isVisibleExecutionRoot: frameVisibleLayerIDs.contains(layer.id),
                framePlan: resolvedMaterialFrameTargetPlans[layer.id],
                textureRegistry: textureRegistry,
                dependencyRuntime: dependencyRuntime,
                mainPass: mainPass,
                commandBuffer: commandBuffer,
                geometryProduct: imageTextures.geometryProducts[layer.id],
                executionTrace: effectExecutionTrace
            ) {
                if !providerGraphEncoded {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                continue
            }
            if let imagePipeline, dependencyRuntime.requiresCapture(
                for: layer.id,
                activeStaticModelConsumerLayerIDs:
                    activeStaticModelNamedAlbedoLayerIDs
            ) {
                let providerModel = imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(
                        for: layer.id
                    ),
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                )
                _ = dependencyRuntime.captureProviderIfRequired(
                    layer: layer,
                    sourceTexture: baseSource?.texture,
                    sourceCandidate: baseSource?.candidate,
                    usesAuthoredLayerColor:
                        baseSource?.usesAuthoredLayerColor ?? true,
                    providerAlpha: Float(SceneDynamicLayerValues.alpha(
                        layerID: layer.id,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    )),
                    providerColor: SceneDynamicLayerValues.color(
                        layerID: layer.id,
                        authoredValue: layer.colorRGB,
                        snapshot: frameContext.dynamicValues
                    ),
                    layerMVP: cameraFrame.viewProjection(for: layer)
                        * providerModel,
                    viewportSize: viewportSize,
                    pipeline: imagePipeline,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass,
                    geometryProduct: imageTextures.geometryProducts[layer.id]
                )
            }
            guard frameVisibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let baseSource else { continue }
                let texture = baseSource.texture
                let resolvedFramePlan = resolvedMaterialFrameTargetPlans[layer.id]
                let dependencyBypassReason = resolvedFramePlan == nil
                    ? nil
                    : imageCompositor
                        .preparedResolvedMaterialExternalDependencyBypassReason(
                            layerID: layer.id
                        )
                let requiresDependencyEffect = (
                    resolvedFramePlan?.consumesExternalPrimaryDependency
                        ?? dependencyRuntime.requiresEffect(for: layer.id)
                ) && dependencyBypassReason == nil
                let dependencyResolution = resolveDependencyEffectInputs(
                    layerID: layer.id,
                    requiresDependencyEffect: requiresDependencyEffect,
                    hasResolvedFramePlan: resolvedFramePlan != nil,
                    bypassReason: dependencyBypassReason,
                    dependencyRuntime: dependencyRuntime,
                    textureRegistry: textureRegistry
                )
                let dependencyEffect = dependencyResolution.dependencyEffect
                let dependencyEffects = dependencyResolution.dependencyEffects
                let resolvedDependencyFailure = dependencyResolution.failure
                let geometryProduct = imageTextures.geometryProducts[layer.id]
                let layerAlpha = SceneDynamicLayerValues.alpha(
                    layerID: layer.id, authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                )
                let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
                let model = geometryProduct.map {
                    geometryModelMatrix(
                        for: layer,
                        worldFramesByLayerID: frameWorldFrames,
                        authoredSize: $0.authoredSize,
                        parallaxMouseNormalized: parallaxMouseNormalized,
                        configuration: parallaxConfiguration,
                        visibleHalfExtents: cameraFrame.coverHalfExtents,
                        usesPerspective: usesPerspective
                    )
                } ?? imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: usesPerspective
                )
                let mvp = cameraFrame.viewProjection(for: layer) * model
                let cursorUV = SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: frameContext.pointer.current,
                    modelViewProjection: mvp
                )
                let previousCursorUV = SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: frameContext.pointer.previous,
                    modelViewProjection: mvp
                )
                let effectSourceExtent: SceneLayerEffectSourceExtent?
                if layer.contentKind == "solid" {
                    effectSourceExtent = SceneCaptureGeometryResolver
                        .projectedPixelSize(
                            layerMVP: mvp,
                            viewportSize: viewportSize
                        )
                        .flatMap(SceneLayerEffectSourceExtent.init(pixelSize:))
                } else {
                    effectSourceExtent = SceneLayerEffectSourceExtent.resolve(
                        publishedRenderSizeWH:
                            imageTextures.layerSourceRenderSize(for: layer.id),
                        authoredRenderSizeWH: layer.renderSizeWH,
                        candidateMappedSize: baseSource.candidate?.mappedSize
                    )
                }
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    baseTextureCandidate: baseSource.candidate,
                    baseTextureSampling: specializedBaseTextureSamplings[layer.id],
                    masks: .empty,
                    textureFrame: spriteAnimations[layer.id].map {
                        $0.transform(
                            at: spriteAnimationPlaybackTimes[layer.id] ?? 0
                        )
                    } ?? .identity,
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
                        tint: baseSource.usesAuthoredLayerColor
                            ? SceneDynamicLayerValues.color(
                                layerID: layer.id,
                                authoredValue: layer.colorRGB,
                                snapshot: frameContext.dynamicValues
                            )
                            : SIMD3(repeating: 1)
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    resolvedMaterialFrameTargetPlan:
                        resolvedFramePlan,
                    effectSourceExtent: effectSourceExtent,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: dependencyEffect,
                    dependencyEffects: dependencyEffects,
                    requiresDependencyEffect: requiresDependencyEffect,
                    blocksStaticLayerSourcePassthrough:
                        dependencyRuntime.blocksStaticLayerSourcePassthrough(
                            for: layer.id
                        ),
                    dynamicValues: frameContext.dynamicValues,
                    audioSpectrum: frameContext.audioSpectrum,
                    authoredShaderFrameInputs: .init(frameContext: frameContext),
                    geometryProduct: geometryProduct
                )
                let explicitLayerSourcePublication = imageTextures
                    .explicitLayerSourcePublication(
                        for: layer.id,
                        matching: texture
                    )
                let layerSourceGraphFallbackPublisher: ((MTLTexture) -> Bool)?
                if geometryProduct == nil,
                   dependencyRuntime.requiresDemandedGraphOutputCapture(for: layer.id) {
                    layerSourceGraphFallbackPublisher = { fallbackTexture in
                        guard fallbackTexture === texture else { return false }
                        return dependencyRuntime
                            .captureGraphSourceFallbackIfRequired(
                                layer: layer,
                                sourceTexture: fallbackTexture,
                                sourceCandidate: baseSource.candidate,
                                usesAuthoredLayerColor:
                                    baseSource.usesAuthoredLayerColor,
                                layerMVP: mvp,
                                viewportSize: viewportSize,
                                pipeline: imagePipeline,
                                textureRegistry: textureRegistry,
                                mainPass: mainPass
                            ) == .published
                    }
                } else {
                    layerSourceGraphFallbackPublisher = nil
                }
                let resolvedMaterialGraphOutputPublisher: ((
                    MTLTexture,
                    SceneTextureContent
                ) -> SceneGraphOutputPublicationResult)?
                if dependencyRuntime.requiresDemandedGraphOutputCapture(
                    for: layer.id
                ) {
                    resolvedMaterialGraphOutputPublisher = { graphOutput, content in
                        dependencyRuntime.publishGraphOutputIfRequired(
                            layerID: layer.id,
                            texture: graphOutput,
                            publicationRole: .visibleMainLoop,
                            textureRegistry: textureRegistry,
                            commandBuffer: commandBuffer,
                            geometryProduct: geometryProduct,
                            content: content
                        ) ?? .invalid(
                            reasonCode: "named-provider-publication-route-missing"
                        )
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
                   request.dependencyEffect == nil,
                   request.dependencyEffects.isEmpty {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    continue
                }
                let drawOutcome = imageCompositor.drawOutcome(
                    request,
                    explicitLayerSourcePublication: explicitLayerSourcePublication,
                    resolvedMaterialGraphOutputPublisher:
                        resolvedMaterialGraphOutputPublisher,
                    layerSourceGraphFallbackPublisher:
                        layerSourceGraphFallbackPublisher,
                    pipeline: imagePipeline,
                    mainPass: mainPass,
                    executionTrace: effectExecutionTrace,
                    executionOrigin: Self.effectExecutionOrigin(
                        for: layer.contentKind
                    )
                )
                if case .layerSourcePassthrough = drawOutcome {
                    ScenePerformanceCounterHub.shared.bump(.fallbackBranches)
                }
#if DEBUG
                if frameDynamicLayerIDs.contains(layer.id) {
                    if drawOutcome.encoded {
                        dynamicEncodedLayerCount += 1
                    }
                    if case .layerSourcePassthrough = drawOutcome {
                        dynamicPassthroughLayerCount += 1
                    }
                }
#endif
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
            case "composition":
                if resolvedMaterialFrameTargetPlans[layer.id] == nil,
                   let imagePipeline {
                    _ = drawCompositionSourceFallback(
                        layer: layer,
                        imageTextures: imageTextures,
                        imagePipeline: imagePipeline,
                        frameContext: frameContext,
                        worldFramesByLayerID: frameWorldFrames,
                        cameraFrame: cameraFrame,
                        parallaxConfiguration: parallaxConfiguration,
                        time: time,
                        mainPass: mainPass,
                        executionTrace: effectExecutionTrace
                    )
                }
            case "project", "fullscreen":
                break
            case "model":
                guard let pipeline = staticModelResources.pipeline,
                      let preparedParts = staticModelResources[layer.id] else { continue }
                for prepared in preparedParts {
                    let albedoTexture: MTLTexture
                    let albedoTextureFrame: SceneTextureUVTransform
                    let albedoSampling: SceneTextureSampling
                    let albedoIsPremultiplied: Bool
                    if let albedo = prepared.albedo {
                        albedoTexture = albedo.texture
                        albedoTextureFrame = albedo.uvTransform
                        albedoSampling = albedo.sampling
                        albedoIsPremultiplied = false
                    } else if let reference = prepared.namedAlbedo,
                              let albedo = dependencyRuntime.staticModelNamedAlbedo(
                                  for: layer.id,
                                  materialPath: prepared.materialPath,
                                  expectedReference: reference,
                                  textureRegistry: textureRegistry
                              ) {
                        albedoTexture = albedo.texture
                        albedoTextureFrame = albedo.textureFrame
                        albedoSampling = albedo.sampling
                        albedoIsPremultiplied = albedo.isPremultiplied
                    } else {
                        dependencyRuntime.recordStaticModelBindingFailure(
                            for: layer.id
                        )
                        continue
                    }
                    let modelMatrix = frameWorldFrames[layer.id]
                        ?? SceneMatrix.identity()
                    let depthTarget = staticModelDepthPlan.target(
                        geometryIdentity: prepared.geometryIdentity,
                        modelMatrix: modelMatrix
                    )
                    if staticModelDepthLease == nil, depthTarget == .shared {
                        let targetExtent = mainPass.targetExtent
                        staticModelDepthLease = staticModelDepthTargetPool.acquire(
                            device: device,
                            width: targetExtent.width,
                            height: targetExtent.height
                        )
                        if let staticModelDepthLease {
                            frameDepthLeases.append(staticModelDepthLease)
                        }
                    }
                    let modelDepthLease: SceneParticleDepthTargetLease?
                    let clearsModelDepth: Bool
                    switch depthTarget {
                    case .shared:
                        modelDepthLease = staticModelDepthLease
                        clearsModelDepth = !staticModelDepthWasCleared
                    case .isolated:
                        let targetExtent = mainPass.targetExtent
                        modelDepthLease = staticModelDepthTargetPool.acquire(
                            device: device,
                            width: targetExtent.width,
                            height: targetExtent.height
                        )
                        if let modelDepthLease {
                            frameDepthLeases.append(modelDepthLease)
                        }
                        clearsModelDepth = true
                    }
                    guard let modelDepthLease,
                          let encoder = mainPass.encoder(
                              depthTexture: modelDepthLease.texture,
                              clearsDepth: clearsModelDepth,
                              clearDepth: 0
                          ) else {
                        continue
                    }
                    if depthTarget == .shared {
                        staticModelDepthWasCleared = true
                    }
                    let alpha = Float(SceneDynamicLayerValues.alpha(
                        layerID: layer.id,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    ))
                    let material = prepared.material.resolvingDynamicValues(
                        layerID: layer.id, materialPath: prepared.dynamicMaterialPath,
                        snapshot: frameContext.dynamicValues
                    ).resolvingDynamicViewTintBack(
                        SceneDynamicLayerValues.color(
                            layerID: layer.id,
                            authoredValue: prepared.material.viewTint.map {
                                [$0.back.x, $0.back.y, $0.back.z]
                            },
                            snapshot: frameContext.dynamicValues
                        )
                    )
                    let encoded = pipeline.draw(
                        mesh: prepared.mesh,
                        texture: albedoTexture,
                        colorTextureIsPremultiplied: albedoIsPremultiplied,
                        emissiveMask: prepared.emissiveMask?.texture,
                        emissiveMaskTextureFrame: prepared.emissiveMask?.uvTransform,
                        emissiveMaskSampling: prepared.emissiveMask?.sampling,
                        modelMatrix: modelMatrix,
                        viewProjection: cameraFrame.reverseDepthViewProjection(
                            usesPerspective: cameraFrame.resolvesPerspective(for: layer)
                        ),
                        cameraPosition: cameraFrame.perspectiveEyePosition,
                        textureFrame: albedoTextureFrame,
                        sampling: albedoSampling,
                        layerAlpha: alpha,
                        material: material,
                        lighting: frameLightSnapshot,
                        writesDepth: prepared.writesDepth,
                        encoder: encoder
                    )
                    dependencyRuntime.recordStaticModelBindingIfRequired(
                        for: layer.id,
                        encoded: encoded,
                        on: commandBuffer
                    )
                }
            case "quad":
                if !drawQuadLayer(
                    layer: layer,
                    resolvedFramePlan: resolvedMaterialFrameTargetPlans[layer.id],
                    imagePipeline: imagePipeline,
                    frameContext: frameContext,
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
                if let depthLease = renderParticleBatches(
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
                ) {
                    frameDepthLeases.append(depthLease)
                }
            default:
                continue
            }
        }
        performanceTelemetry?.endStage("layer-loop")
        hubStage(.layerLoopMicros, hubLayerLoopStart)

        performanceTelemetry?.beginStage("compositor-seal")
        let hubCompositorSealStart = ProcessInfo.processInfo.systemUptime
        mainPass.finishEnsuringClear()
        encodeFrameReadback?(drawable.texture, commandBuffer)
        guard imageCompositor.endResolvedMaterialFrame(on: commandBuffer) else {
            return .dropped(reasonCode: "resolved-material-frame-seal-rejected")
        }
#if DEBUG
        reportDynamicLayerRenderEvidence(
            projection: frameProjection,
            imageTextures: imageTextures,
            dynamicValues: frameContext.dynamicValues,
            encodedLayerCount: dynamicEncodedLayerCount,
            passthroughLayerCount: dynamicPassthroughLayerCount,
            frameIndex: frameContext.frameIndex,
            topologyRevision: layerTopology?.topologyRevision ?? 0,
            commandBuffer: commandBuffer
        )
#endif
        onDrawableWillPresent?(drawable)
        commandBuffer.present(drawable)
        if let effectExecutionTrace {
            effectExecutionTelemetry.observeSharedCommandBuffer(
                for: effectExecutionTrace,
                on: commandBuffer
            )
        }
        performanceTelemetry?.recordSubmitted(on: commandBuffer)
        sourceUpdateTransaction.arm(on: commandBuffer)
        frameDepthLeases.forEach { $0.arm(on: commandBuffer) }
        commandBuffer.commit()
        didCommitParticleSubmission = true
        sourceUpdateTransaction.didSubmit()
        performanceTelemetry?.endStage("compositor-seal")
        hubStage(.compositorSealMicros, hubCompositorSealStart)
        if let cpuStart {
            performanceTelemetry?.recordCPUFrame(
                duration: ProcessInfo.processInfo.systemUptime - cpuStart
            )
        }
        return .submitted
    }
}
