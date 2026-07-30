import Metal

enum SceneShakeRenderer {
    static func render(
        plan: SceneShakeExecutionPlan,
        resources: SceneShakeEffectTextures,
        time: Float,
        audioPulse: Float?,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneShakePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let arguments = resources.resolvedArguments(for: plan),
              pipeline.encode(
                  source: inputTexture,
                  flowMap: arguments.flow.texture,
                  phaseMap: arguments.phase?.texture,
                  flowUVScale: arguments.flowUVScale,
                  maskMap: arguments.mask?.texture,
                  maskUVScale: arguments.maskUVScale,
                  flowSampling: arguments.flow.sampling,
                  phaseSampling: arguments.phase?.sampling ?? .linearClamp,
                  maskSampling: arguments.mask?.sampling ?? .linearClamp,
                  target: outputTexture,
                  plan: plan,
                  time: time,
                  audioPulse: audioPulse,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return outputTexture
    }
}
