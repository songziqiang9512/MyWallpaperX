import Metal
import simd

struct SceneImageLayerCompositor {
    private let authoredEffectPipelines: SceneAuthoredEffectPipelineSet
    private let pipelineRepository: SceneImageEffectPipelineRepository
    private let colorBlendPipelineSlot: ScenePipelineSlot<SceneLayerColorBlendPipeline>

    init?(device: MTLDevice) {
        self.init(pipelineRepository: SceneImageEffectPipelineRepository(device: device))
    }

    init(pipelineRepository: SceneImageEffectPipelineRepository) {
        self.pipelineRepository = pipelineRepository
        authoredEffectPipelines = .init(repository: pipelineRepository)
        let device = pipelineRepository.device
        colorBlendPipelineSlot = .init {
            SceneLayerColorBlendPipeline(device: device)
        }
    }

    @discardableResult
    func draw(
        _ request: SceneImageLayerDrawRequest,
        pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace? = nil,
        executionOrigin: SceneEffectExecutionOrigin = .image
    ) -> Bool {
        guard (request.dependencyEffect.map {
            ($0.slotIndex == 1 && ($0.blendMode == 0 || $0.blendMode == 5))
                || ($0.slotIndex == 3 && $0.blendMode == 0)
        } ?? true) else { return false }
        let masks = request.masks
        let layerColorBlendMode = request.layer.colorBlendMode ?? 0
        guard SceneLayerColorBlendRenderer.supports(layerColorBlendMode) else { return false }
        let colorBlendPipeline = layerColorBlendMode == 0
            ? nil
            : colorBlendPipelineSlot.resolve()
        guard layerColorBlendMode == 0 || colorBlendPipeline != nil else { return false }
        let auxMask = masks.iris ?? masks.opacity
        let runtimeAuthoredPlan = request.authoredEffectPlan
            ?? request.authoredEffectChain?.singleStage
        let usesAuthoredExecution = request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil
        let legacyDecision = usesAuthoredExecution ? nil
            : SceneEffectRuntimePlanner.legacyPlanningDecision(
                for: request.layer,
                resources: SceneLegacyEffectResourceAvailability(
                    hasIrisMask: masks.iris != nil,
                    hasOpacityMask: masks.opacity != nil,
                    hasWaterMask: masks.water != nil,
                    hasFoliageMask: masks.foliage != nil,
                    hasWaterRippleNormal: masks.waterRippleNormal != nil
                ),
                blocksLegacyGaussianBlur: request.blocksLegacyGaussianBlur
            )
        let effectPlan = legacyDecision?.runtimePlan ?? SceneEffectRuntimePlanner.plan(
            for: request.layer,
            hasIrisMask: masks.iris != nil,
            hasOpacityMask: masks.opacity != nil && masks.iris == nil,
            hasWaterMask: masks.water != nil,
            hasFoliageMask: masks.foliage != nil,
            hasWaterRippleNormal: masks.waterRippleNormal != nil,
            authoredEffectPlan: runtimeAuthoredPlan,
            blocksLegacyGaussianBlur: request.blocksLegacyGaussianBlur
        )
        guard request.authoredEffectChain != nil
            || effectPlan.skipsUnsupportedComposite == false else {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "legacy-composite-admission",
                outcome: .failed(reasonCode: "unsupported-composite")
            )
            return false
        }
        let routesOffscreen = effectPlan.offscreenPassCount > 0
            || request.requiresSourceCopy
            || request.authoredEffectChain != nil
            || layerColorBlendMode > 0
        guard !routesOffscreen
            || request.layer.contentKind != "solid"
            || request.offscreenSize != nil else {
            return false
        }
        let requestedOffscreenSize = request.resolvedOffscreenSize
        let requestedOffscreenWidth = max(
            1,
            Int((requestedOffscreenSize?.width ?? CGFloat(request.texture.width)).rounded(.up))
        )
        let requestedOffscreenHeight = max(
            1,
            Int((requestedOffscreenSize?.height ?? CGFloat(request.texture.height)).rounded(.up))
        )
        let chainConsumesDependency =
            request.authoredEffectChain != nil && request.dependencyEffect != nil

        let sourceEffectInputs = request.authoredEffectChain == nil
            ? effectPlan.inputs
            : .neutral
        guard let sourceTextureFrame = request.resolvedBaseTextureFrame() else {
            return false
        }
        // 作者 `brightness` 是 layer 颜色乘数（随包 wave layer 用 3.0/4.0 做过曝发光），
        // 超过 1 的部分由 render target 精度裁剪。`contentKind == "text"` 的 layer 纹理来自
        // CoreText 栅格化，那一步已经乘过同一个 key（见 SceneTextTextureLoader），这里必须跳过。
        let brightness = request.layer.contentKind == "text"
            ? 1
            : max(0, Float(request.layer.brightness ?? 1))
        let usesAuthoredColor = request.layer.contentKind == "image" || request.layer.contentKind == "solid"
        let baseTint = usesAuthoredColor ? request.uniforms.tint : SIMD3<Float>(repeating: 1)
        let directUniforms = makeFragmentUniforms(
            values: request.uniforms,
            effectInputs: sourceEffectInputs,
            textureFrame: sourceTextureFrame,
            tint: baseTint * brightness,
            foliageMaskUVScale: masks.foliageUVScale,
            dependencyBlendMode: routesOffscreen ? nil : request.dependencyEffect?.blendMode
        )
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            var renderedTexture: MTLTexture?
            if let authoredChain = request.authoredEffectChain {
                guard let targets = pool.graphTargets(
                    for: authoredChain,
                    requestedWidth: requestedOffscreenWidth,
                    requestedHeight: requestedOffscreenHeight
                ) else {
                    executionTrace?.recordRouteOperation(
                        layerID: request.layer.id,
                        origin: executionOrigin,
                        operation: "authored-target-allocation",
                        outcome: .failed(reasonCode: "graph-targets-unavailable")
                    )
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneAuthoredEffectChainRenderer.render(
                        sourceTexture: request.texture,
                        masks: masks,
                        targets: targets,
                        chain: authoredChain,
                        dynamicValues: request.dynamicValues,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        pipelines: authoredEffectPipelines,
                        cursorUV: request.uniforms.cursorUV,
                        previousCursorUV: request.uniforms.previousCursorUV,
                        pointerIsInside: request.uniforms.cursorIsInside,
                        previousPointerIsInside: request.uniforms.previousCursorIsInside,
                        frameTime: request.uniforms.frameTime,
                        audioSpectrum: request.audioSpectrum,
                        authoredShaderFrameInputs: request.authoredShaderFrameInputs,
                        dependencyEffect: request.dependencyEffect,
                        commandBuffer: commandBuffer,
                        executionTrace: executionTrace,
                        executionOrigin: executionOrigin
                    )
                }
            } else if let authoredPlan = request.authoredEffectPlan {
                guard let targets = pool.graphTargets(
                    for: authoredPlan,
                    requestedWidth: requestedOffscreenWidth,
                    requestedHeight: requestedOffscreenHeight
                ) else {
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer -> MTLTexture? in
                    SceneStandaloneAuthoredEffectRenderer.render(
                        plan: authoredPlan,
                        sourceTexture: request.texture,
                        masks: masks,
                        targets: targets,
                        dynamicValues: request.dynamicValues,
                        localContrastStrength: request.localContrastStrength,
                        sourceUniforms: directUniforms,
                        audioSpectrum: request.audioSpectrum,
                        sourcePipeline: pipeline,
                        pipelines: authoredEffectPipelines,
                        commandBuffer: commandBuffer,
                        executionTrace: executionTrace,
                        executionOrigin: executionOrigin
                    )
                }
            } else {
                guard let textures = pool.textures(
                    width: requestedOffscreenWidth,
                    height: requestedOffscreenHeight
                ), let legacyDecision else {
                    executionTrace?.recordRouteOperation(
                        layerID: request.layer.id,
                        origin: executionOrigin,
                        operation: "legacy-target-allocation",
                        outcome: .failed(reasonCode: "offscreen-textures-unavailable")
                    )
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneOffscreenEffectRenderer.render(
                        sourceTexture: request.texture,
                        waterMaskTexture: masks.water,
                        foliageMaskTexture: masks.foliage,
                        auxMaskTexture: auxMask,
                        offscreenPair: textures,
                        offscreenPassCount: max(effectPlan.offscreenPassCount, 1),
                        blurPlan: effectPlan.gaussianBlur,
                        bloomPlan: effectPlan.bloom,
                        gradientColorPlan: effectPlan.gradientColor,
                        waterRippleNormalPlan: effectPlan.waterRippleNormal,
                        waterRippleNormalTexture: masks.waterRippleNormal,
                        perspectiveOpacityPlan: effectPlan.perspectiveOpacity,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        gaussianBlurPipeline: effectPlan.gaussianBlur == nil
                            && effectPlan.bloom == nil
                            ? nil
                            : authoredEffectPipelines.gaussianBlur,
                        bloomPipeline: effectPlan.bloom == nil
                            ? nil
                            : pipelineRepository.bloom(),
                        gradientColorPipeline: effectPlan.gradientColor == nil
                            ? nil
                            : pipelineRepository.gradientColor(),
                        waterRipplePipeline: effectPlan.waterRippleNormal == nil
                            ? nil
                            : authoredEffectPipelines.waterRipple,
                        perspectiveOpacityPipeline: effectPlan.perspectiveOpacity == nil
                            ? nil
                            : pipelineRepository.perspectiveOpacity(),
                        commandBuffer: commandBuffer,
                        legacyDecision: legacyDecision,
                        executionTrace: executionTrace,
                        executionOrigin: executionOrigin
                    )
                }
            }
            guard let finalTexture = renderedTexture ?? (
                request.requiresSourceCopy
                    || request.authoredEffectPlan != nil
                    || request.authoredEffectChain != nil
                    ? nil
                    : request.texture
            ) else {
                return false
            }
            let irisSuffix = request.authoredEffectChain?.irisInlineSuffix
            let finalValues = SceneImageLayerUniformValues(
                time: request.uniforms.time,
                alpha: request.finalCompositeAlpha ?? 1,
                cursorUV: request.uniforms.cursorUV
            )
            let finalUniforms = makeFragmentUniforms(
                values: finalValues,
                effectInputs: irisSuffix?.inputs ?? .neutral,
                textureFrame: .identity,
                tint: SIMD3(repeating: 1),
                foliageMaskUVScale: SIMD2(repeating: 1),
                dependencyBlendMode: chainConsumesDependency
                    ? nil
                    : request.dependencyEffect?.blendMode
            )
            let composited = SceneImageLayerMainPassRenderer.draw(
                texture: finalTexture,
                masks: irisSuffix == nil ? .empty : masks,
                mvp: request.mvp,
                uniforms: finalUniforms,
                dependencyTexture: chainConsumesDependency
                    ? nil
                    : request.dependencyEffect?.texture,
                layer: request.layer,
                pipeline: pipeline,
                colorBlendPipeline: colorBlendPipeline,
                mainPass: mainPass
            )
            if let irisSuffix {
                executionTrace?.recordExact(
                    identity: SceneEffectExecutionIdentity(
                        layerID: irisSuffix.effectKey.layerID,
                        effectIndex: irisSuffix.effectKey.effectIndex,
                        descriptorID: irisSuffix.effectKey.descriptorID
                    ),
                    origin: executionOrigin,
                    family: "iris-inline",
                    backend: "iris-inline",
                    outcome: composited
                        ? .encodedOutput
                        : .failed(reasonCode: "main-pass-returned-false")
                )
            } else if !composited, request.authoredEffectChain != nil {
                executionTrace?.recordRouteOperation(
                    layerID: request.layer.id,
                    origin: executionOrigin,
                    operation: "layer-final-composite",
                    outcome: .failed(reasonCode: "main-pass-returned-false")
                )
            } else if !composited, legacyDecision != nil {
                executionTrace?.recordRouteOperation(
                    layerID: request.layer.id,
                    origin: executionOrigin,
                    operation: "legacy-final-composite",
                    outcome: .failed(reasonCode: "main-pass-returned-false")
                )
            }
            return composited
        }
        if request.requiresSourceCopy
            || request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil
            || (routesOffscreen && request.dependencyEffect != nil) {
            return false
        }

        let rendered = SceneImageLayerMainPassRenderer.draw(
            texture: request.texture,
            masks: masks,
            mvp: request.mvp,
            uniforms: directUniforms,
            dependencyTexture: request.dependencyEffect?.texture,
            layer: request.layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            mainPass: mainPass
        )
        legacyDecision?.recordInlineExecution(
            trace: executionTrace,
            origin: executionOrigin,
            backend: "image-layer-pipeline",
            outcome: rendered
                ? .encodedOutput
                : .failed(reasonCode: "main-pass-returned-false")
        )
        if let legacyDecision, !legacyDecision.dispositions.isEmpty {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "legacy-direct-layer",
                outcome: rendered
                    ? .encoded
                    : .failed(reasonCode: "main-pass-returned-false")
            )
        }
        return rendered
    }
}
