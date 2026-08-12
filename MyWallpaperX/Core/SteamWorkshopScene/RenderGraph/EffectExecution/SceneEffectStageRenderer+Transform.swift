import Metal

extension SceneEffectStageRenderer {
    static func renderTransformOrFisheye(
        _ stage: SceneEffectStageExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        switch stage.backend {
        case .transform(let transform):
            guard transform.renderGraph.renderTargets.isEmpty,
                  targets.plan.logicalTargets.isEmpty,
                  capture(
                      sourceTexture: sourceTexture,
                      masks: masks,
target: targets.outputTexture,
                      sourceUniforms: sourceUniforms,
                      pipeline: pipeline,
                      commandBuffer: commandBuffer
                  ) else {
                return nil
            }
        case .fisheyeZeroDistortion(let fisheye):
            guard fisheye.renderGraph.renderTargets.isEmpty,
                  targets.plan.logicalTargets.isEmpty,
                  let fisheyePipeline = pipelines.fisheyeZeroDistortion,
                  capture(
                      sourceTexture: sourceTexture,
                      masks: masks,
target: targets.inputTexture,
                      sourceUniforms: sourceUniforms,
                      pipeline: pipeline,
                      commandBuffer: commandBuffer
                  ),
                  fisheyePipeline.encode(
                      source: targets.inputTexture,
                      target: targets.outputTexture,
                      uniforms: .init(center: fisheye.center, size: fisheye.size),
                      commandBuffer: commandBuffer
                  ) else {
                return nil
            }
        default:
            return nil
        }
        return targets.outputTexture
    }

    private static func capture(
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        target: MTLTexture,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        SceneOffscreenEffectRenderer.captureSource(
            sourceTexture: sourceTexture,
            target: target,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        )
    }
}
