import AppKit
import Metal
import QuartzCore
class SceneMetalView: NSView {
    private let metalDevice: MTLDevice
    let renderer: SceneMetalRenderer
    let metalLayer: CAMetalLayer
    private let solidLayerTexture: MTLTexture?
    private let userPropertyTextureLoad: SceneUserPropertyTextureLoadResult
    private var imageTextures = SceneBaseImageTextureStore()
    private var spriteAnimations: [Int: SceneSpriteAnimation] = [:]
    private var videoTextureSources: [Int: SceneVideoTextureSource] = [:]
    private var puppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
    private var imagePipeline: SceneImageLayerPipeline?
    var particlePlayback: SceneParticlePlaybackState?
    private var dynamicTextTextures: SceneDynamicTextTextureStore?
    private var dynamicImageTextures: SceneDynamicImageTextureProvider?
    private weak var preparedBaseImages: ScenePreparedBaseImageResources?
    private var deferredBaseImageURLs: [Int: URL] = [:]
    private let mediaThumbnailCoordinator: SceneMediaThumbnailCoordinator
    let offscreenTexturePool: SceneOffscreenTexturePool
    var pointerState = SceneSurfacePointerState()
    var sceneScriptPointerEvents = SceneSurfacePointerEventBuffer()
    var parallaxPointerSmoother: SceneParallaxPointerSmoother
    var trackingArea: NSTrackingArea?
#if DEBUG
    let debugFrameCapture = SceneDebugFrameCapture()
#endif
    init?(
        renderDescriptor: SceneRenderDescriptor, effectAdmissionCatalog: SceneEffectAdmissionCatalog,
        baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram = .empty,
        pipelineRepository: SceneImageEffectPipelineRepository,
        imageLayerPipeline: SceneImageLayerPipeline,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge,
        userPropertyTextureURLs: [String: URL] = [:],
        frame: NSRect
    ) {
        guard let renderer = SceneMetalRenderer(
            renderDescriptor: renderDescriptor,
            effectAdmissionCatalog: effectAdmissionCatalog,
            baseMaterialProviderBindings: baseMaterialProviderBindings,
            pipelineRepository: pipelineRepository, resolvedMaterialRuntime: resolvedMaterialRuntime
        ) else { return nil }
        self.metalDevice = renderer.device
        self.renderer = renderer
        self.mediaThumbnailCoordinator = .init(
            program: baseMaterialProviderBindings, device: renderer.device
        )
        self.solidLayerTexture = SceneSolidLayerTexture.make(device: renderer.device)
        self.userPropertyTextureLoad = SceneUserPropertyTextureLoader().load(
            urlsByPropertyKey: userPropertyTextureURLs,
            requestedIdentities: resolvedMaterialRuntime.userPropertyDemands(
                including: renderDescriptor.texturePropertyKeys
            ).union(baseMaterialProviderBindings.userPropertyDemands),
            device: renderer.device
        )
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = !renderDescriptor.requiresReadableFramebuffer(
            resolvedMaterialLayerIDs: resolvedMaterialRuntime.executionLayerIDs,
            sceneBackgroundLayerIDs: resolvedMaterialRuntime.sceneBackgroundLayerIDs
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
        self.metalLayer = layer
        self.offscreenTexturePool = SceneOffscreenTexturePool(device: metalDevice)
        self.parallaxPointerSmoother = SceneParallaxPointerSmoother(
            delay: renderDescriptor.camera.parallaxDelay
        )
        super.init(frame: frame)
        self.layer = layer
        self.wantsLayer = true
        self.imagePipeline = imageLayerPipeline
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
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
        var report: [String] = []
        var loaded = SceneBaseImageTextureStore()
        var loadedSpriteAnimations: [Int: SceneSpriteAnimation] = [:]
        var loadedVideoSources: [Int: SceneVideoTextureSource] = [:]
        var loadedPuppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
        var puppetRecomposeBytes = 0
        var preparedBaseImageHitCount = 0
        self.preparedBaseImages = preparedBaseImages
        deferredBaseImageURLs.removeAll(keepingCapacity: true)
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
            let name = layer.name ?? "(unnamed)"
            let placementSummary = renderer.debugPlacementSummary(for: layer)
            if layer.contentKind == "solid" {
                guard let texture = solidLayerTexture else {
                    report.append("layer \(layer.id) \"\(name)\": procedural solid texture unavailable; \(placementSummary)")
                    continue
                }
                loaded.set(texture, candidate: nil, layerID: layer.id)
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
               preparedBaseImage == nil {
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
                var message = "layer \(layer.id) \"\(name)\": mp4 payload video source ready (\(url.lastPathComponent))"
                message += " [\(resourceView.displayPath(for: url))]"
                if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                    message += "; \(effectSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
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
            case .loaded(let baseLoad):
                let texture = baseLoad.texture
                var effectiveTexture = texture
                var puppetMessage = ""
                if let imagePipeline,
                   let puppetOutcome = ScenePuppetLayerLoad.recomposedTexture(
                       for: layer,
                       atlasTexture: texture,
                       cacheDirectory: cacheDirectory,
                       remainingByteBudget: ScenePuppetMeshRecomposer.recomposeByteBudget
                           - puppetRecomposeBytes,
                       device: metalDevice,
                       commandQueue: renderer.commandQueue,
                       pipeline: imagePipeline
                   ) {
                    if let recomposedTexture = puppetOutcome.texture {
                        effectiveTexture = recomposedTexture
                        puppetRecomposeBytes += puppetOutcome.byteCost
                    }
                    if let playback = puppetOutcome.playback {
                        loadedPuppetPlaybackStates[layer.id] = playback
                    }
                    puppetMessage = "; \(puppetOutcome.message)"
                }
                loaded.set(
                    effectiveTexture,
                    candidate: baseLoad.candidate,
                    layerID: layer.id
                )
                var message = "layer \(layer.id) \"\(name)\": OK \(url.lastPathComponent) → \(texture.width)×\(texture.height) [\(resourceView.displayPath(for: url))]"
                message += baseLoad.message
                if preparedBaseImage != nil {
                    message += "; launch-prepared-static-base"
                }
                message += puppetMessage
                if let animation = baseLoad.animation {
                    loadedSpriteAnimations[layer.id] = animation
                    message += animation.reportSummary
                }
                if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                    message += "; \(effectSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
            case .failed(let failure):
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
        imageTextures = loaded
        spriteAnimations = loadedSpriteAnimations
        let textLoad = SceneTextTextureLoader.load(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            effectSummary: { [renderer] in renderer.effectRuntimeSummary(for: $0) }
        )
        imageTextures.merge(textLoad.textures)
        report.append(contentsOf: renderer.runtimeReportLines())
        dynamicTextTextures = SceneDynamicTextTextureStore(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            initialTextures: textLoad.textures
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
        let loadedLayerCount = Set(loaded.textures.keys).union(loadedVideoSources.keys).count
        report.append("loaded: \(loadedLayerCount) / \(report.filter { $0.starts(with: "layer ") }.count)")
        if let logURL {
            try? report.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
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
            deferredBaseImageURLs.removeValue(forKey: layerID)
            return true
        case .failed:
            return false
        }
    }

    func prepareMediaThumbnail(
        from input: SceneMediaThumbnailInbox.Snapshot
    ) -> SceneMediaThumbnailTextureStore.Snapshot {
        mediaThumbnailCoordinator.update(from: input)
    }

    func renderFrame(
        timing: SceneFrameTiming, dynamicValues: SceneDynamicSnapshot,
        layerTopology: SceneScriptLayerTopologySnapshot,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = [],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) {
        let frameStart = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        guard let drawable = metalLayer.nextDrawable() else {
            performanceTelemetry?.recordDrawableMiss()
            return
        }
        let drawableAcquired = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        let parallaxMouseNormalized = parallaxPointerSmoother.advance(delta: timing.simulationFrameTime)
        let frameContext = makeFrameContext(
            timing: timing, dynamicValues: dynamicValues,
            materialFunctionMutations: materialFunctionMutations,
            parallax: parallaxMouseNormalized, audioSpectrum: audioSpectrum)
        let cameraFrame = renderer.makeCameraFrame(frameContext: frameContext)
        pointerState.previous = pointerState.current
        let particleBatches = advanceParticles(
            timing: timing, dynamicValues: dynamicValues,
            frameContext: frameContext, cameraFrame: cameraFrame)
        dynamicTextTextures?.update(
            from: dynamicValues,
            dynamicLayers: layerTopology.dynamicLayers
        )
        let dynamicTextSnapshot = dynamicTextTextures?.snapshot()
        let dynamicImageSnapshot = dynamicImageTextures?.snapshot(
            dynamicLayers: layerTopology.dynamicLayers
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
        renderer.renderFrame(
            imageTextures: frameImageTextures,
            layerTopology: layerTopology,
            userPropertyTextures: userPropertyTextureLoad.textures,
            userPropertyTextureStates: userPropertyTextureLoad.providerStates,
            mediaThumbnail: mediaThumbnail,
            spriteAnimations: spriteAnimations,
            imagePipeline: imagePipeline,
            particleBatches: particleBatches,
            particlePipeline: particlePlayback?.pipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            cameraFrame: cameraFrame,
            encodeSourceUpdates: { [puppetPlaybackStates, spriteAnimations] commandBuffer, transaction in
                for animation in spriteAnimations.values {
                    animation.encode(
                        sceneTime: Float(frameContext.sceneTime),
                        commandBuffer: commandBuffer, transaction: transaction
                    )
                }
                for playback in puppetPlaybackStates.values {
                    playback.encode(sceneTime: frameContext.sceneTime, dynamicValues: frameContext.dynamicValues, commandBuffer: commandBuffer, transaction: transaction)
                }
            },
            encodeFrameReadback: frameReadback,
            performanceTelemetry: performanceTelemetry,
            to: drawable
        )
    }

}
