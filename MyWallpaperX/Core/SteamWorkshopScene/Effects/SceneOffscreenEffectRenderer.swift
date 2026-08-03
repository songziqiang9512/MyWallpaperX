import Metal
import simd

enum SceneOffscreenEffectRenderer {
    static func renderPreciseBlur(
        executionPlan: SceneAuthoredEffectExecutionPlan,
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let effect = executionPlan.renderGraph.effects.first,
              case .preciseGaussian(let plan) = executionPlan.backend,
              captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: waterMaskTexture,
                  foliageMaskTexture: foliageMaskTexture,
                  auxMaskTexture: auxMaskTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        let horizontalStep = plan.horizontalStep
            * plan.sampleResolutionScale / Float(sourceTexture.width)
        let verticalStep = plan.verticalStep
            * plan.sampleResolutionScale / Float(sourceTexture.height)
        let result = SceneGraphNodeScheduler.encode(
            graph: executionPlan.renderGraph,
            targets: targets,
            commandBuffer: commandBuffer
        ) { node, textures in
            guard let targetIdentity = node.target,
                  let target = textures.texture(for: targetIdentity) else {
                return false
            }
            switch node.materialOrdinal {
            case 0:
                guard executionPlan.acceptsPreciseBlurHorizontalBindings(node.bindings, effectInput: effect.input),
                      let input = textures.texture(for: effect.input) else {
                    return false
                }
                return gaussianBlurPipeline.encode(
                    source: input,
                    target: target,
                    step: SIMD2(horizontalStep, 0),
                    kernel: plan.kernel,
                    commandBuffer: commandBuffer
                )
            case 1:
                guard let sourceIdentity = node.bindings.first(where: { $0.slot == 0 })?.texture,
                      let source = textures.texture(for: sourceIdentity) else {
                    return false
                }
                return gaussianBlurPipeline.encode(
                    source: source,
                    target: target,
                    step: SIMD2(0, verticalStep),
                    kernel: plan.kernel,
                    commandBuffer: commandBuffer
                )
            default:
                return false
            }
        }
        guard case .success = result else {
            return nil
        }
        return targets.outputTexture
    }

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
            waterMaskTexture: masks.water,
            foliageMaskTexture: masks.foliage,
            auxMaskTexture: masks.iris ?? masks.opacity,
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

    static func renderLocalContrast(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        plan: SceneLocalContrastPlan,
        strength: Float,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        localContrastPipeline: SceneLocalContrastPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            target: targets.inputTexture,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return SceneLocalContrastRenderer.render(
            targets: targets,
            quarterAIdentity: plan.firstQuarterTarget,
            quarterBIdentity: plan.secondQuarterTarget,
            strength: strength,
            pipeline: localContrastPipeline,
            commandBuffer: commandBuffer
        )
    }

    static func renderWorkshopShadow(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        plan: SceneWorkshopShadowExecutionPlan,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        workshopShadowPipeline: SceneWorkshopShadowPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard targets.plan.logicalTargets.isEmpty,
              captureSource(
                  sourceTexture: sourceTexture,
                  waterMaskTexture: waterMaskTexture,
                  foliageMaskTexture: foliageMaskTexture,
                  auxMaskTexture: auxMaskTexture,
                  target: targets.inputTexture,
                  sourceUniforms: sourceUniforms,
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ) else {
            return nil
        }
        return SceneWorkshopShadowRenderer.render(
            plan: plan,
            inputTexture: targets.inputTexture,
            outputTexture: targets.outputTexture,
            pipeline: workshopShadowPipeline,
            commandBuffer: commandBuffer
        )
    }

}
