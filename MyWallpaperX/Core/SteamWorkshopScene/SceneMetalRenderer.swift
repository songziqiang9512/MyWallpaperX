import Metal
import QuartzCore
import simd

struct SceneMetalRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderDescriptor: SceneRenderDescriptor
    private let imageCompositor: SceneImageLayerCompositor
    private let visibleLayerIDs: Set<Int>
    // Cached transforms propagate parent pivot/orientation without double-scaling child quads.
    private let worldFramesByLayerID: [Int: simd_float4x4]
    private let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
    private let layersByID: [Int: SceneRenderDescriptor.Layer]
    init?(renderDescriptor: SceneRenderDescriptor) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let imageCompositor = SceneImageLayerCompositor(device: device) else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.renderDescriptor = renderDescriptor
        self.imageCompositor = imageCompositor
        self.visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: renderDescriptor)

        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        self.worldFramesByLayerID = SceneLayerWorldFrameResolver.compute(
            layers: renderDescriptor.layers,
            byID: byID,
            sceneOrthoHeight: renderDescriptor.camera.orthoHeight
        )
        let parallaxNodes = byID.mapValues { layer in
            SceneLayerParallax.Node(
                id: layer.id, parentID: layer.parentID,
                depth: SIMD2(layer.parallaxDepthXY ?? [], fill: 0),
                propagatesToChildren: !layer.disablesParallaxPropagation
            )
        }
        self.parallaxByLayerID = Dictionary(uniqueKeysWithValues: byID.keys.compactMap { id in
            SceneLayerParallax.resolve(layerID: id, nodesByID: parallaxNodes).map { (id, $0) }
        })
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

    func effectRuntimeSummary(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterRippleNormal: Bool = false,
        hasOpacityMask: Bool = false
    ) -> String? {
        SceneEffectRuntimePlanner.runtimeSummary(
            for: layer,
            hasWaterRippleNormal: hasWaterRippleNormal,
            hasOpacityMask: hasOpacityMask
        )
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
        spriteAnimations: [Int: SceneSpriteAnimation],
        irisMaskTextures: [Int: MTLTexture],
        opacityMaskTextures: [Int: MTLTexture],
        waterMaskTextures: [Int: MTLTexture],
        foliageMaskTextures: [Int: MTLTexture],
        waterRippleNormalTextures: [Int: MTLTexture],
        imagePipeline: SceneImageLayerPipeline?,
        particleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        time: Float,
        mouseNormalized: SIMD2<Float>,
        parallaxMouseNormalized: SIMD2<Float>,
        to drawable: CAMetalDrawable,
        viewportSize: CGSize
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let cameraFrame = SceneParticleCameraFrame(
            camera: renderDescriptor.camera,
            viewportSize: viewportSize
        )
        let cursorWorld = cursorWorldPosition(mouseNormalized: mouseNormalized, viewportSize: viewportSize)
        let camera = renderDescriptor.camera
        let parallaxConfiguration = SceneLayerParallax.Configuration(
            enabled: camera.parallaxEnabled, amount: camera.parallaxAmount,
            mouseInfluence: camera.parallaxMouseInfluence,
            orthoSize: SIMD2(
                camera.orthoWidth ?? Float(viewportSize.width),
                camera.orthoHeight ?? Float(viewportSize.height)
            ),
            cameraEyeOffset: SIMD2(camera.eye, fill: 0)
        )
        let orderedLayers = renderDescriptor.renderOrderLayerIDs.compactMap { layersByID[$0] }
        let particleBatchesByID = Dictionary(
            uniqueKeysWithValues: particleBatches.map { ($0.layerID, $0) }
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: drawable.texture,
            clearColor: sceneClearColor
        )

        for layer in orderedLayers {
            guard visibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "text":
                guard let imagePipeline, let texture = imageTextures[layer.id] else { continue }
                let model = imageModelMatrix(
                    for: layer,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    masks: SceneImageLayerMasks(
                        iris: irisMaskTextures[layer.id],
                        opacity: opacityMaskTextures[layer.id],
                        water: waterMaskTextures[layer.id],
                        foliage: foliageMaskTextures[layer.id],
                        waterRippleNormal: waterRippleNormalTextures[layer.id]
                    ),
                    textureFrame: spriteAnimations[layer.id]?.transform(at: time) ?? .identity,
                    mvp: cameraFrame.orthographicViewProjection * model,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: Float(layer.alpha ?? 1),
                        cursorUV: cursorUV(for: layer, cursorWorld: cursorWorld)
                    ),
                    offscreenTexturePool: offscreenTexturePool
                )
                imageCompositor.draw(request, pipeline: imagePipeline, mainPass: mainPass)
            case "particle":
                guard let particlePipeline,
                      let batch = particleBatchesByID[layer.id],
                      let encoder = mainPass.encoder() else { continue }
                let model = particleModelMatrix(
                    for: layer,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                let basis = particleBasis(for: batch, layerModel: model, cameraFrame: cameraFrame)
                particlePipeline.draw(
                    texture: batch.texture,
                    instances: batch.instanceBuffer,
                    uniforms: SceneParticleLayerUniforms(
                        viewProjection: cameraFrame.viewProjection(
                            usesPerspective: batch.usesPerspective
                        ),
                        layerModel: model,
                        basis: basis
                    ),
                    blendMode: batch.blendMode,
                    encoder: encoder
                )
                batch.instanceBuffer.markSubmitted(on: commandBuffer)
            default:
                continue
            }
        }

        mainPass.finishEnsuringClear()
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

    // MARK: - Matrix construction

    private func imageModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4 {
        let size = SIMD2(layer.sizeWH ?? [], fill: 0)
        // Wallpaper Engine world coords are Y-down (origin at the ortho box's
        // top-left, +Y grows downward). Our quad is Y-up (+0.5 at the visual
        // top), so negate the Y size to map the quad's +Y vertex to the
        // smaller world-Y (visually upper) edge of the layer.
        let sizeScale = SceneMatrix.scale(SIMD3(size.x, -size.y, 1))
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFrame: world,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneMatrix.translation(SIMD3(parallax.x, parallax.y, 0)) * world * sizeScale
    }

    private func particleModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4 {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFrame: world,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneParticleCameraFrame.particleLayerModel(
            worldFrame: world,
            parallaxOffset: parallax
        )
    }

    private func parallaxOffset(
        for layer: SceneRenderDescriptor.Layer,
        worldFrame: simd_float4x4,
        mouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> SIMD2<Float> {
        SceneLayerParallax.offset(
            resolution: parallaxByLayerID[layer.id],
            configuration: configuration,
            layerPosition: SIMD2(worldFrame.columns.3.x, worldFrame.columns.3.y),
            mouseNormalized: mouseNormalized
        )
    }

    private func particleBasis(
        for batch: SceneParticleDrawBatch,
        layerModel: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame
    ) -> SceneParticleOrientationBasis {
        guard batch.orientation == .fixed else {
            return cameraFrame.basis(for: batch.orientation)
        }
        let rawAxis = batch.orientationAxis ?? SIMD3<Float>(0, 0, 1)
        let axisLength = simd_length_squared(rawAxis)
        let normal = axisLength.isFinite && axisLength > 1e-8
            ? rawAxis / sqrt(axisLength)
            : SIMD3<Float>(0, 0, 1)
        let reference = abs(normal.y) < 0.999 ? SIMD3<Float>(0, 1, 0) : SIMD3(1, 0, 0)
        let localRight = simd_normalize(simd_cross(reference, normal))
        let localUp = simd_normalize(simd_cross(normal, localRight))
        let transformedRight = layerModel * SIMD4(localRight.x, localRight.y, localRight.z, 0)
        let transformedUp = layerModel * SIMD4(localUp.x, localUp.y, localUp.z, 0)
        let fixedRight = SIMD3(transformedRight.x, transformedRight.y, transformedRight.z)
        let fixedUp = SIMD3(transformedUp.x, transformedUp.y, transformedUp.z)
        return cameraFrame.basis(
            for: batch.orientation,
            fixedRight: fixedRight,
            fixedUp: fixedUp
        )
    }
}
