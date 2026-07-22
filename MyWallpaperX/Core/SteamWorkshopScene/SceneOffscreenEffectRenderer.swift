import Metal
import simd

enum SceneOffscreenEffectRenderer {
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
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        bloomPipeline: SceneBloomPipeline,
        gradientColorPipeline: SceneGradientColorPipeline,
        waterRipplePipeline: SceneWaterRipplePipeline,
        perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            target: offscreenPair.primary,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }

        if let gradientColorPlan {
            guard gradientColorPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                plan: gradientColorPlan,
                time: sourceUniforms.time,
                commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return offscreenPair.secondary
        }

        var effectSource = offscreenPair.primary
        var perspectiveTarget = offscreenPair.secondary
        if let waterRippleNormalPlan, let waterRippleNormalTexture {
            guard waterRipplePipeline.encode(
               source: offscreenPair.primary,
               normalMap: waterRippleNormalTexture,
               target: offscreenPair.secondary,
               plan: waterRippleNormalPlan,
               time: sourceUniforms.time,
               commandBuffer: commandBuffer
            ) else {
                return nil
            }
            effectSource = offscreenPair.secondary
            perspectiveTarget = offscreenPair.tertiary
        }

        if let perspectiveOpacityPlan, let auxMaskTexture {
            guard perspectiveOpacityPipeline.encode(
               source: effectSource,
               opacityMask: auxMaskTexture,
               target: perspectiveTarget,
               plan: perspectiveOpacityPlan,
               commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return perspectiveTarget
        }

        if effectSource === offscreenPair.secondary {
            return effectSource
        }

        if let bloomPlan {
            return renderBloom(
                plan: bloomPlan,
                textures: offscreenPair,
                gaussianBlurPipeline: gaussianBlurPipeline,
                bloomPipeline: bloomPipeline,
                commandBuffer: commandBuffer
            )
        }

        if let blurPlan {
            let horizontalStep = blurPlan.horizontalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.width)
            let verticalStep = blurPlan.verticalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.height)
            guard gaussianBlurPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                step: SIMD2(horizontalStep, 0),
                commandBuffer: commandBuffer
            ), gaussianBlurPipeline.encode(
                source: offscreenPair.secondary,
                target: offscreenPair.primary,
                step: SIMD2(0, verticalStep),
                commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return offscreenPair.primary
        }

        guard offscreenPassCount > 1 else { return offscreenPair.primary }
        guard let effectEncoder = beginEncoder(
                commandBuffer: commandBuffer,
                target: offscreenPair.secondary
              ) else {
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
        return offscreenPair.secondary
    }

    static func renderStandardBlur(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        targets: SceneOffscreenTexturePool.StandardBlurTargets,
        plan: SceneStandardBlurPlan,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        standardBlurPipeline: SceneStandardBlurPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            target: targets.previousFull,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return SceneStandardBlurRenderer.render(
            plan: plan,
            targets: targets,
            pipeline: standardBlurPipeline,
            commandBuffer: commandBuffer
        )
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

    private static func beginEncoder(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture
    ) -> MTLRenderCommandEncoder? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    private static func captureSource(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let encoder = beginEncoder(commandBuffer: commandBuffer, target: target) else {
            return false
        }
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: sourceTexture,
            shakeMaskTexture: nil,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            mvp: fullTargetMVP,
            uniforms: sourceUniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        return true
    }

    private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
    private static let neutralUniforms = SceneLayerFragmentUniforms.neutral()
}
