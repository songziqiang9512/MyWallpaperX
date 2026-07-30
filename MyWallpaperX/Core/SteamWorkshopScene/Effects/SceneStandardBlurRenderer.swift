import Metal
import simd

enum SceneStandardBlurRenderer {
    static func render(
        plan: SceneStandardBlurPlan,
        inputTexture: MTLTexture,
        quarterA: MTLTexture,
        quarterB: MTLTexture,
        outputTexture: MTLTexture,
        maskTexture: MTLTexture? = nil,
        maskUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        maskSampling: SceneTextureSampling = .linearClamp,
        pipeline: SceneStandardBlurPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let horizontalStep = plan.horizontalStep / Float(quarterA.width)
        let verticalStep = plan.verticalStep / Float(quarterA.height)
        guard pipeline.encodeDownsample(
            source: inputTexture,
            target: quarterA,
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: quarterA,
            target: quarterB,
            step: SIMD2(horizontalStep, 0),
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: quarterB,
            target: quarterA,
            step: SIMD2(0, verticalStep),
            commandBuffer: commandBuffer
        ), pipeline.encodeCombine(
            blurred: quarterA,
            mask: maskTexture,
            maskUVScale: maskUVScale,
            maskSampling: maskSampling,
            previous: inputTexture,
            target: outputTexture,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return outputTexture
    }
}
