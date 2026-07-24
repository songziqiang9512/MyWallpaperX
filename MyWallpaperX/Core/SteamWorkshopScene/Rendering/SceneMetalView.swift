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
    private var imageTextures: [Int: MTLTexture] = [:]
    private var spriteAnimations: [Int: SceneSpriteAnimation] = [:]
    private var videoTextureSources: [Int: SceneVideoTextureSource] = [:]
    private var effectTextures = SceneLayerEffectTextureStore()
    private var imagePipeline: SceneImageLayerPipeline?
    private var particlePlayback: SceneParticlePlaybackState?
    private var dynamicTextTextures: SceneDynamicTextTextureStore?
    private let offscreenTexturePool: SceneOffscreenTexturePool
    var pointerState = SceneSurfacePointerState()
    var parallaxPointerSmoother: SceneParallaxPointerSmoother
    var trackingArea: NSTrackingArea?
#if DEBUG
    private let debugFrameCapture = SceneDebugFrameCapture()
#endif

    init?(
        renderDescriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        userPropertyTextureURLs: [String: URL] = [:],
        frame: NSRect
    ) {
        guard let renderer = SceneMetalRenderer(
            renderDescriptor: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog
        ) else { return nil }
        self.metalDevice = renderer.device
        self.renderer = renderer
        self.solidLayerTexture = SceneSolidLayerTexture.make(device: renderer.device)
        self.userPropertyTextureLoad = SceneUserPropertyTextureLoader().load(
            urlsByPropertyKey: userPropertyTextureURLs, device: renderer.device
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

    // MARK: - Geometry

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        metalLayer.frame = bounds
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        configurePointerTracking()
    }

    override func mouseMoved(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseEntered(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseExited(with event: NSEvent) { handlePointerExit() }
    override func mouseDown(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseUp(with event: NSEvent) { handlePointerEvent(event) }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        metalLayer.contentsScale = scale
        let pixelSize = CGSize(width: max(bounds.width, 1) * scale, height: max(bounds.height, 1) * scale)
        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
        }
    }

    // MARK: - Texture loading

    // Loads textures for every image layer and, when `logURL` is provided,
    // writes a human-readable per-layer load report next to the sample so
    // black previews can be debugged without attaching a debugger.
    func loadImageLayers(from cacheDirectory: URL, logURL: URL? = nil) {
        let loader = SceneTextureLoader()
        let resolver = SceneTexturePathResolver(
            cacheDirectory: cacheDirectory,
            descriptor: renderer.renderDescriptor
        )
        var report: [String] = []
        var loaded: [Int: MTLTexture] = [:]
        var loadedSpriteAnimations: [Int: SceneSpriteAnimation] = [:]
        var loadedVideoSources: [Int: SceneVideoTextureSource] = [:]
        var loadedEffectTextures = SceneLayerEffectTextureStore()
        var puppetRecomposeBytes = 0
        report.append("Scene preview texture load report")
        report.append("camera: projection=cover parallax=\(renderer.renderDescriptor.camera.parallaxEnabled) amount=\(renderer.renderDescriptor.camera.parallaxAmount) delay=\(renderer.renderDescriptor.camera.parallaxDelay) mouseInfluence=\(renderer.renderDescriptor.camera.parallaxMouseInfluence)")
        report.append("cacheDirectory: \(cacheDirectory.path)")
        report.append(contentsOf: userPropertyTextureLoad.reportLines)
        let imageLayers = renderer.renderDescriptor.layers.filter(\.isImageRenderable)
        report.append("imageLayerCount: \(imageLayers.count)")
        report.append("solidLayerCount: \(imageLayers.filter { $0.contentKind == "solid" }.count)")
        report.append(contentsOf: renderer.utilityRuntimeReportLines())
        report.append(contentsOf: renderer.authoredEffectRuntimeReportLines())
        report.append(contentsOf: SceneImageBlendRenderPlan(
            descriptor: renderer.renderDescriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: renderer.renderDescriptor)
        ).reportLines())
        for layer in imageLayers {
            let name = layer.name ?? "(unnamed)"
            let placementSummary = renderer.debugPlacementSummary(for: layer)
            let authoredStages = renderer.authoredEffectChain(for: layer.id)?.stages ?? []
            let shakeEffectIDs = Set(authoredStages.compactMap {
                $0.shake?.effectKey.descriptorID
            })
            let waterFlowEffectIDs = Set(authoredStages.compactMap { $0.waterFlow?.effectKey.descriptorID })
            let waterWavesEffectIDs = Set(authoredStages.compactMap {
                $0.waterWaves?.effectKey.descriptorID
            })
            if layer.contentKind == "solid" {
                guard let texture = solidLayerTexture else {
                    report.append("layer \(layer.id) \"\(name)\": procedural solid texture unavailable; \(placementSummary)")
                    continue
                }
                loaded[layer.id] = texture
                let effectTextures = SceneLayerEffectTextureLoader.load(
                    for: layer, resolver: resolver, loader: loader, device: metalDevice,
                    shakeEffectIDs: shakeEffectIDs, waterFlowEffectIDs: waterFlowEffectIDs,
                    waterWavesEffectIDs: waterWavesEffectIDs,
                    userPropertyTextures: userPropertyTextureLoad.textures
                )
                loadedEffectTextures.merge(layerID: layer.id, textures: effectTextures)
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
            if let videoSource = loader.makeVideoTextureSourceIfNeeded(
                from: url,
                layerID: layer.id,
                cacheDirectory: cacheDirectory,
                device: metalDevice
            ) {
                loadedVideoSources[layer.id] = videoSource
                var message = "layer \(layer.id) \"\(name)\": mp4 payload video source ready (\(url.lastPathComponent))"
                if let initialTexture = videoSource.currentTexture(forHostTime: CACurrentMediaTime()) {
                    message += " → \(initialTexture.width)×\(initialTexture.height)"
                }
                message += " [\(relativePath(for: url, cacheDirectory: cacheDirectory))]"
                if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                    message += "; \(effectSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
                continue
            }
            switch loader.load(from: url, device: metalDevice) {
            case .loaded(let texture):
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
                    puppetMessage = "; \(puppetOutcome.message)"
                }
                loaded[layer.id] = effectiveTexture
                var message = "layer \(layer.id) \"\(name)\": OK \(url.lastPathComponent) → \(texture.width)×\(texture.height) [\(relativePath(for: url, cacheDirectory: cacheDirectory))]"
                message += puppetMessage
                if let animation = SceneSpriteAnimation.load(from: url) {
                    loadedSpriteAnimations[layer.id] = animation
                    message += String(
                        format: "; sprite animation frames=%d duration=%.3fs",
                        animation.frames.count,
                        animation.duration
                    )
                }
                let effectTextures = SceneLayerEffectTextureLoader.load(
                    for: layer,
                    resolver: resolver,
                    loader: loader,
                    device: metalDevice,
                    shakeEffectIDs: shakeEffectIDs, waterFlowEffectIDs: waterFlowEffectIDs,
                    waterWavesEffectIDs: waterWavesEffectIDs,
                    userPropertyTextures: userPropertyTextureLoad.textures
                )
                loadedEffectTextures.merge(layerID: layer.id, textures: effectTextures)
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
                    handlesWaterWaves: waterWavesEffectIDs.isEmpty == false
                ) {
                    message += "; \(inlineSummary)"
                }
                message += "; \(placementSummary)"
                report.append(message)
            case .unsupportedFormat(let ext):
                report.append("layer \(layer.id) \"\(name)\": unsupported \(ext) (\(url.lastPathComponent)); \(placementSummary)")
            case .unsupportedTexFormat(let code):
                report.append("layer \(layer.id) \"\(name)\": unsupported .tex format \(code) (\(url.lastPathComponent)); \(placementSummary)")
            case .texNoEmbeddedImage:
                report.append("layer \(layer.id) \"\(name)\": .tex has no embedded JPEG/PNG (likely DXT) — \(url.lastPathComponent); \(placementSummary)")
            case .texContainsVideoPayload:
                report.append("layer \(layer.id) \"\(name)\": .tex is mp4 payload (animated/video) — \(url.lastPathComponent); \(placementSummary)")
            case .decodeFailed(let msg):
                report.append("layer \(layer.id) \"\(name)\": decode failed (\(msg)); \(placementSummary)")
            case .textureAllocationFailed(let w, let h):
                report.append("layer \(layer.id) \"\(name)\": texture allocation failed at \(w)×\(h); \(placementSummary)")
            }
        }
        let utilityXRayLayers = renderer.renderDescriptor.layers.filter { layer in
            layer.utilityLayer != nil
                && (renderer.authoredEffectChain(for: layer.id)?.xRayCount ?? 0) > 0
        }
        for layer in utilityXRayLayers {
            let effectTextures = SceneLayerEffectTextureLoader.load(
                for: layer,
                resolver: resolver,
                loader: loader,
                device: metalDevice,
                userPropertyTextures: userPropertyTextureLoad.textures
            )
            loadedEffectTextures.merge(layerID: layer.id, textures: effectTextures)
            report.append(
                "utility layer \(layer.id) \"\(layer.name ?? "(unnamed)")\""
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
        imageTextures.merge(textLoad.textures) { _, incoming in incoming }
        dynamicTextTextures = SceneDynamicTextTextureStore(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice,
            initialTextures: textLoad.textures
        )
        report.append(contentsOf: textLoad.messages)
        videoTextureSources = loadedVideoSources
        effectTextures = loadedEffectTextures
        particlePlayback = SceneParticlePlaybackState(
            descriptor: renderer.renderDescriptor,
            cacheDirectory: cacheDirectory,
            device: metalDevice
        )
        if let particlePlayback {
            report.append(contentsOf: particlePlayback.loadReportLines(descriptor: renderer.renderDescriptor))
        } else {
            report.append("particle runtime: pipeline unavailable")
        }
        report.append("")
        let loadedLayerCount = Set(loaded.keys).union(loadedVideoSources.keys).count
        report.append("loaded: \(loadedLayerCount) / \(report.filter { $0.starts(with: "layer ") }.count)")
        if let logURL {
            try? report.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

#if DEBUG
    func requestDebugSnapshot(reason: String, outputDirectory: URL) {
        debugFrameCapture.request(reason: reason, outputDirectory: outputDirectory)
    }
#endif

    func renderFrame(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) {
        guard let drawable = metalLayer.nextDrawable() else { return }
        let parallaxMouseNormalized = parallaxPointerSmoother.advance(delta: timing.frameTime)
        let frameContext = makeFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            parallax: parallaxMouseNormalized
        )
        pointerState.previous = pointerState.current
        let particleBatches = particlePlayback?.advance(by: timing.frameTime) ?? []
        dynamicTextTextures?.update(from: dynamicValues)
        var currentImageTextures = imageTextures
        if let textTextures = dynamicTextTextures?.textures() {
            currentImageTextures.merge(textTextures) { _, incoming in incoming }
        }
        for (layerID, videoSource) in videoTextureSources {
            if let texture = videoSource.currentTexture(forHostTime: timing.hostTime) {
                currentImageTextures[layerID] = texture
            }
        }
#if DEBUG
        let frameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = debugFrameCapture.encodeIfRequested
#else
        let frameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil
#endif
        renderer.renderFrame(
            imageTextures: currentImageTextures,
            userPropertyTextures: userPropertyTextureLoad.textures,
            spriteAnimations: spriteAnimations,
            effectTextures: effectTextures,
            imagePipeline: imagePipeline,
            particleBatches: particleBatches,
            particlePipeline: particlePlayback?.pipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            encodeFrameReadback: frameReadback,
            to: drawable
        )
    }

    private func relativePath(for url: URL, cacheDirectory: URL) -> String {
        url.path.replacingOccurrences(of: cacheDirectory.path + "/", with: "")
    }
}
