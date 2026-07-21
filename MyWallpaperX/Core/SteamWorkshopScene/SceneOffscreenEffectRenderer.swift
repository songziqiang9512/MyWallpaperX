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
        perspectiveOpacityPlan: ScenePerspectiveOpacityPlan?,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        bloomPipeline: SceneBloomPipeline,
        perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let sourceEncoder = beginEncoder(
            commandBuffer: commandBuffer,
            target: offscreenPair.primary
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
            mvp: fullTargetMVP,
            uniforms: sourceUniforms,
            encoder: sourceEncoder
        )
        sourceEncoder.endEncoding()

        if let perspectiveOpacityPlan, let auxMaskTexture,
           perspectiveOpacityPipeline.encode(
               source: offscreenPair.primary,
               opacityMask: auxMaskTexture,
               target: offscreenPair.secondary,
               plan: perspectiveOpacityPlan,
               commandBuffer: commandBuffer
           ) {
            return offscreenPair.secondary
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
            let horizontalStep = blurPlan.usesPixelSteps
                ? blurPlan.horizontalStep / Float(offscreenPair.primary.width)
                : blurPlan.horizontalStep
            let verticalStep = blurPlan.usesPixelSteps
                ? blurPlan.verticalStep / Float(offscreenPair.primary.height)
                : blurPlan.verticalStep
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
                return offscreenPair.primary
            }
            return offscreenPair.primary
        }

        guard offscreenPassCount > 1,
              let effectEncoder = beginEncoder(
                commandBuffer: commandBuffer,
                target: offscreenPair.secondary
              ) else {
            return offscreenPair.primary
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

    private static func renderBloom(
        plan: SceneBloomPlan,
        textures: SceneOffscreenTexturePool.Pair,
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        bloomPipeline: SceneBloomPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
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
            return textures.primary
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

    private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
    private static let neutralUniforms = SceneLayerFragmentUniforms(
        time: 0,
        alpha: 1,
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
