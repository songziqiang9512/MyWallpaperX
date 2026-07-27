import Metal

/// godrays 五 pass 编排：capture -> downsample2(half1) -> cast(half2)
/// -> gaussian_x(half1) -> gaussian_y(half2) -> combine(output)。
/// 两张 half RT 由 graph target 表提供（planner 已校验 scale 2 / rgba_backbuffer）。
enum SceneGodraysRenderer {
    static func renderCaptured(
        plan: SceneGodraysPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        godraysPipeline: SceneGodraysPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        // 遮罩挂在 effect 实例上，按 descriptorID 取；声明了遮罩或需要 noise 却取
        // 不到贴图时整段拒绝，不静默降级。
        guard let resources = masks.godraysEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
              let firstHalf = targets.texture(for: plan.firstHalfTarget),
              let secondHalf = targets.texture(for: plan.secondHalfTarget),
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: masks.water,
                  foliageMaskTexture: masks.foliage,
                  auxMaskTexture: masks.iris ?? masks.opacity,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ),
              godraysPipeline.encodeDownsample(
                  source: targets.inputTexture,
                  mask: plan.maskTexturePath != nil ? resources.mask : nil,
                  maskUVScale: resources.maskUVScale,
                  noise: resources.noise,
                  target: firstHalf,
                  plan: plan,
                  time: time,
                  commandBuffer: commandBuffer
              ),
              godraysPipeline.encodeCast(
                  source: firstHalf,
                  target: secondHalf,
                  plan: plan,
                  commandBuffer: commandBuffer
              ),
              godraysPipeline.encodeGaussian(
                  source: secondHalf,
                  target: firstHalf,
                  plan: plan,
                  vertical: false,
                  commandBuffer: commandBuffer
              ),
              godraysPipeline.encodeGaussian(
                  source: firstHalf,
                  target: secondHalf,
                  plan: plan,
                  vertical: true,
                  commandBuffer: commandBuffer
              ),
              godraysPipeline.encodeCombine(
                  rays: secondHalf,
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  plan: plan,
                  commandBuffer: commandBuffer
              )
        else {
            return nil
        }
        return targets.outputTexture
    }
}
