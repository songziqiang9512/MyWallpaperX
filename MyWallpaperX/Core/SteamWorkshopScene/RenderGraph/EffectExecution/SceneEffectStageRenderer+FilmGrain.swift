import Metal

extension SceneEffectStageRenderer {
    static func renderFilmGrain(
        _ filmGrain: SceneFilmGrainExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        filmGrainPipeline: SceneFilmGrainPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard filmGrain.layerID == filmGrain.renderGraph.layerID,
              targets.plan.logicalTargets.isEmpty,
              let resources = masks.filmGrainEffects[filmGrain.effectKey.descriptorID],
              resources.matches(filmGrain),
              let noise = resources.noise,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: sourceTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ),
              filmGrainPipeline.encode(
                  source: targets.inputTexture,
                  noise: noise,
                  target: targets.outputTexture,
                  plan: filmGrain,
                  time: time,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }
}
