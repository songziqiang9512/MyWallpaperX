import Metal
import simd

extension SceneOffscreenEffectRenderer {
    static func render(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        offscreenPair: SceneOffscreenTexturePool.Pair,
        offscreenPassCount: Int,
        blurPlan: SceneGaussianBlurPlan?,
        bloomPlan: SceneBloomPlan?,
        gradientColorPlan: SceneGradientColorPlan?,
        waterRippleNormalPlan: SceneWaterRippleNormalPlan?,
        waterRippleNormalTexture: MTLTexture?,
        perspectiveOpacityPlan: ScenePerspectiveOpacityPlan?,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        gaussianBlurPipeline: SceneGaussianBlurPipeline?,
        bloomPipeline: SceneBloomPipeline?,
        gradientColorPipeline: SceneGradientColorPipeline?,
        waterRipplePipeline: SceneWaterRipplePipeline?,
        perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline?,
        commandBuffer: MTLCommandBuffer,
        legacyDecision: SceneLegacyEffectPlanningDecision,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> MTLTexture? {
        let reporter = SceneLegacyOffscreenExecutionReporter(
            decision: legacyDecision,
            trace: executionTrace,
            origin: executionOrigin
        )
        let captured = captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            target: offscreenPair.primary,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        )
        reporter.recordSourceCapture(captured)
        guard captured else { return nil }

        if let gradientColorPlan {
            guard let gradientColorPipeline = reporter.requiredPipeline(
                gradientColorPipeline,
                operation: "legacy-gradient-color-preflight"
            ) else { return nil }
            let encoded = gradientColorPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                plan: gradientColorPlan,
                time: sourceUniforms.time,
                commandBuffer: commandBuffer
            )
            guard reporter.recordStage(
                family: "gradient-color",
                backend: "gradient-color-pipeline",
                encoded: encoded
            ) else { return nil }
            return offscreenPair.secondary
        }

        var effectSource = offscreenPair.primary
        var perspectiveTarget = offscreenPair.secondary
        if let waterRippleNormalPlan, let waterRippleNormalTexture {
            guard let waterRipplePipeline = reporter.requiredPipeline(
                waterRipplePipeline,
                operation: "legacy-water-ripple-normal-preflight"
            ) else { return nil }
            let encoded = waterRipplePipeline.encode(
                source: offscreenPair.primary,
                normalMap: waterRippleNormalTexture,
                target: offscreenPair.secondary,
                plan: waterRippleNormalPlan,
                time: sourceUniforms.time,
                commandBuffer: commandBuffer
            )
            guard reporter.recordStage(
                family: "water-ripple-normal",
                backend: "water-ripple-pipeline",
                encoded: encoded
            ) else { return nil }
            effectSource = offscreenPair.secondary
            perspectiveTarget = offscreenPair.tertiary
        }

        if let perspectiveOpacityPlan, let auxMaskTexture {
            guard let perspectiveOpacityPipeline = reporter.requiredPipeline(
                perspectiveOpacityPipeline,
                operation: "legacy-perspective-opacity-preflight"
            ) else { return nil }
            let encoded = perspectiveOpacityPipeline.encode(
                source: effectSource,
                opacityMask: auxMaskTexture,
                target: perspectiveTarget,
                plan: perspectiveOpacityPlan,
                commandBuffer: commandBuffer
            )
            guard reporter.recordStage(
                family: "perspective-opacity",
                backend: "perspective-opacity-pipeline",
                encoded: encoded
            ) else { return nil }
            return perspectiveTarget
        }

        if effectSource === offscreenPair.secondary { return effectSource }

        if let bloomPlan {
            guard let bloomPipeline = reporter.requiredPipeline(
                bloomPipeline,
                operation: "legacy-bloom-preflight"
            ), let gaussianBlurPipeline = reporter.requiredPipeline(
                gaussianBlurPipeline,
                operation: "legacy-bloom-preflight"
            ) else { return nil }
            let output = renderBloom(
                plan: bloomPlan,
                textures: offscreenPair,
                gaussianBlurPipeline: gaussianBlurPipeline,
                bloomPipeline: bloomPipeline,
                commandBuffer: commandBuffer
            )
            reporter.recordStage(
                family: "bloom",
                backend: "bloom-pipeline",
                encoded: output != nil
            )
            return output
        }

        if let blurPlan {
            guard let gaussianBlurPipeline = reporter.requiredPipeline(
                gaussianBlurPipeline,
                operation: "legacy-gaussian-blur-preflight"
            ) else { return nil }
            let horizontalStep = blurPlan.horizontalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.width)
            let verticalStep = blurPlan.verticalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.height)
            let encoded = gaussianBlurPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                step: SIMD2(horizontalStep, 0),
                commandBuffer: commandBuffer
            ) && gaussianBlurPipeline.encode(
                source: offscreenPair.secondary,
                target: offscreenPair.primary,
                step: SIMD2(0, verticalStep),
                commandBuffer: commandBuffer
            )
            let family = blurPlan.isPrecise
                ? "gaussian-blur-precise"
                : "gaussian-blur"
            guard reporter.recordStage(
                family: family,
                backend: "gaussian-blur-pipeline",
                encoded: encoded
            ) else { return nil }
            return offscreenPair.primary
        }

        guard offscreenPassCount > 1 else { return offscreenPair.primary }
        guard let effectEncoder = beginEncoder(
            commandBuffer: commandBuffer,
            target: offscreenPair.secondary
        ) else {
            reporter.recordRoute(
                "legacy-neutral-copy",
                .failed(reasonCode: "encoder-unavailable")
            )
            return nil
        }
        pipeline.bind(encoder: effectEncoder)
        pipeline.drawLayer(
            texture: offscreenPair.primary,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: fullTargetMVP,
            uniforms: neutralUniforms,
            encoder: effectEncoder
        )
        effectEncoder.endEncoding()
        reporter.recordRoute("legacy-neutral-copy", .encoded)
        return offscreenPair.secondary
    }

    private static func renderBloom(
        plan: SceneBloomPlan,
        textures: SceneOffscreenTexturePool.Pair,
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        bloomPipeline: SceneBloomPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let horizontalStep = SIMD2(plan.radius / Float(textures.secondary.width), 0)
        let verticalStep = SIMD2(0, plan.radius / Float(textures.secondary.height))
        guard bloomPipeline.encodeThreshold(
            source: textures.primary,
            target: textures.secondary,
            plan: plan,
            commandBuffer: commandBuffer
        ), gaussianBlurPipeline.encode(
            source: textures.secondary,
            target: textures.tertiary,
            step: horizontalStep,
            commandBuffer: commandBuffer
        ), gaussianBlurPipeline.encode(
            source: textures.tertiary,
            target: textures.secondary,
            step: verticalStep,
            commandBuffer: commandBuffer
        ), bloomPipeline.encodeComposite(
            source: textures.primary,
            bloom: textures.secondary,
            target: textures.tertiary,
            plan: plan,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return textures.tertiary
    }
}

nonisolated struct SceneLegacyOffscreenExecutionReporter {
    let decision: SceneLegacyEffectPlanningDecision
    let trace: SceneEffectExecutionFrameTrace?
    let origin: SceneEffectExecutionOrigin

    func recordSourceCapture(_ encoded: Bool) {
        recordRoute(
            "legacy-source-capture",
            encoded ? .encoded : .failed(reasonCode: "source-capture-failed")
        )
        guard encoded else { return }
        decision.recordInlineExecution(
            trace: trace,
            origin: origin,
            backend: "image-layer-pipeline",
            outcome: .encodedOutput
        )
    }

    func requiredPipeline<Value>(
        _ value: Value?,
        operation: String
    ) -> Value? {
        guard let value else {
            recordRoute(
                operation,
                .failed(reasonCode: "pipeline-unavailable")
            )
            return nil
        }
        return value
    }

    @discardableResult
    func recordStage(family: String, backend: String, encoded: Bool) -> Bool {
        decision.recordOffscreenExecution(
            family: family,
            trace: trace,
            origin: origin,
            backend: backend,
            outcome: encoded
                ? .encodedOutput
                : .failed(reasonCode: "encode-returned-false")
        )
        return encoded
    }

    func recordRoute(
        _ operation: String,
        _ outcome: SceneEffectRouteOperationOutcome
    ) {
        trace?.recordRouteOperation(
            layerID: decision.routeGroup.layerID,
            origin: origin,
            operation: operation,
            outcome: outcome
        )
    }
}
