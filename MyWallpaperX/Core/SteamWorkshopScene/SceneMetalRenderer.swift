import Metal
import QuartzCore
import simd

struct SceneMetalRendererDiagnostic {
    let imageLayerCount: Int
    let particleLayerCount: Int
    let textLayerCount: Int
    let containerLayerCount: Int
    let effectPassCount: Int
    let materialPassCount: Int
    let rendererGaps: [String]
}

struct SceneMetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderDescriptor: SceneRenderDescriptor
    private let gaussianBlurPipeline: SceneGaussianBlurPipeline

    // Cached scene-graph world frames for every layer. Frames are
    // translate+rotate+userScale (no size-scale baked in) so parents propagate
    // pivot/orientation without double-scaling child quads.
    private let worldFramesByLayerID: [Int: simd_float4x4]
    private let layersByID: [Int: SceneRenderDescriptor.Layer]

    init?(renderDescriptor: SceneRenderDescriptor) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let gaussianBlurPipeline = SceneGaussianBlurPipeline(device: device) else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.renderDescriptor = renderDescriptor
        self.gaussianBlurPipeline = gaussianBlurPipeline

        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        self.worldFramesByLayerID = Self.computeWorldFrames(
            layers: renderDescriptor.layers,
            byID: byID,
            sceneOrthoHeight: renderDescriptor.camera.orthoHeight
        )
    }

    func diagnostics() -> SceneMetalRendererDiagnostic {
        let layers = renderDescriptor.layers
        let imageCount = layers.filter { $0.contentKind == "image" }.count
        let particleCount = layers.filter { $0.contentKind == "particle" }.count
        let textCount = layers.filter { $0.contentKind == "text" }.count
        let containerCount = layers.filter { $0.contentKind == "container" }.count
        let effectPassCount = layers.flatMap(\.effects).flatMap(\.passes).count

        var gaps = renderDescriptor.firstStageRendererGaps
        if effectPassCount > 0 {
            gaps.append("effect shader execution (\(effectPassCount) passes)")
        }
        if renderDescriptor.materialPasses.contains(where: { $0.shaderPath != nil }) {
            gaps.append("material shader compilation")
        }
        return SceneMetalRendererDiagnostic(
            imageLayerCount: imageCount,
            particleLayerCount: particleCount,
            textLayerCount: textCount,
            containerLayerCount: containerCount,
            effectPassCount: effectPassCount,
            materialPassCount: renderDescriptor.materialPasses.count,
            rendererGaps: gaps
        )
    }

    // Single MTLClearColor matching the scene's clearcolor (premultiplied for
    // the framebuffer's alpha channel).
    var sceneClearColor: MTLClearColor {
        let c = renderDescriptor.camera.clearColor
        let r = Double(c.count > 0 ? c[0] : 0.7)
        let g = Double(c.count > 1 ? c[1] : 0.7)
        let b = Double(c.count > 2 ? c[2] : 0.7)
        return MTLClearColorMake(r, g, b, 1.0)
    }

    func offscreenPassCount(for layer: SceneRenderDescriptor.Layer) -> Int {
        SceneEffectRuntimePlanner.offscreenPassCount(for: layer)
    }

    func effectRuntimeSummary(for layer: SceneRenderDescriptor.Layer) -> String? {
        SceneEffectRuntimePlanner.runtimeSummary(for: layer)
    }

    func debugPlacementSummary(for layer: SceneRenderDescriptor.Layer) -> String {
        let origin = SIMD3<Float>(layer.originXYZ ?? [], fill: 0)
        let size = SIMD2<Float>(layer.sizeWH ?? [], fill: 0)
        let scale = SIMD3<Float>(layer.scaleXYZ ?? [], fill: 1)
        let angles = SIMD3<Float>(layer.anglesXYZ ?? [], fill: 0)
        let cropOffset = SIMD2<Float>(layer.modelCropOffsetXY ?? [], fill: 0)
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let worldCenter = world.columns.3
        return String(
            format: "parent=%@ localOrigin=(%.2f, %.2f, %.2f) worldCenter=(%.2f, %.2f, %.2f) size=(%.2f, %.2f) scale=(%.3f, %.3f, %.3f) angles=(%.3f, %.3f, %.3f) cropOffset=(%.2f, %.2f)",
            layer.parentID.map(String.init) ?? "nil",
            origin.x, origin.y, origin.z,
            worldCenter.x, worldCenter.y, worldCenter.z,
            size.x, size.y,
            scale.x, scale.y, scale.z,
            angles.x, angles.y, angles.z,
            cropOffset.x, cropOffset.y
        )
    }

    func renderClearPass(to drawable: CAMetalDrawable, clearColor: MTLClearColor? = nil) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor ?? sceneClearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Renders image layers in renderOrderLayerIDs order. Each layer uses its
    // own model matrix (origin/size/scale/angles with parent chain) and a
    // shared scene view+projection derived from the descriptor's camera.
    // Layers without a loaded texture or with visible=false are skipped.
    //
    // `time` is elapsed seconds since render start; it drives shader-side
    // effect approximations (foliagesway, waterwaves) keyed off the effect
    // names referenced by each layer's effectFiles.
    func renderFrame(
        imageTextures: [Int: MTLTexture],
        irisMaskTextures: [Int: MTLTexture],
        opacityMaskTextures: [Int: MTLTexture],
        waterMaskTextures: [Int: MTLTexture],
        foliageMaskTextures: [Int: MTLTexture],
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        time: Float,
        mouseNormalized: SIMD2<Float>,
        to drawable: CAMetalDrawable,
        viewportSize: CGSize
    ) {
        guard let pipeline = imagePipeline else {
            renderClearPass(to: drawable)
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let viewProj = makeViewProjection(viewportSize: viewportSize, mouseNormalized: mouseNormalized)
        let cursorWorld = cursorWorldPosition(mouseNormalized: mouseNormalized, viewportSize: viewportSize)
        let orderedLayers = renderDescriptor.renderOrderLayerIDs.compactMap { layersByID[$0] }

        var mainLoadAction: MTLLoadAction = .clear
        var mainEncoder: MTLRenderCommandEncoder?

        func ensureMainEncoder() -> MTLRenderCommandEncoder? {
            if let mainEncoder {
                return mainEncoder
            }
            mainEncoder = beginRenderEncoder(
                commandBuffer: commandBuffer,
                target: drawable.texture,
                loadAction: mainLoadAction,
                clearColor: sceneClearColor
            )
            mainLoadAction = .load
            if let mainEncoder {
                pipeline.bind(encoder: mainEncoder)
            }
            return mainEncoder
        }

        func closeMainEncoder() {
            mainEncoder?.endEncoding()
            mainEncoder = nil
        }

        for layer in orderedLayers where layer.contentKind == "image" {
            guard layer.visible != false else { continue }
            guard let texture = imageTextures[layer.id] else { continue }
            let irisMaskTexture = irisMaskTextures[layer.id]
            let opacityMaskTexture = opacityMaskTextures[layer.id]
            let waterMaskTexture = waterMaskTextures[layer.id]
            let foliageMaskTexture = foliageMaskTextures[layer.id]
            let auxMaskTexture = irisMaskTexture ?? opacityMaskTexture
            let effectPlan = SceneEffectRuntimePlanner.plan(
                for: layer,
                hasIrisMask: irisMaskTexture != nil,
                hasOpacityMask: opacityMaskTexture != nil && irisMaskTexture == nil,
                hasWaterMask: waterMaskTexture != nil,
                hasFoliageMask: foliageMaskTexture != nil
            )
            guard effectPlan.skipDirectRender == false else { continue }
            let effectInputs = effectPlan.inputs
            let model = modelMatrix(for: layer)
            let mvp = viewProj * model
            let directUniforms = SceneLayerFragmentUniforms(
                time: time,
                alpha: Float(layer.alpha ?? 1.0),
                effectFlags: effectInputs.flags.rawValue,
                _pad0: 0,
                cursorUV: cursorUV(for: layer, cursorWorld: cursorWorld),
                _pad1: .zero,
                effectParams0: effectInputs.params0,
                effectParams1: effectInputs.params1,
                effectParams2: effectInputs.params2,
                effectParams3: effectInputs.params3
            )

            let offscreenPassCount = effectPlan.offscreenPassCount
            if offscreenPassCount > 0,
               let offscreenTexturePool,
               let offscreenPair = offscreenTexturePool.textures(for: texture) {
                closeMainEncoder()
                let finalTexture = renderLayerOffscreen(
                    sourceTexture: texture,
                    waterMaskTexture: waterMaskTexture,
                    foliageMaskTexture: foliageMaskTexture,
                    auxMaskTexture: auxMaskTexture,
                    offscreenPair: offscreenPair,
                    offscreenPassCount: offscreenPassCount,
                    blurPlan: effectPlan.gaussianBlur,
                    sourceUniforms: directUniforms,
                    pipeline: pipeline,
                    commandBuffer: commandBuffer
                ) ?? texture
                guard let encoder = ensureMainEncoder() else { continue }
                pipeline.drawLayer(
                    texture: finalTexture,
                    shakeMaskTexture: nil,
                    waterMaskTexture: nil,
                    foliageMaskTexture: nil,
                    auxMaskTexture: nil,
                    mvp: mvp,
                    uniforms: Self.neutralUniforms(alpha: 1),
                    encoder: encoder
                )
                continue
            }

            guard let encoder = ensureMainEncoder() else { continue }
            pipeline.drawLayer(
                texture: texture,
                shakeMaskTexture: nil,
                waterMaskTexture: waterMaskTexture,
                foliageMaskTexture: foliageMaskTexture,
                auxMaskTexture: auxMaskTexture,
                mvp: mvp,
                uniforms: directUniforms,
                encoder: encoder
            )
        }

        if mainEncoder == nil {
            _ = ensureMainEncoder()
        }
        closeMainEncoder()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Maps the normalized mouse position to ortho-world coordinates so
    // per-layer UV transforms can position the cursorripple correctly.
    //
    // mouseNormalized is +Y-up (NSView coords), world is Y-down — subtract
    // the Y component instead of adding it so cursor's visual top matches
    // world's smaller-Y top.
    private func cursorWorldPosition(mouseNormalized: SIMD2<Float>, viewportSize: CGSize) -> SIMD2<Float> {
        let cam = renderDescriptor.camera
        let orthoW = cam.orthoWidth ?? Float(viewportSize.width)
        let orthoH = cam.orthoHeight ?? Float(viewportSize.height)
        return SIMD2(
            orthoW * 0.5 + mouseNormalized.x * orthoW * 0.5,
            orthoH * 0.5 - mouseNormalized.y * orthoH * 0.5
        )
    }

    // Layer-local UV for the cursor, ignoring rotation/parent transforms (good
    // enough for cursorripple's purely-decorative wave). Both world Y and
    // texture V grow downward, so no flip is needed.
    private func cursorUV(for layer: SceneRenderDescriptor.Layer, cursorWorld: SIMD2<Float>) -> SIMD2<Float> {
        let origin = SIMD3<Float>(layer.originXYZ ?? [], fill: 0)
        let size = SIMD2<Float>(layer.sizeWH ?? [], fill: 0)
        guard size.x > 0, size.y > 0 else { return .zero }
        let u = (cursorWorld.x - (origin.x - size.x / 2)) / size.x
        let v = (cursorWorld.y - (origin.y - size.y / 2)) / size.y
        return SIMD2(u, v)
    }

    // Resolves which inline effect approximations apply to a layer by
    // matching directory names in its `effectFiles` (e.g. "effects/foliagesway/
    // effect.json"). This is a stand-in for a real effect runtime — only the
    // effects we have hand-written shader paths for are honored; everything
    // else is silently ignored at this stage.
    private func renderLayerOffscreen(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        offscreenPair: SceneOffscreenTexturePool.Pair,
        offscreenPassCount: Int,
        blurPlan: SceneGaussianBlurPlan?,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let sourceEncoder = beginRenderEncoder(
            commandBuffer: commandBuffer,
            target: offscreenPair.primary,
            loadAction: .clear,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        ) else {
            return nil
        }
        pipeline.bind(encoder: sourceEncoder)
        pipeline.drawLayer(
            texture: sourceTexture,
            shakeMaskTexture: nil,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            mvp: Self.fullTargetMVP,
            uniforms: sourceUniforms,
            encoder: sourceEncoder
        )
        sourceEncoder.endEncoding()

        if let blurPlan {
            guard gaussianBlurPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                step: SIMD2(blurPlan.horizontalStep, 0),
                commandBuffer: commandBuffer
            ), gaussianBlurPipeline.encode(
                source: offscreenPair.secondary,
                target: offscreenPair.primary,
                step: SIMD2(0, blurPlan.verticalStep),
                commandBuffer: commandBuffer
            ) else {
                return offscreenPair.primary
            }
            return offscreenPair.primary
        }

        guard offscreenPassCount > 1,
              let effectEncoder = beginRenderEncoder(
                commandBuffer: commandBuffer,
                target: offscreenPair.secondary,
                loadAction: .clear,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
              ) else {
            return offscreenPair.primary
        }

        // Keep exactly one ping-pong hop alive for now so blur/bloom-style
        // layers already exercise the offscreen route without pretending the
        // actual per-pass shader math exists yet.
        pipeline.bind(encoder: effectEncoder)
        pipeline.drawLayer(
            texture: offscreenPair.primary,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: Self.fullTargetMVP,
            uniforms: Self.neutralUniforms(alpha: 1),
            encoder: effectEncoder
        )
        effectEncoder.endEncoding()
        return offscreenPair.secondary
    }

    private func beginRenderEncoder(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        loadAction: MTLLoadAction,
        clearColor: MTLClearColor
    ) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = loadAction
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].storeAction = .store
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))

    private static func neutralUniforms(alpha: Float) -> SceneLayerFragmentUniforms {
        SceneLayerFragmentUniforms(
            time: 0,
            alpha: alpha,
            effectFlags: 0,
            _pad0: 0,
            cursorUV: .zero,
            _pad1: .zero,
            effectParams0: .zero,
            effectParams1: .zero,
            effectParams2: .zero,
            effectParams3: .zero
        )
    }

    // MARK: - Matrix construction

    // Computes the view * projection matrix from the scene camera, applying a
    // "fit" (letterbox) aspect to the drawable so the entire ortho box is
    // visible regardless of the viewport's aspect ratio.
    //
    // Coordinate convention (inferred from samples):
    // - World origin is the bottom-left corner of the scene; main image
    //   layers have origin=(orthoW/2, orthoH/2) and size=(orthoW, orthoH).
    // - scene.json's camera.eye/center are relative to the *scene center*
    //   ((orthoW/2, orthoH/2)), not the raw world origin. So default
    //   eye=(0,0,0) places the camera at the scene center looking down -Z.
    private func makeViewProjection(viewportSize: CGSize, mouseNormalized: SIMD2<Float>) -> simd_float4x4 {
        let camera = renderDescriptor.camera
        let orthoW = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoH = camera.orthoHeight ?? Float(viewportSize.height)
        guard orthoW > 0, orthoH > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return SceneMatrix.identity()
        }

        // Place the camera at z=cameraDepth (+Z) above the layer plane so
        // layers at world z=0 fall comfortably within the [-near, -far]
        // view-space range and are not near-clipped. cameraDepth is arbitrary
        // (ortho doesn't change size with depth) but must be > near.
        let cameraDepth: Float = max(1, camera.nearZ * 10)
        let sceneCenter = SIMD3<Float>(orthoW / 2, orthoH / 2, cameraDepth)
        let eyeOffset = SIMD3<Float>(camera.eye, fill: 0)
        let centerOffset = SIMD3<Float>(camera.center, fill: 0)
        let upDir = SIMD3<Float>(camera.up, fill: 0)
        // Camera parallax: small lateral camera offset following the cursor.
        // 4% of the ortho box is a subtle, non-disorienting amount; we always
        // apply it (regardless of scene general.cameraparallax flag) so the
        // preview gives obvious "alive" feedback when the user moves the mouse.
        let parallaxScale: Float = 0.04
        let parallaxOffset = SIMD3<Float>(
            mouseNormalized.x * orthoW * parallaxScale,
            mouseNormalized.y * orthoH * parallaxScale,
            0
        )
        let eye = sceneCenter + eyeOffset + parallaxOffset
        let center = sceneCenter + centerOffset + parallaxOffset
        let view = SceneMatrix.lookAt(eye: eye, center: center, up: upDir)

        let drawableAspect = Float(viewportSize.width / viewportSize.height)
        let sceneAspect = orthoW / orthoH

        var halfW = orthoW / 2
        var halfH = orthoH / 2
        if drawableAspect > sceneAspect {
            // Viewport is wider than the scene: expand horizontally for letterbox.
            halfW = halfH * drawableAspect
        } else {
            halfH = halfW / drawableAspect
        }

        // World is Y-down (see modelMatrix comment) so swap ortho top/bottom
        // to flip the Y axis on its way to Metal's Y-up NDC. The net effect:
        // world (0, 0) (top-left of the ortho box) lands at NDC (-1, +1)
        // (top-left of the drawable).
        let proj = SceneMatrix.ortho(
            left: -halfW, right: halfW,
            bottom: halfH, top: -halfH,
            near: camera.nearZ, far: camera.farZ
        )
        return proj * view
    }

    private func modelMatrix(for layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
        let size = SIMD2(layer.sizeWH ?? [], fill: 0)
        // Wallpaper Engine world coords are Y-down (origin at the ortho box's
        // top-left, +Y grows downward). Our quad is Y-up (+0.5 at the visual
        // top), so negate the Y size to map the quad's +Y vertex to the
        // smaller world-Y (visually upper) edge of the layer.
        let sizeScale = SceneMatrix.scale(SIMD3(size.x, -size.y, 1))
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        return world * sizeScale
    }

    // World frame = compose translate+rotate+userScale up the parent chain.
    // Scene object origins behave as bottom-left/world Y-up for root objects,
    // while parented child offsets are authored relative to that same axis in
    // local space. Convert roots with (sceneH - y), convert child local
    // offsets with (-y), and mirror Z rotation direction to preserve the
    // authored clockwise/counter-clockwise placement once everything lands in
    // the renderer's Y-down world.
    // Size is intentionally NOT baked in here so children inherit a parent's
    // pivot/orientation/scale without double-scaling their own quad.
    private static func computeWorldFrames(
        layers: [SceneRenderDescriptor.Layer],
        byID: [Int: SceneRenderDescriptor.Layer],
        sceneOrthoHeight: Float?
    ) -> [Int: simd_float4x4] {
        var cache: [Int: simd_float4x4] = [:]

        func localFrame(_ layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
            var origin = SIMD3(layer.originXYZ ?? [], fill: 0)
            let scale = SIMD3(layer.scaleXYZ ?? [], fill: 1)
            var angles = SIMD3(layer.anglesXYZ ?? [], fill: 0)
            if layer.parentID == nil {
                if let sceneOrthoHeight, sceneOrthoHeight > 0 {
                    origin.y = sceneOrthoHeight - origin.y
                }
            } else {
                origin.y = -origin.y
            }
            angles.z = -angles.z
            let t = SceneMatrix.translation(origin)
            let r = SceneMatrix.eulerXYZ(angles)
            let s = SceneMatrix.scale(scale)
            return t * r * s
        }

        func resolve(_ layer: SceneRenderDescriptor.Layer, visiting: Set<Int>) -> simd_float4x4 {
            if let cached = cache[layer.id] { return cached }
            var nextVisiting = visiting
            nextVisiting.insert(layer.id)
            let local = localFrame(layer)
            let world: simd_float4x4
            if let parentID = layer.parentID,
               !visiting.contains(parentID),
               let parent = byID[parentID] {
                world = resolve(parent, visiting: nextVisiting) * local
            } else {
                world = local
            }
            cache[layer.id] = world
            return world
        }

        for layer in layers {
            _ = resolve(layer, visiting: [])
        }
        return cache
    }
}
