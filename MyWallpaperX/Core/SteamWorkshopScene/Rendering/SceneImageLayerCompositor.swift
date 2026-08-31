import Metal
import simd

struct SceneImageLayerCompositor {
    enum DrawOutcome: Equatable {
        case normal(consumedDependency: Bool)
        case layerSourcePassthrough
        case failed

        var encoded: Bool {
            switch self {
            case .normal, .layerSourcePassthrough:
                return true
            case .failed:
                return false
            }
        }

        var consumedDependency: Bool {
            guard case let .normal(consumedDependency) = self else {
                return false
            }
            return consumedDependency
        }
    }

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
        drawOutcome(
            request,
            explicitLayerSourcePublication: nil,
            pipeline: pipeline,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: executionOrigin
        ).encoded
    }

    @discardableResult
    func drawOutcome(
        _ request: SceneImageLayerDrawRequest,
        explicitLayerSourcePublication: SceneTextureProviderPublication?,
        resolvedMaterialGraphOutputPublisher: ((MTLTexture) -> Bool)? = nil,
        pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace? = nil,
        executionOrigin: SceneEffectExecutionOrigin = .image
    ) -> DrawOutcome {
        guard request.resolvedMaterialFrameTargetPlan == nil
            || resolvedMaterialRuntime != nil else {
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "resolved-material-claim",
                outcome: .failed(reasonCode: "resolved-material-runtime-unavailable")
            )
            return .failed
        }
        let resolvedMaterialRoute = resolvedMaterialClaim(for: request)
        guard !resolvedMaterialRoute.isRejected else { return .failed }
        let resolvedMaterialClaim = resolvedMaterialRoute.execution
        let hasUnclaimedVisibleEffects = request.layer.effects.contains {
            $0.visible != false
        } && resolvedMaterialClaim == nil
        let passthroughResolution = SceneLayerSourcePassthroughPlan.resolve(
            request: request,
            publication: explicitLayerSourcePublication,
            route: resolvedMaterialRoute
        )
        if case let .success(passthroughPlan) = passthroughResolution {
            let uniforms = makeFragmentUniforms(
                values: request.uniforms,
                textureFrame: passthroughPlan.source.uvTransform,
                tint: SIMD3<Float>(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: passthroughPlan.source.sampling
            )
            let encoded = SceneImageLayerMainPassRenderer.draw(
                texture: passthroughPlan.source.texture,
                mvp: passthroughPlan.modelViewProjection,
                uniforms: uniforms,
                dependencyTexture: nil,
                layer: request.layer,
                pipeline: pipeline,
                colorBlendPipeline: nil,
                mainPass: mainPass
            )
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "degraded-layer-source-passthrough",
                outcome: encoded
                    ? .encoded
                    : .failed(reasonCode: "main-pass-encode-failed")
            )
            return encoded ? .layerSourcePassthrough : .failed
        }
        guard !hasUnclaimedVisibleEffects else {
            let reasonCode: String
            switch passthroughResolution {
            case .success:
                reasonCode = "unclaimed-visible-effects"
            case let .failure(reason):
                reasonCode = "unclaimed-visible-effects-\(reason.rawValue)"
            }
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "unclaimed-effect-product-authority",
                outcome: .failed(reasonCode: reasonCode)
            )
            return .failed
        }
        let dependencyEffect = request.dependencyEffect

        let graphConsumesExternalPrimary = request
            .resolvedMaterialFrameTargetPlan?
            .consumesExternalPrimaryDependency == true
        guard (dependencyEffect.map {
            if graphConsumesExternalPrimary {
                return $0.slotIndex == 1
                    && (0...SceneBlendModeShaderSource.maximumMode)
                        .contains($0.blendMode)
            }
            return ($0.slotIndex == 1
                && ($0.blendMode == 0 || $0.blendMode == 5))
                || ($0.slotIndex == 3 && $0.blendMode == 0)
        } ?? true) else {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "dependency-input-invalid")
            return .failed
        }
        let layerColorBlendMode = request.layer.colorBlendMode ?? 0
        guard SceneLayerColorBlendRenderer.supports(layerColorBlendMode) else {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "layer-color-blend-unsupported")
            return .failed
        }
        let colorBlendPipeline = layerColorBlendMode == 0 ? nil : colorBlendPipelineSlot.resolve()
        guard layerColorBlendMode == 0 || colorBlendPipeline != nil else {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "layer-color-blend-pipeline-unavailable")
            return .failed
        }
        let routesOffscreen = request.requiresSourceCopy
            || resolvedMaterialClaim != nil
            || layerColorBlendMode > 0
        guard !routesOffscreen
            || request.layer.contentKind != "solid"
            || request.offscreenSize != nil else {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "solid-offscreen-size-unavailable")
            return .failed
        }
        guard let directUniforms = sourceFragmentUniforms(
            for: request,
            routesOffscreen: routesOffscreen
        ) else {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "base-texture-frame-invalid")
            return .failed
        }
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            var renderedTexture: MTLTexture?
            var graphExecutionTicket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket?
            if let claim = resolvedMaterialClaim {
                guard let resolvedMaterialRuntime else {
                    _ = rejectResolvedMaterialClaim(
                        resolvedMaterialClaim,
                        reasonCode: "resolved-material-runtime-unavailable"
                    )
                    return .failed
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
                    return .failed
                }
            } else {
                let dimensions = offscreenDimensions(for: request)
                guard let target = pool.compositionTarget(
                    width: dimensions.width,
                    height: dimensions.height
                ) else { return .failed }
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
                _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                    reasonCode: "final-offscreen-texture-unavailable")
                return .failed
            }
            if let resolvedMaterialGraphOutputPublisher {
                guard let graphExecutionTicket,
                      resolvedMaterialGraphOutputPublisher(finalTexture) else {
                    if let graphExecutionTicket {
                        _ = consumeResolvedMaterialComposite(
                            graphExecutionTicket,
                            texture: finalTexture,
                            consumed: false,
                            layerID: request.layer.id,
                            executionTrace: executionTrace,
                            executionOrigin: executionOrigin
                        )
                    }
                    return .failed
                }
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
                ) else { return .failed }
            }
            return composited
                ? .normal(consumedDependency: dependencyEffect != nil)
                : .failed
        }
        if request.requiresSourceCopy
            || resolvedMaterialClaim != nil
            || (routesOffscreen && dependencyEffect != nil) {
            _ = rejectResolvedMaterialClaim(resolvedMaterialClaim,
                reasonCode: "offscreen-pool-unavailable")
            return .failed
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
            ? .normal(consumedDependency: dependencyEffect != nil)
            : .failed
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
