import AppKit
import Metal
import QuartzCore
// Layer-hosting NSView that drives SceneMetalRenderer through a CAMetalLayer.
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
    private var effectTextures = SceneLayerEffectTextureStore()
    private var imagePipeline: SceneImageLayerPipeline?
    private var particlePlayback: SceneParticlePlaybackState?
    private var dynamicTextTextures: SceneDynamicTextTextureStore?
    private let offscreenTexturePool: SceneOffscreenTexturePool
    var pointerState = SceneSurfacePointerState()
    var parallaxPointerSmoother: SceneParallaxPointerSmoother
    var trackingArea: NSTrackingArea?
#if DEBUG
    let debugFrameCapture = SceneDebugFrameCapture()
#endif
    init?(
        renderDescriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        sceneScriptAudioBarsProgram: SceneScriptAudioBarsProgram = .empty,
        pipelineRepository: SceneImageEffectPipelineRepository,
        userPropertyTextureURLs: [String: URL] = [:],
        frame: NSRect
    ) {
        guard let renderer = SceneMetalRenderer(
            renderDescriptor: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            sceneScriptAudioBarsProgram: sceneScriptAudioBarsProgram,
            pipelineRepository: pipelineRepository
        ) else { return nil }
        self.metalDevice = renderer.device
        self.renderer = renderer
        self.solidLayerTexture = SceneSolidLayerTexture.make(device: renderer.device)
        let preservedPropertyKeys = Set(renderDescriptor.layers.flatMap { layer -> [String] in
            guard let declaration = SceneXRayRuntimePlanner.declaration(for: layer) else {
                return []
            }
            return [
                declaration.blendPropertyKey,
                declaration.haloPropertyKey,
            ].compactMap { $0 }
        })
        self.userPropertyTextureLoad = SceneUserPropertyTextureLoader().load(
            urlsByPropertyKey: userPropertyTextureURLs,
            preservedPropertyKeys: preservedPropertyKeys,
            device: renderer.device
        )

        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = !renderDescriptor.requiresReadableFramebuffer(
            authoredEffectCatalog: authoredEffectCatalog
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

        // Layer-hosting view: set layer before wantsLayer = true.
        self.layer = layer
        self.wantsLayer = true
        self.imagePipeline = SceneImageLayerPipeline(device: metalDevice)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Pointer input
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        configurePointerTracking()
    }

    override func mouseMoved(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseEntered(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseExited(with event: NSEvent) { handlePointerExit() }
    override func mouseDown(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseUp(with event: NSEvent) { handlePointerEvent(event) }

    // MARK: - Texture loading
    // Loads image layers and optionally writes a report for black-preview diagnosis.
    func loadImageLayers(
        from cacheDirectory: URL, resourceView: SceneResourceView,
        videoSourceRegistry: SceneVideoTextureSourceRegistry,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader, logURL: URL? = nil
    ) {
        let loader = SceneTextureLoader()
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: renderer.renderDescriptor
        )
        var report: [String] = []
        var loaded = SceneBaseImageTextureStore()
        var loadedSpriteAnimations: [Int: SceneSpriteAnimation] = [:]
        var loadedVideoSources: [Int: SceneVideoTextureSource] = [:]
        var loadedPuppetPlaybackStates: [Int: ScenePuppetPlaybackState] = [:]
        var loadedEffectTextures = SceneLayerEffectTextureStore()
        var puppetRecomposeBytes = 0
        // 所有渲染层都要装载 effect 实例资源，mp4 payload 视频层也不能遗漏。
        func loadEffectTextures(for layer: SceneRenderDescriptor.Layer) -> SceneLayerEffectTextures {
            let stages = renderer.authoredEffectChain(for: layer.id)?.stages ?? []
            let textures = SceneLayerEffectTextureLoader.load(
                for: layer,
                stages: stages,
                resolver: resolver,
                loader: loader,
                device: metalDevice,
                userPropertyTextures: userPropertyTextureLoad.textures,
                userPropertyTextureCandidates: userPropertyTextureLoad.textureCandidates,
                preservedUserPropertyTextures: userPropertyTextureLoad.preservedTextures
            )
            loadedEffectTextures.merge(layerID: layer.id, textures: textures)
            return textures
        }
        report.append("Scene preview texture load report")
        report.append("camera: projection=cover parallax=\(renderer.renderDescriptor.camera.parallaxEnabled) amount=\(renderer.renderDescriptor.camera.parallaxAmount) delay=\(renderer.renderDescriptor.camera.parallaxDelay) mouseInfluence=\(renderer.renderDescriptor.camera.parallaxMouseInfluence)")
        report.append("cacheDirectory: \(cacheDirectory.path)")
        report.append(contentsOf: userPropertyTextureLoad.reportLines)
        let imageLayers = renderer.renderDescriptor.layers.filter(\.isImageRenderable)
        report.append("imageLayerCount: \(imageLayers.count)")
        report.append("solidLayerCount: \(imageLayers.filter { $0.contentKind == "solid" }.count)")
        report.append(contentsOf: renderer.runtimeReportLines())
        report.append(contentsOf: SceneImageBlendRenderPlan(
            descriptor: renderer.renderDescriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: renderer.renderDescriptor)
        ).reportLines())
        for layer in imageLayers {
            let name = layer.name ?? "(unnamed)"
            let placementSummary = renderer.debugPlacementSummary(for: layer)
            if layer.contentKind == "solid" {
                guard let texture = solidLayerTexture else {
                    report.append("layer \(layer.id) \"\(name)\": procedural solid texture unavailable; \(placementSummary)")
                    continue
                }
                loaded.set(texture, candidate: nil, layerID: layer.id)
                let effectTextures = loadEffectTextures(for: layer)
                let color = SIMD3(layer.colorRGB ?? [], fill: 1)
                var message = String(
                    format: "layer %d \"%@\": OK procedural solid tint=(%.5f, %.5f, %.5f)",
                    layer.id, name, color.x, color.y, color.z
                )
                message += effectTextures.message
                if let effectSummary = renderer.effectRuntimeSummary(for: layer, hasWaterMask: effectTextures.waterMask != nil, hasFoliageMask: effectTextures.foliageMask != nil) {
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
            if let videoSource = videoSourceRegistry.source(
                from: url,
                layerID: layer.id,
                cacheDirectory: cacheDirectory,
                device: metalDevice,
                loader: loader
            ) {
                loadedVideoSources[layer.id] = videoSource
                let effectTextures = loadEffectTextures(for: layer)
                var message = "layer \(layer.id) \"\(name)\": mp4 payload video source ready (\(url.lastPathComponent))"
                message += " [\(resourceView.displayPath(for: url))]"
                message += effectTextures.message
                if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                    message += "; \(effectSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
                continue
            }
            switch SceneBaseImageTextureLoad.load(
                from: url,
                usesPuppet: layer.puppetMeshPath != nil,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                textureAnimationPlan: SceneTextureAnimationScriptCompiler.compile(
                    layerID: layer.id, definitions: layer.textureAnimationScripts ?? []
                ),
                device: metalDevice
            ) {
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
                message += puppetMessage
                if let animation = baseLoad.animation {
                    loadedSpriteAnimations[layer.id] = animation
                    message += animation.reportSummary
                }
                let effectTextures = loadEffectTextures(for: layer)
                message += effectTextures.message
                if let effectSummary = renderer.effectRuntimeSummary(
                    for: layer,
                    hasWaterRippleNormal: effectTextures.waterRippleNormal != nil,
                    hasOpacityMask: effectTextures.opacityMask != nil,
                    hasWaterMask: effectTextures.waterMask != nil,
                    hasFoliageMask: effectTextures.foliageMask != nil
                ) {
                    message += "; \(effectSummary)"
                }
                if let inlineSummary = SceneInlineEffectRuntime.summary(
                    for: layer,
                    hasWaterMask: effectTextures.waterMask != nil,
                    handlesWaterWaves: (renderer.authoredEffectChain(for: layer.id)?
                        .waterWavesCount ?? 0) > 0
                ) {
                    message += "; \(inlineSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
            case .failed(let failure):
                report.append(SceneBaseImageTextureLoad.failureReportLine(
                    failure,
                    layer: .init(id: layer.id, name: name),
                    url: url,
                    placementSummary: placementSummary
                ))
            }
        }
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderer.renderDescriptor,
            authoredEffectCatalog: renderer.authoredEffectCatalog
        )
        let effectOnlyLayers = renderer.renderDescriptor.layers.filter { layer in
            let chain = renderer.authoredEffectChain(for: layer.id)
            return (utilityPlans[layer.id]?.shouldCapture == true && chain != nil)
                || (layer.contentKind == "quad" && (chain?.lightShaftsCount ?? 0) > 0)
        }
        for layer in effectOnlyLayers {
            let effectTextures = loadEffectTextures(for: layer)
            report.append(
                "effect-only layer \(layer.id) \"\(layer.name ?? "(unnamed)")\""
                    + effectTextures.message
            )
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
        // text layer 纹理走 CoreText 栅格化，不经过上面的 image 循环；带 authored effect 的
        // text 层同样要装载 per-effect 贴图，否则链在执行期取不到整段失败（同 mp4 视频层先例）。
        for layer in renderer.renderDescriptor.layers
        where layer.contentKind == "text" && renderer.authoredEffectChain(for: layer.id) != nil {
            let effectTextures = loadEffectTextures(for: layer)
            if !effectTextures.message.isEmpty {
                report.append(
                    "text layer \(layer.id) \"\(layer.name ?? "(unnamed)")\" effect resources"
                        + effectTextures.message
                )
            }
        }
        dynamicTextTextures = SceneDynamicTextTextureStore(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            initialTextures: textLoad.textures
        )
        report.append(contentsOf: textLoad.messages)
        videoTextureSources = loadedVideoSources
        puppetPlaybackStates = loadedPuppetPlaybackStates
        effectTextures = loadedEffectTextures
        particlePlayback = SceneParticlePlaybackState(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice, resourceView: resourceView, textureLoader: loader
        )
        if let particlePlayback {
            report.append(contentsOf: particlePlayback.loadReportLines(descriptor: renderer.renderDescriptor))
        } else {
            report.append("particle runtime: pipeline unavailable")
        }
        report.append("")
        let loadedLayerCount = Set(loaded.textures.keys).union(loadedVideoSources.keys).count
        report.append("loaded: \(loadedLayerCount) / \(report.filter { $0.starts(with: "layer ") }.count)")
        if let logURL {
            try? report.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    func renderFrame(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil
    ) {
        let frameStart = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        guard let drawable = metalLayer.nextDrawable() else {
            performanceTelemetry?.recordDrawableMiss()
            return
        }
        let drawableAcquired = performanceTelemetry.map { _ in ProcessInfo.processInfo.systemUptime }
        let parallaxMouseNormalized = parallaxPointerSmoother.advance(delta: timing.frameTime)
        let frameContext = makeFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            parallax: parallaxMouseNormalized,
            audioSpectrum: audioSpectrum
        )
        pointerState.previous = pointerState.current
        let particleBatches = particlePlayback?.advance(by: timing.frameTime, dynamicValues: dynamicValues) ?? []
        dynamicTextTextures?.update(from: dynamicValues)
        let dynamicTextSnapshot = dynamicTextTextures?.snapshot()
        let frameImageTextures = SceneFrameLayerTextureAssembly.make(
            base: imageTextures, dynamicText: dynamicTextSnapshot,
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
            dynamicTextRenderSizes: dynamicTextSnapshot?.renderSizes ?? [:],
            userPropertyTextures: userPropertyTextureLoad.textures,
            spriteAnimations: spriteAnimations,
            effectTextures: effectTextures,
            imagePipeline: imagePipeline,
            particleBatches: particleBatches,
            particlePipeline: particlePlayback?.pipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            encodeSourceUpdates: { [puppetPlaybackStates, spriteAnimations] commandBuffer in
                for animation in spriteAnimations.values {
                    animation.encode(
                        sceneTime: Float(frameContext.sceneTime), wallDate: frameContext.wallDate,
                        commandBuffer: commandBuffer
                    )
                }
                for playback in puppetPlaybackStates.values {
                    playback.encode(sceneTime: frameContext.sceneTime, commandBuffer: commandBuffer)
                }
            },
            encodeFrameReadback: frameReadback,
            performanceTelemetry: performanceTelemetry,
            to: drawable
        )
    }
}
