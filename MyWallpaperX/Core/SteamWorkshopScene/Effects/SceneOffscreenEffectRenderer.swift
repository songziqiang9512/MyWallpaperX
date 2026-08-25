import Metal
import simd

enum SceneOffscreenEffectRenderer {
    static func renderStandardBlur(
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        plan: SceneStandardBlurPlan,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        standardBlurPipeline: SceneStandardBlurPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let combineMask = masks.standardBlurEffects[plan.effectDescriptorID]
        let intermediates = targets.plan.logicalTargets.sorted {
            $0.lifetime.firstWriteNodeIndex < $1.lifetime.firstWriteNodeIndex
        }
        guard intermediates.count == 2,
              plan.maskTexturePath == nil || combineMask?.matches(plan) == true,
              let quarterA = targets.texture(for: intermediates[0].identity),
              let quarterB = targets.texture(for: intermediates[1].identity),
              captureSource(
            sourceTexture: sourceTexture,
            target: targets.inputTexture,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        let maskCandidate = plan.maskTexturePath == nil
            ? nil
            : combineMask?.maskCandidate
        let maskUVScale = maskCandidate?.axisAlignedMappedUVScale(
            expectedPurpose: .mask
        )
        guard maskCandidate == nil || maskUVScale != nil else {
            return nil
        }
        return SceneStandardBlurRenderer.render(
            plan: plan,
            inputTexture: targets.inputTexture,
            quarterA: quarterA,
            quarterB: quarterB,
            outputTexture: targets.outputTexture,
            maskTexture: maskCandidate?.texture,
            maskUVScale: maskUVScale ?? SIMD2(repeating: 1),
            maskSampling: maskCandidate?.sampling ?? .linearClamp,
            pipeline: standardBlurPipeline,
            commandBuffer: commandBuffer
        )
    }

}
