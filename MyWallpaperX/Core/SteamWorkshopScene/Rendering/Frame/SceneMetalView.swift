import AppKit
import Metal
import QuartzCore
import simd

private struct SceneStartupReportBuffer {
    private var lines: [String]?

    init(enabled: Bool) {
        lines = enabled ? [] : nil
    }

    var isEnabled: Bool {
        lines != nil
    }

    mutating func append(_ line: @autoclosure () -> String) {
        guard lines != nil else { return }
        lines?.append(line())
    }

    mutating func append(contentsOf newLines: @autoclosure () -> [String]) {
        guard lines != nil else { return }
        lines?.append(contentsOf: newLines())
    }

    var layerEntryCount: Int {
        lines?.filter { $0.starts(with: "layer ") }.count ?? 0
    }

    func write(to url: URL?) {
        guard let url, let lines else { return }
        try? lines.joined(separator: "\n").write(
            to: url, atomically: true, encoding: .utf8
        )
    }
}

class SceneMetalView: NSView {
    private let metalDevice: MTLDevice
    private let preparedDynamicTextFieldsByLayerID:
        [Int: Set<SceneDynamicTextField>]
    private let presentationStreamID: UInt64
    private let textureAnimationPlaybackRuntime:
        SceneTextureAnimationPlaybackRuntime
    let renderer: SceneMetalRenderer
    let metalLayer: CAMetalLayer
    private let solidLayerTexture: MTLTexture?
    private let userPropertyTextureLoad: SceneUserPropertyTextureLoadResult
    private var imageTextures = SceneBaseImageTextureStore()
    private var spriteAnimations: [Int: SceneSpriteAnimation] = [:]
    private var specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:]
    private var videoTextureSources: [Int: SceneVideoTextureSource] = [:]
#if DEBUG
    var recordedPuppetPoseLayerIDs: Set<Int> = []
#endif
    var puppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
    private var imagePipeline: SceneImageLayerPipeline?
    var particlePlayback: SceneParticlePlaybackState?
    private var dynamicTextTextures: SceneDynamicTextTextureStore?
    private var pendingDynamicTextUpdate: (
        snapshot: SceneDynamicSnapshot,
        dynamicLayers: [SceneRenderDescriptor.Layer],
        dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>]
    )?
    private var pendingMediaThumbnailInput: SceneMediaThumbnailInbox.Snapshot?
    private var firstFramePresentationRegistration:
        ((CAMetalDrawable) -> Bool)?
    private var dynamicImageTextures: SceneDynamicImageTextureProvider?
    private weak var preparedBaseImages: ScenePreparedBaseImageResources?
    private var deferredBaseImageURLs: [Int: URL] = [:]
    private var adoptedDeferredBaseImageURLs: [Int: URL] = [:]
    private let mediaThumbnailCoordinator: SceneMediaThumbnailCoordinator
    let offscreenTexturePool: SceneOffscreenTexturePool
    var pointerState = SceneSurfacePointerState()
    var sceneScriptPointerEvents = SceneSurfacePointerEventBuffer()
    var parallaxPointerSmoother: SceneParallaxPointerSmoother
    var trackingArea: NSTrackingArea?
    #if DEBUG
        let debugFrameCapture = SceneDebugFrameCapture()
    #endif

    var renderTargetResidentByteCost: Int {
        offscreenTexturePool.residentByteCost
            + renderer.dependencyRuntime.renderTargetResidentByteCost
            + renderer.imageCompositor.renderTargetResidentByteCost
            + renderer.staticModelDepthTargetPool.residentByteCost
            + (particlePlayback?.pipeline.renderTargetResidentByteCost ?? 0)
    }
    init?(
        renderDescriptor: SceneRenderDescriptor, effectAdmissionCatalog: SceneEffectAdmissionCatalog,
        baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        staticModelResources: ScenePreparedStaticModelResources = .empty,
        pipelineRepository: SceneImageEffectPipelineRepository,
        imageLayerPipeline: SceneImageLayerPipeline,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge,
        textureAnimationPlaybackRuntime:
            SceneTextureAnimationPlaybackRuntime,
        textureUploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        userPropertyTextureURLs: [String: URL] = [:],
        dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>] = [:],
        presentationStreamID: UInt64,
        firstFramePresentationRegistration:
            ((CAMetalDrawable) -> Bool)? = nil,
        frame: NSRect
    ) {
        guard let renderer = SceneMetalRenderer(
            renderDescriptor: renderDescriptor,
            effectAdmissionCatalog: effectAdmissionCatalog,
            baseMaterialProviderBindings: baseMaterialProviderBindings,
            staticModelResources: staticModelResources,
            pipelineRepository: pipelineRepository, resolvedMaterialRuntime: resolvedMaterialRuntime
        ) else { return nil }
        metalDevice = renderer.device
        preparedDynamicTextFieldsByLayerID = dynamicTextFieldsByLayerID
        self.presentationStreamID = presentationStreamID
        self.firstFramePresentationRegistration =
            firstFramePresentationRegistration
        self.textureAnimationPlaybackRuntime = textureAnimationPlaybackRuntime
        self.renderer = renderer
        mediaThumbnailCoordinator = .init(
            program: baseMaterialProviderBindings,
            textureUploadCommandQueue: textureUploadCommandQueue,
            device: renderer.device
        )
        solidLayerTexture = SceneSolidLayerTexture.make(device: renderer.device)
        userPropertyTextureLoad = SceneUserPropertyTextureLoader().load(
            urlsByPropertyKey: userPropertyTextureURLs,
            requestedIdentities: resolvedMaterialRuntime.userPropertyDemands(
                including: renderDescriptor.texturePropertyKeys
            ).union(baseMaterialProviderBindings.userPropertyDemands),
            textureUploadCommandQueue: textureUploadCommandQueue,
            textureDecodeCacheBudget: textureDecodeCacheBudget,
            device: renderer.device
        )
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = !renderDescriptor.requiresReadableFramebuffer(
            resolvedMaterialLayerIDs: resolvedMaterialRuntime.executionLayerIDs,
            sceneBackgroundLayerIDs: resolvedMaterialRuntime.sceneBackgroundLayerIDs,
            admittedResolvedMaterialReferences:
                resolvedMaterialRuntime.admittedResolvedMaterialReferences
        )
        #if DEBUG
            debugFrameCapture.configure(layer)
        #endif
        layer.contentsGravity = .resizeAspect
        layer.frame = frame
        // Prime drawableSize so the very first render has a non-zero target.
        let initialScale = NSScreen.main?.backingScaleFactor ?? 1
        layer.contentsScale = initialScale
        layer.drawableSize = CGSize(width: frame.width * initialScale, height: frame.height * initialScale)
        metalLayer = layer
        offscreenTexturePool = SceneOffscreenTexturePool(device: metalDevice)
        parallaxPointerSmoother = SceneParallaxPointerSmoother()
        super.init(frame: frame)
        self.layer = layer
        wantsLayer = true
        imagePipeline = imageLayerPipeline
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    // MARK: - Texture loading and diagnostics

    func loadImageLayers(
        from cacheDirectory: URL, resourceView: SceneResourceView,
        videoSourceRegistry: SceneVideoTextureSourceRegistry,
        preparedBaseImages: ScenePreparedBaseImageResources,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        logURL: URL? = nil
    ) {
        let loader = preparedBaseImages.textureLoader
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: renderer.renderDescriptor
        )
        var report = SceneStartupReportBuffer(enabled: logURL != nil)
        var loaded = SceneBaseImageTextureStore()
        var loadedSpriteAnimations: [Int: SceneSpriteAnimation] = [:]
        var loadedSpecializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:]
        var loadedVideoSources: [Int: SceneVideoTextureSource] = [:]
        var loadedPuppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
        var preparedBaseImageHitCount = 0
        renderer.installResolvedMaterialExecutionEvidence()
        self.preparedBaseImages = preparedBaseImages
        deferredBaseImageURLs.removeAll(keepingCapacity: true)
        adoptedDeferredBaseImageURLs.removeAll(keepingCapacity: true)
        report.append("Scene preview texture load report")
        report.append("camera: projection=cover parallax=\(renderer.renderDescriptor.camera.parallaxEnabled) amount=\(renderer.renderDescriptor.camera.parallaxAmount) delay=\(renderer.renderDescriptor.camera.parallaxDelay) mouseInfluence=\(renderer.renderDescriptor.camera.parallaxMouseInfluence)")
        report.append(SceneCameraShake.reportLine(renderer.renderDescriptor.camera))
        report.append("cacheDirectory: \(cacheDirectory.path)")
        report.append(contentsOf: userPropertyTextureLoad.reportLines)
        report.append(preparedBaseImages.reportLine)
        let imageLayers = renderer.renderDescriptor.layers.filter(\.isImageRenderable)
        report.append("imageLayerCount: \(imageLayers.count)")
        report.append("solidLayerCount: \(imageLayers.filter { $0.contentKind == "solid" }.count)")
        report.append(contentsOf: mediaThumbnailCoordinator.program.reportLines())
        for layer in imageLayers {
            let name = report.isEnabled ? (layer.name ?? "(unnamed)") : ""
            let placementSummary = report.isEnabled
                ? renderer.debugPlacementSummary(for: layer) : ""
            if layer.contentKind == "solid" {
                guard let texture = solidLayerTexture else {
                    report.append("layer \(layer.id) \"\(name)\": procedural solid texture unavailable; \(placementSummary)")
                    continue
                }
                loaded.set(texture, candidate: nil, layerID: layer.id)
                if report.isEnabled {
                    let color = SIMD3(layer.colorRGB ?? [], fill: 1)
                    var message = String(
                        format: "layer %d \"%@\": OK procedural solid tint=(%.5f, %.5f, %.5f)",
                        layer.id, name, color.x, color.y, color.z
                    )
                    if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                        message += "; \(effectSummary)"
                    }
                    message += "; \(placementSummary)"
                    report.append(message)
                }
                continue
            }
            guard let url = resolver.resolvePrimaryTexture(for: layer) else {
                report.append("layer \(layer.id) \"\(name)\": no texture URL (built-in or unresolvable); \(placementSummary)")
                continue
            }
            let preparedBaseImage = preparedBaseImages.outcome(
                for: layer.id,
                url: url,
                device: metalDevice
            )
            if preparedBaseImages.deferredLayerIDs.contains(layer.id),
               preparedBaseImage == nil
            {
                deferredBaseImageURLs[layer.id] = url
                report.append(
                    "layer \(layer.id) \"\(name)\":"
                        + " deferred-static-base; \(placementSummary)"
                )
                continue
            }
            if let videoSource = videoSourceRegistry.source(
                from: url,
                layerID: layer.id,
                cacheDirectory: cacheDirectory,
                device: metalDevice,
                loader: loader
            ) {
                loadedVideoSources[layer.id] = videoSource
                if report.isEnabled {
                    var message = "layer \(layer.id) \"\(name)\":"
                        + " mp4 payload video source ready (\(url.lastPathComponent))"
                    message += " [\(resourceView.displayPath(for: url))]"
                    if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                        message += "; \(effectSummary)"
                    }
                    message += "; \(placementSummary)"
                    report.append(message)
                }
                continue
            }
            let baseImage = preparedBaseImage ?? SceneBaseImageTextureLoad.load(
                from: url,
                usesPuppet: layer.puppetMeshPath != nil,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: metalDevice
            )
            if preparedBaseImage != nil {
                preparedBaseImageHitCount += 1
            }
            switch baseImage {
            case let .loaded(baseLoad):
                let texture = baseLoad.texture
                var puppetMessage: String?
                if layer.puppetMeshPath != nil,
                   let imagePipeline,
                   let puppetOutcome = ScenePuppetLayerLoad.preparedGeometry(
                       for: layer,
                       atlasTexture: texture,
                       cacheDirectory: cacheDirectory,
                       device: metalDevice,
                       pipeline: imagePipeline
                   ) {
                    if let product = puppetOutcome.geometryProduct {
                        loaded.setPuppetGeometry(
                            product,
                            samplingAtlas: texture,
                            samplingCandidate: baseLoad.candidate,
                            layerID: layer.id
                        )
                    } else if puppetOutcome.allowsMissingMeshTextureProduct {
                        loaded.set(texture, candidate: nil, layerID: layer.id)
                    }
                    if let playback = puppetOutcome.playback {
                        loadedPuppetPlaybackStates[layer.id] = playback
                    }
                    if report.isEnabled {
                        puppetMessage = "; \(puppetOutcome.message)"
                    }
                } else if layer.puppetMeshPath == nil {
                    loaded.set(
                        texture,
                        candidate: baseLoad.candidate,
                        layerID: layer.id
                    )
                }
                // Texture animation belongs to the authored base-image
                // resource, not to the quad geometry.  A Puppet layer still
                // samples that TEX through its world-space GeometryProduct,
                // so publish the same prepared definition and playback time
                // to both geometry kinds.
                if let animation = baseLoad.animation {
                    let identity = resourceView.displayPath(for: url)
                    if case .success = textureAnimationPlaybackRuntime.register(
                        layerID: layer.id,
                        sourceIdentity: identity,
                        animation: animation
                    ) {
                        loadedSpriteAnimations[layer.id] = animation
                    } else {
                        report.append(
                            "layer \(layer.id) \"\(name)\":"
                                + " conflicting texture-animation definition"
                        )
                    }
                }
                if let sampling = baseLoad.baseTextureSampling {
                    loadedSpecializedBaseTextureSamplings[layer.id] = sampling
                }
                if report.isEnabled {
                    var message = "layer \(layer.id) \"\(name)\": OK"
                        + " \(url.lastPathComponent) → \(texture.width)×\(texture.height)"
                        + " [\(resourceView.displayPath(for: url))]"
                    message += baseLoad.message
                    if preparedBaseImage != nil {
                        message += "; launch-prepared-static-base"
                    }
                    message += puppetMessage ?? ""
                    if let animation = baseLoad.animation {
                        message += animation.reportSummary
                    }
                    if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                        message += "; \(effectSummary)"
                    }
                    message += "; \(placementSummary)"
                    report.append(message)
                }
            case let .failed(failure):
                if report.isEnabled {
                    var message = SceneBaseImageTextureLoad.failureReportLine(
                        failure,
                        layer: .init(id: layer.id, name: name),
                        url: url,
                        placementSummary: placementSummary
                    )
                    if preparedBaseImage != nil {
                        message += "; launch-prepared-static-base"
                    }
                    report.append(message)
                }
            }
        }
        imageTextures = loaded
        spriteAnimations = loadedSpriteAnimations
        specializedBaseTextureSamplings = loadedSpecializedBaseTextureSamplings
        let textLoad = SceneTextTextureLoader.load(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            recordsDiagnostics: report.isEnabled,
            effectSummary: { [renderer] in renderer.effectRuntimeSummary(for: $0) }
        )
        imageTextures.merge(textLoad.textures)
        report.append(contentsOf: renderer.runtimeReportLines())
        dynamicTextTextures = SceneDynamicTextTextureStore(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            initialTextures: textLoad.textures,
            initialRenderSizes: textLoad.renderSizes,
            dynamicTextFieldsByLayerID: preparedDynamicTextFieldsByLayerID
        )
        dynamicImageTextures = SceneDynamicImageTextureProvider(
            resources: preparedBaseImages.dynamicImageResources
        )
        report.append(contentsOf: textLoad.messages)
        videoTextureSources = loadedVideoSources
        puppetPlaybackStates = loadedPuppetPlaybackStates
        particlePlayback = SceneParticlePlaybackState(
            descriptor: renderer.renderDescriptor, cacheDirectory: cacheDirectory,
            device: metalDevice, resourceView: resourceView, textureLoader: loader,
            layerImage: SceneParticleLayerImageEmitterCompiler.compile(
                descriptor: renderer.renderDescriptor, texturesByLayerID: imageTextures.textures,
                animatedSourceLayerIDs: Set(loadedSpriteAnimations.keys)
            ),
            initialDynamicValues: initialDynamicValues
        )
        if let particlePlayback {
            report.append(contentsOf: particlePlayback.loadReportLines(descriptor: renderer.renderDescriptor))
        } else {
            report.append("particle runtime: pipeline unavailable")
        }
        report.append("")
        report.append(
            "prepared static base resource usage: hits=\(preparedBaseImageHitCount)"
        )
        report.append(
            "prepared static model layers: \(renderer.staticModelResources.preparedLayerIDs)"
        )
        if report.isEnabled {
            let loadedLayerCount = Set(loaded.textures.keys)
                .union(loadedVideoSources.keys).count
            let reportedLayerCount = report.layerEntryCount
            report.append("loaded: \(loadedLayerCount) / \(reportedLayerCount)")
        }
        report.write(to: logURL)
    }

    func adoptPreparedDeferredBaseImage(layerID: Int) -> Bool {
        if imageTextures[layerID] != nil { return true }
        guard let preparedBaseImages,
              let url = deferredBaseImageURLs[layerID],
              let outcome = preparedBaseImages.outcome(
                  for: layerID,
                  url: url,
                  device: metalDevice
              ) else { return false }
        switch outcome {
        case let .loaded(loaded):
            imageTextures.set(
                loaded.texture,
                candidate: loaded.candidate,
                layerID: layerID
            )
            specializedBaseTextureSamplings[layerID] = loaded.baseTextureSampling
            adoptedDeferredBaseImageURLs[layerID] = url
            deferredBaseImageURLs.removeValue(forKey: layerID)
            return true
        case .failed:
            return false
        }
    }

    /// Rolls back a deferred base-image adoption that has not crossed the
    /// host's all-surface property/frame barrier.  The host may have already
    /// adopted a peer surface when a later surface or live-state validation
    /// fails, so this inverse must be explicit rather than relying on the
    /// next visibility request to hide the partially adopted texture.
    func discardPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        for layerID in layerIDs {
            guard let url = adoptedDeferredBaseImageURLs.removeValue(
                forKey: layerID
            ) else { continue }
            imageTextures[layerID] = nil
            specializedBaseTextureSamplings.removeValue(forKey: layerID)
            deferredBaseImageURLs[layerID] = url
        }
    }

    /// Clears rollback records after the property/resource transition has
    /// crossed the host barrier and become the surface's new committed state.
    func commitPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        for layerID in layerIDs {
            adoptedDeferredBaseImageURLs.removeValue(forKey: layerID)
        }
    }

    func prepareMediaThumbnail(
        from input: SceneMediaThumbnailInbox.Snapshot
    ) -> SceneMediaThumbnailTextureStore.Snapshot {
        pendingMediaThumbnailInput = input
        return mediaThumbnailCoordinator.prepareFrame()
    }

    func snapshotParallaxPointerSmoother() -> SceneParallaxPointerSmoother.State {
        parallaxPointerSmoother.snapshot()
    }

    func restoreParallaxPointerSmoother(
        _ state: SceneParallaxPointerSmoother.State
    ) {
        parallaxPointerSmoother.restore(state)
    }

    func snapshotPointerPrevious() -> SIMD2<Float> {
        pointerState.previous
    }

    func restorePointerPrevious(_ value: SIMD2<Float>) {
        pointerState.previous = value
    }

    func renderFrame(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
        layerTopology: SceneScriptLayerTopologySnapshot,
        dynamicTextFieldsByLayerID:
            [Int: Set<SceneDynamicTextField>] = [:],
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = [],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = [],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) -> SceneMetalRenderer.FrameOutcome {
        pendingDynamicTextUpdate = nil
        for playback in puppetPlaybackStates.values {
            playback.apply(scriptBoneMutations: puppetBoneMutations)
        }
        let frameStart = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        // Unconditional always-on drawable wait measurement; independent of
        // the telemetry-gated frameStart/drawableAcquired constants above.
        let hubDrawableWaitStart = ProcessInfo.processInfo.systemUptime
        guard let drawable = metalLayer.nextDrawable() else {
            ScenePerformanceCounterHub.shared.add(
                .drawableWaitMicros,
                ScenePerformanceCounterHub.micros(since: hubDrawableWaitStart)
            )
            performanceTelemetry?.recordDrawableMiss()
            return .deferred(reasonCode: "drawable-unavailable")
        }
        ScenePerformanceCounterHub.shared.add(
            .drawableWaitMicros,
            ScenePerformanceCounterHub.micros(since: hubDrawableWaitStart)
        )
        let drawableAcquired = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        let parallaxPointerState = parallaxPointerSmoother.snapshot()
        let pointerPrevious = pointerState.previous
        let cameraProperty = dynamicValues.cameraPropertyProjection()
        let parallaxDelay = cameraProperty.parallaxDelay
            ?? renderer.renderDescriptor.camera.parallaxDelay
        let parallaxMouseNormalized = parallaxPointerSmoother.advance(
            delta: timing.simulationFrameTime,
            delay: parallaxDelay
        )
        let frameContext = makeFrameContext(
            timing: timing, dynamicValues: dynamicValues,
            materialFunctionMutations: materialFunctionMutations,
            parallax: parallaxMouseNormalized, audioSpectrum: audioSpectrum
        )
        let spriteAnimationPlaybackTimes =
            textureAnimationPlaybackRuntime.playbackTimes(
                layerIDs: spriteAnimations.keys,
                sceneTime: timing.sceneTime
            )
        assert(
            spriteAnimations.keys.allSatisfy {
                spriteAnimationPlaybackTimes[$0] != nil
            },
            "prepared texture animation is missing typed playback state"
        )
        let cameraFrame = renderer.makeCameraFrame(frameContext: frameContext)
        pointerState.previous = pointerState.current
        let dynamicTextSnapshot = dynamicTextTextures?.prepareFrame()
        let dynamicImageSnapshot = dynamicImageTextures?.snapshot(
            topology: layerTopology
        )
        let frameImageTextures = SceneFrameLayerTextureAssembly.make(
            base: imageTextures, dynamicImage: dynamicImageSnapshot,
            dynamicText: dynamicTextSnapshot,
            mediaThumbnail: mediaThumbnail, mediaBindings: mediaThumbnailCoordinator.program,
            videoSources: videoTextureSources, timing: timing
        )
        #if DEBUG
            let frameReadback = debugFrameCapture.encodeIfRequested
        #else
            let frameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil
        #endif
        if let frameStart, let drawableAcquired {
            performanceTelemetry?.recordPreparation(
                drawableWait: drawableAcquired - frameStart,
                preEncode: ProcessInfo.processInfo.systemUptime - drawableAcquired
            )
        }
        let presentationRegistration = firstFramePresentationRegistration
        let onDrawableWillPresent: ((CAMetalDrawable) -> Void)?
        if presentationRegistration != nil || performanceTelemetry != nil {
            onDrawableWillPresent = { [presentationStreamID] drawable in
                _ = presentationRegistration?(drawable)
                performanceTelemetry?.recordWillPresent(
                    drawable,
                    streamID: presentationStreamID
                )
            }
        } else {
            onDrawableWillPresent = nil
        }
        let outcome = renderer.renderFrame(
            imageTextures: frameImageTextures,
            layerTopology: layerTopology,
            userPropertyTextures: userPropertyTextureLoad.textures,
            userPropertyTextureStates: userPropertyTextureLoad.providerStates,
            mediaThumbnail: mediaThumbnail,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
            specializedBaseTextureSamplings: specializedBaseTextureSamplings,
            imagePipeline: imagePipeline,
            particleBatchesProvider: { [performanceTelemetry] in
                advanceParticles(
                    timing: timing, dynamicValues: dynamicValues,
                    frameContext: frameContext, cameraFrame: cameraFrame,
                    performanceTelemetry: performanceTelemetry
                )
            },
            particlePipeline: particlePlayback?.pipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            cameraFrame: cameraFrame,
            encodeSourceUpdates: { [puppetPlaybackStates, spriteAnimations, spriteAnimationPlaybackTimes] commandBuffer, transaction in
                for (layerID, animation) in spriteAnimations {
                    guard let playbackTime =
                        spriteAnimationPlaybackTimes[layerID] else { continue }
                    animation.encode(
                        playbackTime: playbackTime,
                        commandBuffer: commandBuffer, transaction: transaction
                    )
                }
                var framesByParentLayerID: [Int: [String: simd_float4x4]] = [:]
                framesByParentLayerID.reserveCapacity(puppetPlaybackStates.count)
                for playback in puppetPlaybackStates.values {
                    let frames = playback.encode(
                        sceneTime: frameContext.sceneTime,
                        dynamicValues: frameContext.dynamicValues,
                        commandBuffer: commandBuffer,
                        transaction: transaction
                    )
                    if !frames.isEmpty {
                        framesByParentLayerID[playback.layerID] = frames
                    }
                }
                return ScenePuppetAttachmentFrameSnapshot(
                    framesByParentLayerID: framesByParentLayerID
                )
            },
            encodeFrameReadback: frameReadback,
            performanceTelemetry: performanceTelemetry,
            onDrawableWillPresent: onDrawableWillPresent,
            to: drawable
        )
        if outcome.isSubmitted {
            firstFramePresentationRegistration = nil
            // Dynamic text is asynchronous; stage its next request for the
            // host's all-surface submission barrier.
            pendingDynamicTextUpdate = (
                snapshot: dynamicValues,
                dynamicLayers: layerTopology.dynamicLayers,
                dynamicTextFieldsByLayerID: dynamicTextFieldsByLayerID
            )
        } else {
            particlePlayback?.discardPreparedFrame()
            dynamicTextTextures?.discardPreparedFrame()
            parallaxPointerSmoother.restore(parallaxPointerState)
            pointerState.previous = pointerPrevious
        }
        return outcome
    }

    func discardPreparedSpriteFrames() {
        spriteAnimations.values.forEach { $0.discardPreparedFrame() }
    }

    func commitPreparedVideoFrames() {
        videoTextureSources.values.forEach { $0.commitPreparedFrame() }
    }

    func discardPreparedVideoFrames() {
        videoTextureSources.values.forEach { $0.discardPreparedFrame() }
    }

    func commitPreparedMediaThumbnailUpdate() {
        guard let pendingMediaThumbnailInput else {
            mediaThumbnailCoordinator.commitPreparedFrame()
            return
        }
        self.pendingMediaThumbnailInput = nil
        _ = mediaThumbnailCoordinator.update(from: pendingMediaThumbnailInput)
        mediaThumbnailCoordinator.commitPreparedFrame()
    }

    func discardPreparedMediaThumbnailUpdate() {
        pendingMediaThumbnailInput = nil
        mediaThumbnailCoordinator.discardPreparedFrame()
    }

    func commitPreparedFrameTexturePublication() {
        renderer.commitFrameTexturePublication()
    }

    func discardPreparedFrameTexturePublication() {
        renderer.discardFrameTexturePublication()
    }

    func commitPreparedMaterialAssetFrame() {
        renderer.commitResolvedMaterialAssetFrame()
    }

    func discardPreparedMaterialAssetFrame() {
        renderer.discardResolvedMaterialAssetFrame()
    }

    func commitPreparedDynamicTextUpdate() {
        guard let pendingDynamicTextUpdate else {
            dynamicTextTextures?.commitPreparedFrame()
            return
        }
        self.pendingDynamicTextUpdate = nil
        dynamicTextTextures?.update(
            from: pendingDynamicTextUpdate.snapshot,
            dynamicLayers: pendingDynamicTextUpdate.dynamicLayers,
            dynamicTextFieldsByLayerID:
                pendingDynamicTextUpdate.dynamicTextFieldsByLayerID
        )
        dynamicTextTextures?.commitPreparedFrame()
    }

    func discardPreparedDynamicTextUpdate() {
        pendingDynamicTextUpdate = nil
        dynamicTextTextures?.discardPreparedFrame()
    }
}
