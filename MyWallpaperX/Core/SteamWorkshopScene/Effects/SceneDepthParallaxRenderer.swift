import Metal
import simd

enum SceneDepthParallaxRenderer {
    static func render(
        plan: SceneDepthParallaxExecutionPlan,
        resources: SceneDepthParallaxEffectTextures,
        sourceTexture: MTLTexture,
        target: MTLTexture,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        pipeline: SceneDepthParallaxPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let arguments = resources.resolvedArguments(for: plan),
              pipeline.encode(
                  source: sourceTexture,
                  depth: arguments.depth.texture,
                  target: target,
                  plan: plan,
                  cursorUV: pointerIsInside
                      ? cursorUV
                      : SIMD2(repeating: 0.5),
                  depthUVScale: arguments.depthUVScale,
                  depthSampling: arguments.depth.sampling,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return target
    }
}
