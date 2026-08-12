import Metal

extension SceneEffectStageRenderer {
    static func renderWaterRipple(
        _ waterRipple: SceneWaterRippleExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              let resources = masks.waterRippleEffects[
                  waterRipple.effectKey.descriptorID
              ],
              let waterRipplePipeline = pipelines.waterRipple else {
            return nil
        }
        return SceneWaterRippleRenderer.render(
            plan: waterRipple,
            sourceTexture: sourceTexture,
            resources: resources,
            target: targets.outputTexture,
            time: time,
            pipeline: waterRipplePipeline,
            commandBuffer: commandBuffer
        )
    }
}
