import Metal

extension SceneAuthoredEffectChainRenderer {
    /// 遮罩挂在 effect 实例上（同一层可有多个 pulse 各绑一张），按 descriptorID 取；
    /// 声明了遮罩或需要 noise 却取不到贴图时整段拒绝，不静默降级。
    static func renderPulse(
        _ pulse: ScenePulseExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        dynamicValues: SceneDynamicSnapshot,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pulsePipeline: ScenePulsePipeline,
        time: Float,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let resources = masks.pulseEffects[pulse.effectKey.descriptorID],
              resources.matches(pulse),
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
              let inputs = pulseInputs(
                  plan: pulse,
                  resources: resources,
                  time: time,
                  dynamicValues: dynamicValues,
                  audioSpectrum: audioSpectrum
              ),
              pulsePipeline.encode(
                  source: targets.inputTexture,
                  noise: pulse.requiresNoiseTexture ? resources.noise : nil,
                  mask: pulse.maskTexturePath != nil ? resources.mask : nil,
                  target: targets.outputTexture,
                  inputs: inputs,
                  commandBuffer: commandBuffer
              )
        else {
            return nil
        }
        return targets.outputTexture
    }

    private static func pulseInputs(
        plan: ScenePulseExecutionPlan,
        resources: ScenePulseEffectTextures,
        time: Float,
        dynamicValues: SceneDynamicSnapshot,
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> ScenePulsePipeline.Inputs? {
        typealias Constant = ScenePulseExecutionPlan.Constant
        func scalar(_ constant: Constant) -> Float {
            Float(plan.resolvedComponents(constant, in: dynamicValues).x)
        }
        func vector3(_ constant: Constant) -> SIMD3<Float> {
            let value = plan.resolvedComponents(constant, in: dynamicValues)
            return SIMD3(Float(value.x), Float(value.y), Float(value.z))
        }
        let bounds = plan.resolvedComponents(.bounds, in: dynamicValues)
        guard bounds.x < bounds.y else { return nil }
        return ScenePulsePipeline.Inputs(
            time: time,
            speed: scalar(.speed),
            phase: scalar(.phase),
            phaseOffset: plan.shaderProfile.phaseOffset,
            amount: scalar(.amount),
            bounds: SIMD2(Float(bounds.x), Float(bounds.y)),
            noiseSpeed: scalar(.noiseSpeed),
            noiseAmount: scalar(.noiseAmount),
            noiseUVScale: plan.shaderProfile.noiseUVScale,
            power: scalar(.power),
            tintLow: vector3(.tintLow),
            tintHigh: vector3(.tintHigh),
            blendMode: plan.blendMode,
            pulseColor: plan.pulseColor,
            pulseAlpha: plan.pulseAlpha,
            saturatesOutput: plan.shaderProfile.saturatesOutput,
            maskUVScale: resources.maskUVScale,
            audioPulse: plan.audio.map {
                SceneAudioResponse.evaluate(spectrum: audioSpectrum, parameters: $0)
            }
        )
    }
}
