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
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let staticModelResources: ScenePreparedStaticModelResources
    let spotLightRuntime: SceneSpotLightRuntime
    let dependencyRuntime: SceneDependencyFrameRuntime
    let textureRegistry = SceneFrameTextureRegistry()
    let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
    private let effectExecutionTelemetry = SceneEffectExecutionTelemetry()
    private let staticModelDepthTargetPool = SceneParticleDepthTargetPool()
    init?(
        renderDescriptor: SceneRenderDescriptor,
        effectAdmissionCatalog: SceneEffectAdmissionCatalog,
        baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        staticModelResources: ScenePreparedStaticModelResources = .empty,
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
        self.baseMaterialProviderBindings = baseMaterialProviderBindings
        self.staticModelResources = staticModelResources
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
        let resolvedMaterialVisibleRootLayerIDs =
            resolvedMaterialRuntime?.visibleExecutionRootLayerIDs ?? []
        let executableUtilityConsumerLayerIDs = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: renderDescriptor,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        self.dependencyRuntime = SceneDependencyFrameRuntime(
            descriptor: renderDescriptor,
            visibleLayerIDs:
                visibleLayerIDs.union(resolvedMaterialVisibleRootLayerIDs),
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            verifiedXRayStageKeys: effectAdmissionCatalog.verifiedXRayStageKeys,
            admittedResolvedMaterialReferences: resolvedMaterialRuntime?
                .admittedResolvedMaterialReferences ?? [],
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
        let worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            descriptor: renderDescriptor, byID: byID
        )
        self.worldFramesByLayerID = worldFramesByLayerID
        self.parallaxByLayerID = SceneLayerParallax.resolveAll(layersByID: byID)
    }

    func installResolvedMaterialExecutionEvidence() {
        let dispositionCatalog = SceneEffectRuntimeDispositionCatalog(
            descriptor: renderDescriptor,
            admissionCatalog: effectAdmissionCatalog,
            resolvedMaterialSubjects: imageCompositor.resolvedMaterialRuntime?
                .runtimeDispositionSubjects ?? []
        )
        imageCompositor.resolvedMaterialRuntime?.installExecutionEvidence(
            dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects
        )
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
        var frameDepthLeases: [SceneParticleDepthTargetLease] = []
        defer { frameDepthLeases.forEach { $0.cancel() } }
        var staticModelDepthLease: SceneParticleDepthTargetLease?
        var staticModelDepthWasCleared = false
        var staticModelDepthPlan = SceneStaticModelDepthPlan()
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
        let dynamicLightColors = Dictionary(uniqueKeysWithValues:
            frameDescriptor.layers.compactMap { layer -> (Int, SIMD3<Float>)? in
                guard layer.spotLight != nil || layer.directionalLight != nil else {
                    return nil
                }
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
            worldFramesByLayerID: frameWorldFrames,
            dynamicLayerColors: dynamicLightColors
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
        var forwardGraphProviderLayerIDs: Set<Int> = []
        if let imagePipeline {
            if let prepared = prepareForwardDependencyProviders(
                orderedLayers: orderedLayers,
                imageTextures: imageTextures,
                imagePipeline: imagePipeline,
                frameContext: frameContext,
                worldFramesByLayerID: frameWorldFrames,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration,
                viewportSize: viewportSize,
                mainPass: mainPass,
                framePlans: resolvedMaterialFrameTargetPlans,
                commandBuffer: commandBuffer,
                executionTrace: effectExecutionTrace
            ) {
                forwardGraphProviderLayerIDs = prepared
            } else {
                stopsAfterClaimedFailure = true
            }
        }
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
                effectExecutionTrace.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-provider-rejected",
                    outcome: .failed(reasonCode: reasonCode)
                )
            } else if baseSource?.usesSystemProvider == true {
                effectExecutionTrace.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-system-provider",
                    outcome: .encoded
                )
            } else if baseSource?.usesUserPropertyProvider == true {
                effectExecutionTrace.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-user-property-provider",
                    outcome: .encoded
                )
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
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(
                        layerOverride: layer.usesPerspective
                    )
                )
                _ = dependencyRuntime.captureProviderIfRequired(
                    layer: layer,
                    sourceTexture: baseSource?.texture,
                    sourceCandidate: baseSource?.candidate,
                    usesAuthoredLayerColor:
                        baseSource?.usesAuthoredLayerColor ?? true,
                    layerMVP: cameraFrame.viewProjection(for: layer)
                        * providerModel,
                    viewportSize: viewportSize,
                    pipeline: imagePipeline,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
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
                let dependencyEffect: SceneDependencyEffectInput?
                let resolvedDependencyFailure: (
                    reasonCode: String,
                    isOrdinaryUnavailable: Bool
                )?
                if dependencyBypassReason != nil {
                    dependencyEffect = nil
                    resolvedDependencyFailure = nil
                } else if requiresDependencyEffect, resolvedFramePlan != nil {
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
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: cameraFrame.resolvesPerspective(
                        layerOverride: layer.usesPerspective
                    )
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
                let layerSourceGraphFallbackPublisher: ((MTLTexture) -> Bool)?
                if dependencyRuntime.requiresGraphOutputCapture(for: layer.id) {
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
                            ) == true
                    }
                } else {
                    layerSourceGraphFallbackPublisher = nil
                }
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
                    layerSourceGraphFallbackPublisher:
                        layerSourceGraphFallbackPublisher,
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
                      let prepared = staticModelResources[layer.id] else {
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
                    layerID: layer.id,
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
                _ = pipeline.draw(
                    mesh: prepared.mesh,
                    texture: prepared.albedo.texture,
                    emissiveMask: prepared.emissiveMask?.texture,
                    emissiveMaskTextureFrame: prepared.emissiveMask?.uvTransform,
                    emissiveMaskSampling: prepared.emissiveMask?.sampling,
                    modelMatrix: modelMatrix,
                    viewProjection: cameraFrame.reverseDepthViewProjection(
                        usesPerspective: cameraFrame.resolvesPerspective(
                            layerOverride: layer.usesPerspective
                        )
                    ),
                    cameraPosition: cameraFrame.perspectiveEyePosition,
                    textureFrame: prepared.albedo.uvTransform,
                    sampling: prepared.albedo.sampling,
                    layerAlpha: alpha,
                    material: material,
                    lighting: frameLightSnapshot,
                    writesDepth: prepared.writesDepth,
                    encoder: encoder
                )
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
        frameDepthLeases.forEach { $0.arm(on: commandBuffer) }
        commandBuffer.commit()
        sourceUpdateTransaction.didSubmit()
        if let cpuStart {
            performanceTelemetry?.recordCPUFrame(
                duration: ProcessInfo.processInfo.systemUptime - cpuStart
            )
        }
    }

}
