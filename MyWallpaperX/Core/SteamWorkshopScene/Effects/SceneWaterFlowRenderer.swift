import Metal

enum SceneWaterFlowRenderer {
    static func renderCaptured(
        plan: SceneWaterFlowExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        waterFlowPipeline: SceneWaterFlowPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.waterFlowEffects[plan.effectKey.descriptorID],
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: masks.water,
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
            pipeline: waterFlowPipeline,
            commandBuffer: commandBuffer
        )
    }

    static func render(
        plan: SceneWaterFlowExecutionPlan,
        resources: SceneWaterFlowEffectTextures,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWaterFlowPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard resources.matches(plan),
              let flowTexture = resources.flow,
              let phaseTexture = resources.phase,
              pipeline.encode(
                  source: inputTexture,
                  flowTexture: flowTexture,
                  phaseTexture: phaseTexture,
                  target: outputTexture,
                  plan: plan,
                  time: time,
                  maskUVScale: resources.flowUVScale,
                  flowSampling: resources.flowSampling,
                  phaseSampling: resources.phaseSampling,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return outputTexture
    }
}
