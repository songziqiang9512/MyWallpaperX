import Metal
import simd

enum SceneFoliageSwayRenderer {
    static func render(
        plan: SceneFoliageSwayExecutionPlan,
        sourceTexture: MTLTexture,
        maskTexture: MTLTexture,
        maskUVScale: SIMD2<Float>,
        target: MTLTexture,
        time: Float,
        sourcePipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard sourceTexture !== target,
              time.isFinite,
              maskUVScale.x.isFinite,
              maskUVScale.y.isFinite,
              maskUVScale.x > 0,
              maskUVScale.y > 0 else {
            return nil
        }
        let runtime = plan.runtimePlan
        var uniforms = SceneLayerFragmentUniforms.neutral()
        var flags = SceneEffectFlags()
        flags.insert(.foliagesway)
        flags.insert(.hasFoliageMask)
        uniforms.time = time
        uniforms.effectFlags = flags.rawValue
        uniforms.effectParams3 = SIMD4(
            runtime.strength,
            runtime.speed,
            runtime.phase,
            runtime.power
        )
        uniforms.effectParams4 = SIMD4(
            runtime.noiseScale,
            runtime.ratio,
            runtime.direction,
            0
        )
        uniforms.effectParams5 = SIMD4(maskUVScale.x, maskUVScale.y, 0, 0)
        guard SceneOffscreenEffectRenderer.captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: nil,
            foliageMaskTexture: maskTexture,
            auxMaskTexture: nil,
            target: target,
            sourceUniforms: uniforms,
            pipeline: sourcePipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return target
    }
}
