import Metal
import simd

enum SceneStandardBlurRenderer {
    static func render(
        plan: SceneStandardBlurPlan,
        targets: SceneOffscreenTexturePool.StandardBlurTargets,
        pipeline: SceneStandardBlurPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let horizontalStep = plan.horizontalStep / Float(targets.quarterA.width)
        let verticalStep = plan.verticalStep / Float(targets.quarterA.height)
        guard pipeline.encodeDownsample(
            source: targets.previousFull,
            target: targets.quarterA,
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: targets.quarterA,
            target: targets.quarterB,
            step: SIMD2(horizontalStep, 0),
            commandBuffer: commandBuffer
        ), pipeline.encodeGaussian(
            source: targets.quarterB,
            target: targets.quarterA,
            step: SIMD2(0, verticalStep),
            commandBuffer: commandBuffer
        ), pipeline.encodeCombine(
            blurred: targets.quarterA,
            previous: targets.previousFull,
            target: targets.outputFull,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return targets.outputFull
    }
}
