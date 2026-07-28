import Metal
import simd

enum SceneCursorRippleRenderer {
    static func renderCaptured(
        plan: SceneCursorRippleExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        cursorRipplePipeline: SceneCursorRipplePipeline,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let buffer1 = framebuffer(plan, name: "_rt_EightBuffer1")
        let buffer2 = framebuffer(plan, name: "_rt_EightBuffer2")
        guard let resources = masks.cursorRippleEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
              let intermediate = targets.texture(for: buffer1),
              let history = targets.texture(for: buffer2),
              targets.plan.logicalTargets.count == 2,
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
              cursorRipplePipeline.encode(
                  history: history,
                  intermediate: intermediate,
                  source: targets.inputTexture,
                  output: targets.outputTexture,
                  mask: resources.mask,
                  maskUVScale: resources.maskUVScale,
                  plan: plan,
                  currentCursorUV: currentCursorUV,
                  previousCursorUV: previousCursorUV,
                  pointerIsInside: pointerIsInside,
                  previousPointerIsInside: previousPointerIsInside,
                  frameTime: frameTime,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return targets.outputTexture
    }

    private static func framebuffer(
        _ plan: SceneCursorRippleExecutionPlan,
        name: String
    ) -> SceneAuthoredEffectRenderPlan.TextureIdentity {
        .init(
            kind: .framebuffer,
            layerID: plan.layerID,
            effect: plan.effectKey,
            name: name
        )
    }
}
