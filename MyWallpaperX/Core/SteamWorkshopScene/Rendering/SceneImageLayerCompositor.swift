import Metal
import simd

struct SceneImageLayerCompositor {
    let authoredEffectPipelines: SceneAuthoredEffectPipelineSet
    private let pipelineRepository: SceneImageEffectPipelineRepository
    private let colorBlendPipelineSlot: ScenePipelineSlot<SceneLayerColorBlendPipeline>
    let resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge?

    init?(device: MTLDevice) {
        self.init(pipelineRepository: SceneImageEffectPipelineRepository(device: device))
    }
    init(
        pipelineRepository: SceneImageEffectPipelineRepository,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil
    ) {
        self.pipelineRepository = pipelineRepository
        self.resolvedMaterialRuntime = resolvedMaterialRuntime
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
        frameTransaction: SceneSourceUpdateTransaction? = nil,
        executionTrace: SceneEffectExecutionFrameTrace? = nil,
        executionOrigin: SceneEffectExecutionOrigin = .image,
        onLegacyAuthoredRouteSelected: (() -> Void)? = nil
    ) -> Bool {
        let resolvedMaterialRoute = resolvedMaterialClaim(for: request)
        guard !resolvedMaterialRoute.isRejected else { return false }
        let resolvedMaterialClaim = resolvedMaterialRoute.execution
        let dependencyEffect = request.dependencyEffect

        guard (dependencyEffect.map {
            ($0.slotIndex == 1 && ($0.blendMode == 0 || $0.blendMode == 5))
                || ($0.slotIndex == 3 && $0.blendMode == 0)
        } ?? true) else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "dependency-input-invalid")
        }
        let masks = request.masks
        let layerColorBlendMode = request.layer.colorBlendMode ?? 0
        guard SceneLayerColorBlendRenderer.supports(layerColorBlendMode) else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "layer-color-blend-unsupported")
        }
        let colorBlendPipeline = layerColorBlendMode == 0 ? nil : colorBlendPipelineSlot.resolve()
        guard layerColorBlendMode == 0 || colorBlendPipeline != nil else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "layer-color-blend-pipeline-unavailable")
        }
        let auxMask = masks.iris ?? masks.opacity
        let runtimeAuthoredPlan = request.authoredEffectPlan ?? request.authoredEffectChain?.singleStage
        let usesAuthoredExecution = resolvedMaterialClaim != nil || request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil || request.suppressesLegacyEffectFallback
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
        let effectPlan: SceneEffectRuntimePlan
        if resolvedMaterialClaim != nil || request.suppressesLegacyEffectFallback {
            effectPlan = .neutral
        } else {
            effectPlan = legacyDecision?.runtimePlan ?? SceneEffectRuntimePlanner.plan(
                for: request.layer,
                hasIrisMask: masks.iris != nil,
                hasOpacityMask: masks.opacity != nil && masks.iris == nil,
                hasWaterMask: masks.water != nil,
                hasFoliageMask: masks.foliage != nil,
                hasWaterRippleNormal: masks.waterRippleNormal != nil,
                authoredEffectPlan: runtimeAuthoredPlan,
                blocksLegacyGaussianBlur: request.blocksLegacyGaussianBlur
            )
        }
        guard resolvedMaterialClaim != nil
            || request.authoredEffectChain != nil
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
            || resolvedMaterialClaim != nil
            || request.authoredEffectChain != nil
            || request.suppressesLegacyEffectFallback
            || layerColorBlendMode > 0
        guard !routesOffscreen
            || request.layer.contentKind != "solid"
            || request.offscreenSize != nil else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "solid-offscreen-size-unavailable")
        }
        let chainConsumesDependency = request.authoredEffectChain != nil
            && dependencyEffect != nil

        let sourceEffectInputs = request.authoredEffectChain == nil
            && resolvedMaterialClaim == nil && !request.suppressesLegacyEffectFallback
            ? effectPlan.inputs
            : .neutral
        guard let directUniforms = sourceFragmentUniforms(
            for: request,
            effectInputs: sourceEffectInputs,
            routesOffscreen: routesOffscreen
        ) else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "base-texture-frame-invalid")
        }
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            var renderedTexture: MTLTexture?
            var graphExecutionTicket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket?
            if let claim = resolvedMaterialClaim,
               let resolvedMaterialRuntime {
                switch executeResolvedMaterialClaim(
                    runtime: resolvedMaterialRuntime,
                    claim: claim,
                    framePlan: request.resolvedMaterialFrameTargetPlan,
                    layerID: request.layer.id,
                    mainPass: mainPass,
                    executionTrace: executionTrace,
                    executionOrigin: executionOrigin
                ) {
                case let .encoded(texture, ticket):
                    (renderedTexture, graphExecutionTicket) = (texture, ticket)
                case .failed:
                    return false
                }
            } else if let authoredChain = request.authoredEffectChain {
                onLegacyAuthoredRouteSelected?()
                renderedTexture = renderLegacyAuthoredChain(
                    authoredChain,
                    request: request,
                    pool: pool,
                    sourceUniforms: directUniforms,
                    pipeline: pipeline,
                    pipelines: authoredEffectPipelines,
                    mainPass: mainPass,
                    frameTransaction: frameTransaction,
                    executionTrace: executionTrace,
                    executionOrigin: executionOrigin
                )
            } else if let authoredPlan = request.authoredEffectPlan {
                onLegacyAuthoredRouteSelected?()
                guard let frameTables = request.legacyAuthoredFrameTables,
                      frameTables.tables.count == 1 else {
                    executionTrace?.recordRouteOperation(
                        layerID: request.layer.id,
                        origin: executionOrigin,
                        operation: "standalone-authored-frame-tables",
                        outcome: .failed(reasonCode: "frame-tables-unavailable")
                    )
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer -> MTLTexture? in
                    SceneStandaloneAuthoredEffectRenderer.render(
                        plan: authoredPlan,
                        sourceTexture: request.texture,
                        masks: masks,
                        targets: frameTables.tables[0],
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
            } else if request.suppressesLegacyEffectFallback {
                let dimensions = legacyOffscreenDimensions(for: request)
                guard let textures = pool.textures(
                    width: dimensions.width,
                    height: dimensions.height
                ) else { return false }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneOffscreenEffectRenderer.captureSource(
                        sourceTexture: request.texture,
                        waterMaskTexture: nil,
                        foliageMaskTexture: nil,
                        auxMaskTexture: nil,
                        target: textures.primary,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        commandBuffer: commandBuffer
                    ) ? textures.primary : nil
                }
            } else {
                let dimensions = legacyOffscreenDimensions(for: request)
                guard let textures = pool.textures(
                    width: dimensions.width,
                    height: dimensions.height
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
                    || resolvedMaterialClaim != nil
                    || request.authoredEffectPlan != nil
                    || request.authoredEffectChain != nil
                    || request.suppressesLegacyEffectFallback
                    ? nil
                    : request.texture
            ) else {
                return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                    reasonCode: "final-offscreen-texture-unavailable")
            }
            let finalValues = SceneImageLayerUniformValues(
                time: request.uniforms.time,
                alpha: request.finalCompositeAlpha ?? 1,
                cursorUV: request.uniforms.cursorUV
            )
            let finalUniforms = makeFragmentUniforms(
                values: finalValues,
                effectInputs: .neutral,
                textureFrame: .identity,
                tint: SIMD3(repeating: 1),
                foliageMaskUVScale: SIMD2(repeating: 1),
                dependencyBlendMode: chainConsumesDependency
                    ? nil
                    : dependencyEffect?.blendMode
            )
            let composited = SceneImageLayerMainPassRenderer.draw(
                texture: finalTexture,
                masks: .empty,
                mvp: request.mvp,
                uniforms: finalUniforms,
                dependencyTexture: chainConsumesDependency
                    ? nil
                    : dependencyEffect?.texture,
                layer: request.layer,
                pipeline: pipeline,
                colorBlendPipeline: colorBlendPipeline,
                mainPass: mainPass
            )
            if let graphExecutionTicket {
                guard consumeResolvedMaterialComposite(
                    graphExecutionTicket,
                    texture: finalTexture,
                    consumed: composited,
                    layerID: request.layer.id,
                    executionTrace: executionTrace,
                    executionOrigin: executionOrigin
                ) else { return false }
            }
            if !composited, request.authoredEffectChain != nil {
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
            || resolvedMaterialClaim != nil
            || request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil
            || request.suppressesLegacyEffectFallback
            || (routesOffscreen && dependencyEffect != nil) {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "offscreen-pool-unavailable")
        }
        let rendered = SceneImageLayerMainPassRenderer.draw(
            texture: request.texture,
            masks: masks,
            mvp: request.mvp,
            uniforms: directUniforms,
            dependencyTexture: dependencyEffect?.texture,
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

    func executeResolvedMaterialClaim(
        runtime: SceneResolvedMaterialRuntimeBridge,
        claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        layerID: Int,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> SceneResolvedMaterialGraphComposition.Result {
        SceneResolvedMaterialGraphComposition.executeClaimed(
            runtime: runtime,
            claim: claim,
            framePlan: framePlan,
            layerID: layerID,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: executionOrigin
        )
    }
}
