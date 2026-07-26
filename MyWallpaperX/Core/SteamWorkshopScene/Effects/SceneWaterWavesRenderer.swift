import Metal

enum SceneWaterWavesRenderer {
    static func renderCaptured(
        plan: SceneWaterWavesExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        waterWavesPipeline: SceneWaterWavesPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.waterWavesEffects[plan.effectKey.descriptorID],
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: nil,
                  foliageMaskTexture: masks.foliage,
                  auxMaskTexture: masks.iris ?? masks.opacity,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: sourcePipeline,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return render(
            plan: plan,
            resources: resources,
            time: time,
            inputTexture: targets.inputTexture,
            outputTexture: targets.outputTexture,
            pipeline: waterWavesPipeline,
            commandBuffer: commandBuffer
        )
    }

    static func render(
        plan: SceneWaterWavesExecutionPlan,
        resources: SceneWaterWavesEffectTextures,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWaterWavesPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        // plan.maskTexturePath == nil 是 legacy profile 的合法无遮罩形态（等价 mask=1）；
        // 声明了遮罩却取不到贴图时 matches 拒绝，不静默降级。
        guard resources.matches(plan),
              plan.maskTexturePath == nil || resources.mask != nil,
              pipeline.encode(
                  source: inputTexture,
                  mask: plan.maskTexturePath != nil ? resources.mask : nil,
                  target: outputTexture,
                  plan: plan,
                  time: time,
                  maskUVScale: resources.maskUVScale,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return outputTexture
    }
}
