import Metal

extension SceneAuthoredEffectChainRenderer {
    static func renderAuthoredShader(
        _ shader: SceneAuthoredShaderExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        frame: SceneAuthoredShaderFrameInputs?,
        pipeline: SceneImageLayerPipeline,
        pipelineCache: SceneAuthoredShaderPipelineCache,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let frame,
              targets.plan.logicalTargets.isEmpty,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: masks.water,
                  foliageMaskTexture: masks.foliage,
                  auxMaskTexture: auxMask,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              SceneAuthoredShaderRenderer.encode(
                  plan: shader,
                  source: targets.inputTexture,
                  target: targets.outputTexture,
                  frame: frame,
                  pipelineCache: pipelineCache,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
