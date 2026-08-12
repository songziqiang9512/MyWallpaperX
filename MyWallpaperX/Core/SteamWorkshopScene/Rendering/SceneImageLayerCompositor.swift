import Metal
import simd

struct SceneImageLayerCompositor {
    let authoredEffectPipelines: SceneAuthoredEffectPipelineSet
    private let colorBlendPipelineSlot: ScenePipelineSlot<SceneLayerColorBlendPipeline>
    let resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge?

    init?(device: MTLDevice) {
        self.init(pipelineRepository: SceneImageEffectPipelineRepository(device: device))
    }
    init(
        pipelineRepository: SceneImageEffectPipelineRepository,
        resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil
    ) {
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
        executionTrace: SceneEffectExecutionFrameTrace? = nil,
        executionOrigin: SceneEffectExecutionOrigin = .image
    ) -> Bool {
        guard request.resolvedMaterialFrameTargetPlan == nil
            || resolvedMaterialRuntime != nil else {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "resolved-material-claim",
                outcome: .failed(reasonCode: "resolved-material-runtime-unavailable")
            )
            return false
        }
        let resolvedMaterialRoute = resolvedMaterialClaim(for: request)
        guard !resolvedMaterialRoute.isRejected else { return false }
        let resolvedMaterialClaim = resolvedMaterialRoute.execution
        let hasUnclaimedVisibleEffects = request.layer.effects.contains {
            $0.visible != false
        } && resolvedMaterialClaim == nil
        guard !hasUnclaimedVisibleEffects else {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "unclaimed-effect-product-authority",
                outcome: .failed(reasonCode: "unclaimed-visible-effects")
            )
            return false
        }
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
        let routesOffscreen = request.requiresSourceCopy
            || resolvedMaterialClaim != nil
            || layerColorBlendMode > 0
        guard !routesOffscreen
            || request.layer.contentKind != "solid"
            || request.offscreenSize != nil else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "solid-offscreen-size-unavailable")
        }
        guard let directUniforms = sourceFragmentUniforms(
            for: request,
            routesOffscreen: routesOffscreen
        ) else {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "base-texture-frame-invalid")
        }
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            var renderedTexture: MTLTexture?
            var graphExecutionTicket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket?
            if let claim = resolvedMaterialClaim {
                guard let resolvedMaterialRuntime else {
                    return rejectResolvedMaterialClaim(
                        resolvedMaterialClaim,
                        reasonCode: "resolved-material-runtime-unavailable"
                    )
                }
                switch executeResolvedMaterialClaim(
                    runtime: resolvedMaterialRuntime,
                    claim: claim,
                    framePlan: request.resolvedMaterialFrameTargetPlan,
                    layerID: request.layer.id,
                    dependencyEffect: dependencyEffect,
                    mainPass: mainPass,
                    executionTrace: executionTrace,
                    executionOrigin: executionOrigin
                ) {
                case let .encoded(texture, ticket):
                    (renderedTexture, graphExecutionTicket) = (texture, ticket)
                case .failed:
                    return false
                }
            } else {
                let dimensions = offscreenDimensions(for: request)
                guard let target = pool.compositionTarget(
                    width: dimensions.width,
                    height: dimensions.height
                ) else { return false }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneOffscreenEffectRenderer.captureSource(
                        sourceTexture: request.texture,
                        target: target.texture,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        commandBuffer: commandBuffer
                    ) ? target.texture : nil
                }
            }
            guard let finalTexture = renderedTexture ?? (
                request.requiresSourceCopy
                    || resolvedMaterialClaim != nil
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
            let dependencyConsumed = graphExecutionTicket?
                .consumesExternalPrimaryDependency == true
            let finalUniforms = makeFragmentUniforms(
                values: finalValues,
                textureFrame: .identity,
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: dependencyConsumed
                    ? nil
                    : dependencyEffect?.blendMode
            )
            let composited = SceneImageLayerMainPassRenderer.draw(
                texture: finalTexture,
                mvp: request.mvp,
                uniforms: finalUniforms,
                dependencyTexture: dependencyConsumed
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
            return composited
        }
        if request.requiresSourceCopy
            || resolvedMaterialClaim != nil
            || (routesOffscreen && dependencyEffect != nil) {
            return rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "offscreen-pool-unavailable")
        }
        let rendered = SceneImageLayerMainPassRenderer.draw(
            texture: request.texture,
            mvp: request.mvp,
            uniforms: directUniforms,
            dependencyTexture: dependencyEffect?.texture,
            layer: request.layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            mainPass: mainPass
        )
        return rendered
    }

    func executeResolvedMaterialClaim(
        runtime: SceneResolvedMaterialRuntimeBridge,
        claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        layerID: Int,
        dependencyEffect: SceneDependencyEffectInput?,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> SceneResolvedMaterialGraphComposition.Result {
        SceneResolvedMaterialGraphComposition.executeClaimed(
            runtime: runtime,
            claim: claim,
            framePlan: framePlan,
            layerID: layerID,
            dependencyEffect: dependencyEffect,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: executionOrigin
        )
    }
}
