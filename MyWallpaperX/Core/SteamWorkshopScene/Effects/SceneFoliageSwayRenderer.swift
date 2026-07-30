import Metal
import simd

enum SceneFoliageSwayRenderer {
    static func render(
        plan: SceneFoliageSwayExecutionPlan,
        sourceTexture: MTLTexture,
        resources: SceneFoliageSwayEffectTextures,
        target: MTLTexture,
        time: Float,
        pipeline: SceneFoliageSwayPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard resources.matches(plan),
              let noise = resources.noise,
              pipeline.encode(
                  source: sourceTexture,
                  mask: plan.maskTexturePath == nil ? nil : resources.mask,
                  noise: noise,
                  target: target,
                  plan: plan.runtimePlan,
                  maskUVScale: resources.maskUVScale,
                  time: time,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return target
    }
}
