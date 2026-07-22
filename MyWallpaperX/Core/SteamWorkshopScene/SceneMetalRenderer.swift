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
    private let utilityPlansByLayerID: [Int: SceneUtilityLayerRuntimePlan]
    private let dependencyRuntime: SceneDependencyFrameRuntime
    private let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
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
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: renderDescriptor)
        self.visibleLayerIDs = visibleLayerIDs
        self.dependencyRuntime = SceneDependencyFrameRuntime(
            plan: SceneDependencyRenderPlan(
                descriptor: renderDescriptor,
                visibleLayerIDs: visibleLayerIDs
            ),
            device: device
        )

        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        self.utilityPlansByLayerID = SceneUtilityLayerRuntimePlanner.plans(in: renderDescriptor)
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
        let imageCount = layers.filter(\.isImageRenderable).count
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
        hasOpacityMask: Bool = false,
        hasWaterMask: Bool = false,
        hasFoliageMask: Bool = false
    ) -> String? {
        SceneEffectRuntimePlanner.runtimeSummary(
            for: layer,
            hasWaterRippleNormal: hasWaterRippleNormal,
            hasOpacityMask: hasOpacityMask,
            hasWaterMask: hasWaterMask,
            hasFoliageMask: hasFoliageMask
        )
    }

    func debugPlacementSummary(for layer: SceneRenderDescriptor.Layer) -> String {
        SceneLayerPlacementSummary.make(
            layer: layer,
            worldFrame: worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
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
        foliageMaskUVScales: [Int: SIMD2<Float>],
        waterRippleNormalTextures: [Int: MTLTexture],
        imagePipeline: SceneImageLayerPipeline?,
        particleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        time: Float,
        mouseNormalized: SIMD2<Float>,
        parallaxMouseNormalized: SIMD2<Float>,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
        to drawable: CAMetalDrawable,
        viewportSize: CGSize
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let cameraFrame = SceneParticleCameraFrame(
            camera: renderDescriptor.camera,
            viewportSize: viewportSize
        )
        let cursorWorld = SceneLayerCursorGeometry.worldPosition(
            camera: renderDescriptor.camera,
            mouseNormalized: mouseNormalized,
            viewportSize: viewportSize
        )
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

        dependencyRuntime.beginFrame()
        for layer in orderedLayers {
            if let imagePipeline, dependencyRuntime.requiresCapture(for: layer.id) {
                let providerModel = imageModelMatrix(
                    for: layer,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                _ = dependencyRuntime.captureProviderIfRequired(
                    layer: layer,
                    layerMVP: cameraFrame.orthographicViewProjection * providerModel,
                    viewportSize: viewportSize,
                    pipeline: imagePipeline,
                    mainPass: mainPass
                )
            }
            guard visibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let texture = imageTextures[layer.id] else { continue }
                let dependencyEffect = dependencyRuntime.effectInput(for: layer.id)
                if dependencyRuntime.requiresEffect(for: layer.id), dependencyEffect == nil {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    continue
                }
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
                        foliageUVScale: foliageMaskUVScales[layer.id]
                            ?? SIMD2(repeating: 1),
                        waterRippleNormal: waterRippleNormalTextures[layer.id]
                    ),
                    textureFrame: spriteAnimations[layer.id]?.transform(at: time) ?? .identity,
                    mvp: cameraFrame.orthographicViewProjection * model,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: Float(layer.alpha ?? 1),
                        cursorUV: SceneLayerCursorGeometry.layerUV(
                            for: layer,
                            cursorWorld: cursorWorld
                        )
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: dependencyEffect
                )
                let encoded = imageCompositor.draw(request, pipeline: imagePipeline, mainPass: mainPass)
                dependencyRuntime.recordBindingIfRequired(
                    for: layer.id,
                    encoded: encoded,
                    on: commandBuffer
                )
            case "composition", "project", "fullscreen":
                guard let imagePipeline, let offscreenTexturePool,
                      let plan = utilityPlansByLayerID[layer.id], plan.shouldCapture else { continue }
                let model = imageModelMatrix(
                    for: layer,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                let captured = SceneUtilityLayerRenderer.draw(
                    layer: layer, plan: plan,
                    layerMVP: cameraFrame.orthographicViewProjection * model,
                    viewportSize: viewportSize, time: time,
                    pipeline: imagePipeline, compositor: imageCompositor,
                    offscreenTexturePool: offscreenTexturePool, mainPass: mainPass
                )
                utilityCaptureTelemetry.record(layerID: layer.id, encoded: captured, on: commandBuffer)
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
        encodeFrameReadback?(drawable.texture, commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Matrix construction

    private func imageModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4 {
        let size = SIMD2(layer.renderSizeWH ?? [], fill: 0)
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
