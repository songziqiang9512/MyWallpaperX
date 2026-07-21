import AppKit
import Metal
import QuartzCore

// Layer-hosting NSView that drives SceneMetalRenderer through a CAMetalLayer.
class SceneMetalView: NSView {
    private let metalDevice: MTLDevice
    private let renderer: SceneMetalRenderer
    private let metalLayer: CAMetalLayer
    private var imageTextures: [Int: MTLTexture] = [:]
    private var videoTextureSources: [Int: SceneVideoTextureSource] = [:]
    private var irisMaskTextures: [Int: MTLTexture] = [:]
    private var opacityMaskTextures: [Int: MTLTexture] = [:]
    private var waterMaskTextures: [Int: MTLTexture] = [:]
    private var foliageMaskTextures: [Int: MTLTexture] = [:]
    private var imagePipeline: SceneImageLayerPipeline?
    private let offscreenTexturePool: SceneOffscreenTexturePool
    private var displayTimer: Timer?
    // Wall-clock anchor for the shader `g_Time` uniform. Resampled per frame
    // and passed to the renderer so shader-side effects (foliagesway, etc.)
    // advance in real time independent of frame rate.
    private let renderStartTime = CACurrentMediaTime()
    // Mouse position normalized to view bounds: x and y in [-1, +1] with
    // (0,0) at the view's center, +Y up. Defaults to (0,0) when the cursor
    // is outside the view. Drives parallax camera offset + cursorripple UV.
    private var mouseNormalized: SIMD2<Float> = .zero
    private var trackingArea: NSTrackingArea?

    init?(renderDescriptor: SceneRenderDescriptor, frame: NSRect) {
        guard let renderer = SceneMetalRenderer(renderDescriptor: renderDescriptor) else { return nil }
        self.metalDevice = renderer.device
        self.renderer = renderer

        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.contentsGravity = .resizeAspect
        layer.frame = frame
        // Prime drawableSize so the very first render has a non-zero target.
        let initialScale = NSScreen.main?.backingScaleFactor ?? 1
        layer.contentsScale = initialScale
        layer.drawableSize = CGSize(width: frame.width * initialScale, height: frame.height * initialScale)
        self.metalLayer = layer
        self.offscreenTexturePool = SceneOffscreenTexturePool(device: metalDevice)

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

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateMouseNormalized(event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateMouseNormalized(event)
    }

    override func mouseExited(with event: NSEvent) {
        mouseNormalized = .zero
    }

    func updateMouseLocationInScreen(_ screenPoint: CGPoint) {
        guard let window else {
            mouseNormalized = .zero
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let local = convert(windowPoint, from: nil)
        guard bounds.contains(local), bounds.width > 0, bounds.height > 0 else {
            mouseNormalized = .zero
            return
        }
        let nx = Float((local.x / bounds.width) * 2 - 1)
        let ny = Float((local.y / bounds.height) * 2 - 1)
        mouseNormalized = SIMD2(
            max(-1, min(1, nx)),
            max(-1, min(1, ny))
        )
    }

    private func updateMouseNormalized(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let nx = Float((local.x / bounds.width) * 2 - 1)
        let ny = Float((local.y / bounds.height) * 2 - 1)
        mouseNormalized = SIMD2(
            max(-1, min(1, nx)),
            max(-1, min(1, ny))
        )
    }

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
        var loadedVideoSources: [Int: SceneVideoTextureSource] = [:]
        var loadedIrisMasks: [Int: MTLTexture] = [:]
        var loadedOpacityMasks: [Int: MTLTexture] = [:]
        var loadedWaterMasks: [Int: MTLTexture] = [:]
        var loadedFoliageMasks: [Int: MTLTexture] = [:]
        report.append("Scene preview texture load report")
        report.append("cacheDirectory: \(cacheDirectory.path)")
        report.append("imageLayerCount: \(renderer.renderDescriptor.layers.filter { $0.contentKind == "image" }.count)")
        report.append("")
        for layer in renderer.renderDescriptor.layers where layer.contentKind == "image" {
            let name = layer.name ?? "(unnamed)"
            let placementSummary = renderer.debugPlacementSummary(for: layer)
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
                loaded[layer.id] = texture
                var message = "layer \(layer.id) \"\(name)\": OK \(url.lastPathComponent) → \(texture.width)×\(texture.height) [\(relativePath(for: url, cacheDirectory: cacheDirectory))]"
                if let effectSummary = renderer.effectRuntimeSummary(for: layer) {
                    message += "; \(effectSummary)"
                }
                if let irisMaskURL = resolveEffectMaskTextureURL(
                    for: layer,
                    effectNameFragment: "iris",
                    resolver: resolver
                ) {
                    appendMaskLoadMessage(
                        layerID: layer.id,
                        label: "iris mask",
                        maskURL: irisMaskURL,
                        loader: loader,
                        message: &message,
                        loadedMasks: &loadedIrisMasks
                    )
                }
                if let opacityMaskURL = resolveEffectMaskTextureURL(
                    for: layer,
                    effectNameFragment: "opacity",
                    resolver: resolver
                ) {
                    appendMaskLoadMessage(
                        layerID: layer.id,
                        label: "opacity mask",
                        maskURL: opacityMaskURL,
                        loader: loader,
                        message: &message,
                        loadedMasks: &loadedOpacityMasks
                    )
                }
                if let waterMaskURL = resolveWaterEffectMaskTextureURL(for: layer, resolver: resolver) {
                    appendMaskLoadMessage(
                        layerID: layer.id,
                        label: "water mask",
                        maskURL: waterMaskURL,
                        loader: loader,
                        message: &message,
                        loadedMasks: &loadedWaterMasks
                    )
                }
                if let foliageMaskURL = resolveFoliageEffectMaskTextureURL(for: layer, resolver: resolver) {
                    appendMaskLoadMessage(
                        layerID: layer.id,
                        label: "foliage mask",
                        maskURL: foliageMaskURL,
                        loader: loader,
                        message: &message,
                        loadedMasks: &loadedFoliageMasks
                    )
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
        imageTextures = loaded
        let textLoad = SceneTextTextureLoader.load(descriptor: renderer.renderDescriptor, cacheDirectory: cacheDirectory, device: metalDevice)
        imageTextures.merge(textLoad.textures) { _, incoming in incoming }
        report.append(contentsOf: textLoad.messages)
        videoTextureSources = loadedVideoSources
        irisMaskTextures = loadedIrisMasks
        opacityMaskTextures = loadedOpacityMasks
        waterMaskTextures = loadedWaterMasks
        foliageMaskTextures = loadedFoliageMasks
        report.append("")
        let loadedLayerCount = Set(loaded.keys).union(loadedVideoSources.keys).count
        report.append("loaded: \(loadedLayerCount) / \(report.filter { $0.starts(with: "layer ") }.count)")
        if let logURL {
            try? report.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Render loop

    func startRendering() {
        guard displayTimer == nil else { return }
        // Use .common so the timer keeps firing during menu tracking and live resize.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    func stopRendering() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func renderFrame() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        let elapsed = Float(CACurrentMediaTime() - renderStartTime)
        let hostTime = CACurrentMediaTime()
        var currentImageTextures = imageTextures
        for (layerID, videoSource) in videoTextureSources {
            if let texture = videoSource.currentTexture(forHostTime: hostTime) {
                currentImageTextures[layerID] = texture
            }
        }
        renderer.renderFrame(
            imageTextures: currentImageTextures,
            irisMaskTextures: irisMaskTextures,
            opacityMaskTextures: opacityMaskTextures,
            waterMaskTextures: waterMaskTextures,
            foliageMaskTextures: foliageMaskTextures,
            imagePipeline: imagePipeline,
            offscreenTexturePool: offscreenTexturePool,
            time: elapsed,
            mouseNormalized: mouseNormalized,
            to: drawable,
            viewportSize: metalLayer.drawableSize
        )
    }

    private func resolveEffectMaskTextureURL(
        for layer: SceneRenderDescriptor.Layer,
        effectNameFragment: String,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.file.localizedLowercase.contains(effectNameFragment) {
            for pass in effect.passes {
                for texturePath in pass.texturePaths {
                    if let url = resolver.resolveTextureFile(named: texturePath) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func resolveWaterEffectMaskTextureURL(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for fragment in ["waterwaves", "waterripple"] {
            if let url = resolveMaskedEffectTextureURL(
                for: layer,
                effectNameFragment: fragment,
                resolver: resolver
            ) {
                return url
            }
        }
        return nil
    }

    private func resolveFoliageEffectMaskTextureURL(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for fragment in ["foliagesway", "cursorripple"] {
            if let url = resolveMaskedEffectTextureURL(
                for: layer,
                effectNameFragment: fragment,
                resolver: resolver
            ) {
                return url
            }
        }
        return nil
    }

    private func resolveMaskedEffectTextureURL(
        for layer: SceneRenderDescriptor.Layer,
        effectNameFragment: String,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false {
            let lower = effect.file.localizedLowercase
            guard lower.contains(effectNameFragment) else { continue }
            for pass in effect.passes {
                if let texturePath = pass.texturePaths.first(where: { $0.localizedLowercase.contains("mask") }),
                   let url = resolver.resolveTextureFile(named: texturePath) {
                    return url
                }
            }
        }
        return nil
    }

    private func appendMaskLoadMessage(
        layerID: Int,
        label: String,
        maskURL: URL,
        loader: SceneTextureLoader,
        message: inout String,
        loadedMasks: inout [Int: MTLTexture]
    ) {
        switch loader.load(from: maskURL, device: metalDevice) {
        case .loaded(let maskTexture):
            loadedMasks[layerID] = maskTexture
            message += "; \(label) OK \(maskURL.lastPathComponent) → \(maskTexture.width)×\(maskTexture.height)"
        case .unsupportedFormat(let ext):
            message += "; \(label) unsupported \(ext) (\(maskURL.lastPathComponent))"
        case .unsupportedTexFormat(let code):
            message += "; \(label) unsupported .tex format \(code) (\(maskURL.lastPathComponent))"
        case .texNoEmbeddedImage:
            message += "; \(label) has no embedded JPEG/PNG (\(maskURL.lastPathComponent))"
        case .texContainsVideoPayload:
            message += "; \(label) is mp4 payload (\(maskURL.lastPathComponent))"
        case .decodeFailed(let msg):
            message += "; \(label) decode failed (\(msg))"
        case .textureAllocationFailed(let w, let h):
            message += "; \(label) allocation failed at \(w)×\(h)"
        }
    }

    private func relativePath(for url: URL, cacheDirectory: URL) -> String {
        url.path.replacingOccurrences(of: cacheDirectory.path + "/", with: "")
    }
}
