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
    let worldFramesByLayerID: [Int: simd_float4x4]
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
    private let layersByID: [Int: SceneRenderDescriptor.Layer]
    private let utilityPlansByTriggerLayerID: [Int: [SceneUtilityLayerRuntimePlan]]
    private let authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    private let dependencyRuntime: SceneDependencyFrameRuntime
    private let textureRegistry = SceneFrameTextureRegistry()
    private let utilityCaptureTelemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
    private let authoredEffectTelemetry = SceneGPUCompletionTelemetry(phase: "authored-effect-graph")
    init?(
        renderDescriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) {
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
        self.authoredEffectCatalog = authoredEffectCatalog
        self.dependencyRuntime = SceneDependencyFrameRuntime(
            descriptor: renderDescriptor,
            visibleLayerIDs: visibleLayerIDs,
            device: device
        )

        let byID = Dictionary(uniqueKeysWithValues: renderDescriptor.layers.map { ($0.id, $0) })
        self.layersByID = byID
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog
        )
        self.utilityPlansByTriggerLayerID = Dictionary(
            grouping: utilityPlans.values.filter(\.shouldCapture),
            by: \.triggerLayerID
        )
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

    var sceneClearColor: MTLClearColor {
        let c = renderDescriptor.camera.clearColor
        let r = Double(c.count > 0 ? c[0] : 0.7)
        let g = Double(c.count > 1 ? c[1] : 0.7)
        let b = Double(c.count > 2 ? c[2] : 0.7)
        return MTLClearColorMake(r, g, b, 1.0)
    }

    func authoredEffectRuntimeReportLines() -> [String] {
        authoredEffectCatalog.reportLines
    }

    func utilityRuntimeReportLines() -> [String] {
        SceneUtilityLayerRuntimePlanner.reportLines(
            descriptor: renderDescriptor,
            authoredEffectCatalog: authoredEffectCatalog
        )
    }

    func authoredEffectPlan(for layerID: Int) -> SceneAuthoredEffectExecutionPlan? {
        authoredEffectCatalog.plansByLayerID[layerID]
    }

    func authoredEffectChain(for layerID: Int) -> SceneAuthoredEffectExecutionChain? {
        authoredEffectCatalog.chainsByLayerID[layerID]
    }

    func blocksLegacyGaussianBlur(for layerID: Int) -> Bool {
        authoredEffectCatalog.legacyGaussianBlurBlockedLayerIDs.contains(layerID)
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

    func renderFrame(
        imageTextures: [Int: MTLTexture],
        userPropertyTextures: [String: MTLTexture] = [:],
        spriteAnimations: [Int: SceneSpriteAnimation],
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline?,
        particleBatches: [SceneParticleDrawBatch],
        particlePipeline: SceneParticleMetalPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        encodeFrameReadback: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
        to drawable: CAMetalDrawable
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let viewportSize = frameContext.screenSize
        let time = Float(frameContext.sceneTime)
        let parallaxMouseNormalized = frameContext.cameraParallaxPosition
        let cameraFrame = SceneParticleCameraFrame(
            camera: renderDescriptor.camera,
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

        textureRegistry.beginFrame(
            layerSources: imageTextures,
            userPropertyTextures: userPropertyTextures
        )
        for layer in orderedLayers {
            defer {
                renderUtilityPlans(
                    triggeredBy: layer.id,
                    effectTextures: effectTextures,
                    imagePipeline: imagePipeline,
                    offscreenTexturePool: offscreenTexturePool,
                    frameContext: frameContext,
                    cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration,
                    viewportSize: viewportSize,
                    time: time,
                    mainPass: mainPass,
                    commandBuffer: commandBuffer
                )
            }
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
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
                )
            }
            guard visibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let texture = imageTextures[layer.id] else { continue }
                let dependencyEffect = dependencyRuntime.effectInput(
                    for: layer.id,
                    textureRegistry: textureRegistry
                )
                let authoredEffectChain = authoredEffectChain(for: layer.id)
                let authoredEffectPlan = authoredEffectChain?.singleStage
                if dependencyRuntime.requiresEffect(for: layer.id), dependencyEffect == nil {
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    continue
                }
                let preparedTexture = dependencyRuntime.preparedSourceTexture(
                    for: layer.id,
                    sourceTexture: texture,
                    textureRegistry: textureRegistry,
                    mainPass: mainPass
                )
                let layerAlpha = SceneDynamicLayerValues.alpha(
                    layerID: layer.id, authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                )
                let model = imageModelMatrix(
                    for: layer,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                let mvp = cameraFrame.orthographicViewProjection * model
                let cursorUV = SceneLayerCursorGeometry.layerUV(
                    mouseNormalized: frameContext.pointer.current,
                    modelViewProjection: mvp
                )
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: preparedTexture,
                    masks: SceneImageLayerMasks(
                        iris: effectTextures.irisMasks[layer.id],
                        opacity: effectTextures.opacityMasks[layer.id],
                        water: effectTextures.waterMasks[layer.id],
                        waterUVScale: effectTextures.waterUVScales[layer.id]
                            ?? SIMD2(repeating: 1),
                        foliage: effectTextures.foliageMasks[layer.id],
                        foliageUVScale: effectTextures.foliageUVScales[layer.id]
                            ?? SIMD2(repeating: 1),
                        waterRippleNormal: effectTextures.waterRippleNormals[layer.id],
                        shakeEffects: effectTextures.shakeEffects,
                        waterFlowEffects: effectTextures.waterFlowEffects,
                        waterWavesEffects: effectTextures.waterWavesEffects,
                        xRay: effectTextures.xRayEffects[layer.id]
                    ),
                    textureFrame: spriteAnimations[layer.id]?.transform(at: time) ?? .identity,
                    mvp: mvp,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: layerAlpha,
                        cursorUV: cursorUV ?? .zero,
                        cursorIsInside: frameContext.pointer.isInside && cursorUV != nil,
                        primaryButtonIsDown: frameContext.pointer.isPrimaryButtonDown,
                        tint: SceneDynamicLayerValues.color(
                            layerID: layer.id, authoredValue: layer.colorRGB,
                            snapshot: frameContext.dynamicValues
                        )
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: dependencyEffect,
                    authoredEffectPlan: authoredEffectPlan,
                    blocksLegacyGaussianBlur: blocksLegacyGaussianBlur(for: layer.id),
                    authoredEffectChain: authoredEffectChain,
                    dynamicValues: frameContext.dynamicValues
                )
                let encoded = imageCompositor.draw(request, pipeline: imagePipeline, mainPass: mainPass)
                if authoredEffectChain != nil {
                    authoredEffectTelemetry.record(layerID: layer.id, encoded: encoded, on: commandBuffer)
                }
                dependencyRuntime.recordBindingIfRequired(
                    for: layer.id,
                    encoded: encoded,
                    on: commandBuffer
                )
            case "composition", "project", "fullscreen":
                break
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

    private func renderUtilityPlans(
        triggeredBy layerID: Int,
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let plans = utilityPlansByTriggerLayerID[layerID],
              let imagePipeline,
              let offscreenTexturePool else {
            return
        }
        for plan in plans {
            guard let layer = layersByID[plan.layerID] else { continue }
            let model = imageModelMatrix(
                for: layer,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration
            )
            let mvp = cameraFrame.orthographicViewProjection * model
            let cursorUV = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: mvp
            )
            let authoredEffectChain = authoredEffectChain(for: layer.id)
            let captured = SceneUtilityLayerRenderer.draw(
                layer: layer,
                plan: plan,
                layerMVP: mvp,
                viewportSize: viewportSize,
                time: time,
                finalCompositeAlpha: SceneDynamicLayerValues.alpha(
                    layerID: layer.id,
                    authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                ),
                masks: .xRayOnly(effectTextures.xRayEffects[layer.id]),
                cursorUV: cursorUV ?? .zero,
                pointerIsInside: frameContext.pointer.isInside && cursorUV != nil,
                authoredEffectChain: authoredEffectChain,
                dynamicValues: frameContext.dynamicValues,
                blocksLegacyGaussianBlur: blocksLegacyGaussianBlur(for: layer.id),
                pipeline: imagePipeline,
                compositor: imageCompositor,
                offscreenTexturePool: offscreenTexturePool,
                mainPass: mainPass
            )
            utilityCaptureTelemetry.record(
                layerID: layer.id,
                encoded: captured,
                on: commandBuffer
            )
            if authoredEffectChain != nil {
                authoredEffectTelemetry.record(
                    layerID: layer.id,
                    encoded: captured,
                    on: commandBuffer
                )
            }
        }
    }

}
