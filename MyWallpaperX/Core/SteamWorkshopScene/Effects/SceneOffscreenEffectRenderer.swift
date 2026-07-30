import Metal
import simd

enum SceneOffscreenEffectRenderer {
    static func render(
        sourceTexture: MTLTexture,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        offscreenPair: SceneOffscreenTexturePool.Pair,
        offscreenPassCount: Int,
        blurPlan: SceneGaussianBlurPlan?,
        bloomPlan: SceneBloomPlan?,
        gradientColorPlan: SceneGradientColorPlan?,
        waterRippleNormalPlan: SceneWaterRippleNormalPlan?,
        waterRippleNormalTexture: MTLTexture?,
        perspectiveOpacityPlan: ScenePerspectiveOpacityPlan?,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        gaussianBlurPipeline: SceneGaussianBlurPipeline?,
        bloomPipeline: SceneBloomPipeline?,
        gradientColorPipeline: SceneGradientColorPipeline?,
        waterRipplePipeline: SceneWaterRipplePipeline?,
        perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline?,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard captureSource(
            sourceTexture: sourceTexture,
            waterMaskTexture: waterMaskTexture,
            foliageMaskTexture: foliageMaskTexture,
            auxMaskTexture: auxMaskTexture,
            target: offscreenPair.primary,
            sourceUniforms: sourceUniforms,
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }

        if let gradientColorPlan {
            guard let gradientColorPipeline else { return nil }
            guard gradientColorPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                plan: gradientColorPlan,
                time: sourceUniforms.time,
                commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return offscreenPair.secondary
        }

        var effectSource = offscreenPair.primary
        var perspectiveTarget = offscreenPair.secondary
        if let waterRippleNormalPlan, let waterRippleNormalTexture {
            guard let waterRipplePipeline else { return nil }
            guard waterRipplePipeline.encode(
               source: offscreenPair.primary,
               normalMap: waterRippleNormalTexture,
               target: offscreenPair.secondary,
               plan: waterRippleNormalPlan,
               time: sourceUniforms.time,
               commandBuffer: commandBuffer
            ) else {
                return nil
            }
            effectSource = offscreenPair.secondary
            perspectiveTarget = offscreenPair.tertiary
        }

        if let perspectiveOpacityPlan, let auxMaskTexture {
            guard let perspectiveOpacityPipeline else { return nil }
            guard perspectiveOpacityPipeline.encode(
               source: effectSource,
               opacityMask: auxMaskTexture,
               target: perspectiveTarget,
               plan: perspectiveOpacityPlan,
               commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return perspectiveTarget
        }

        if effectSource === offscreenPair.secondary {
            return effectSource
        }

        if let bloomPlan {
            guard let bloomPipeline, let gaussianBlurPipeline else { return nil }
            return renderBloom(
                plan: bloomPlan,
                textures: offscreenPair,
                gaussianBlurPipeline: gaussianBlurPipeline,
                bloomPipeline: bloomPipeline,
                commandBuffer: commandBuffer
            )
        }

        if let blurPlan {
            guard let gaussianBlurPipeline else { return nil }
            let horizontalStep = blurPlan.horizontalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.width)
            let verticalStep = blurPlan.verticalStep
                * blurPlan.sampleResolutionScale / Float(offscreenPair.primary.height)
            guard gaussianBlurPipeline.encode(
                source: offscreenPair.primary,
                target: offscreenPair.secondary,
                step: SIMD2(horizontalStep, 0),
                commandBuffer: commandBuffer
            ), gaussianBlurPipeline.encode(
                source: offscreenPair.secondary,
                target: offscreenPair.primary,
                step: SIMD2(0, verticalStep),
                commandBuffer: commandBuffer
            ) else {
                return nil
            }
            return offscreenPair.primary
        }

        guard offscreenPassCount > 1 else { return offscreenPair.primary }
        guard let effectEncoder = beginEncoder(
                commandBuffer: commandBuffer,
                target: offscreenPair.secondary
              ) else {
            return nil
        }
        pipeline.bind(encoder: effectEncoder)
        pipeline.drawLayer(
            texture: offscreenPair.primary,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: fullTargetMVP,
            uniforms: neutralUniforms,
            encoder: effectEncoder
        )
        effectEncoder.endEncoding()
        return offscreenPair.secondary
    }

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
        return SceneStandardBlurRenderer.render(
            plan: plan,
            inputTexture: targets.inputTexture,
            quarterA: quarterA,
            quarterB: quarterB,
            outputTexture: targets.outputTexture,
            maskTexture: combineMask?.mask,
            maskUVScale: combineMask?.maskUVScale ?? SIMD2(repeating: 1),
            maskSampling: combineMask?.maskSampling ?? .linearClamp,
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

    private static func renderBloom(
        plan: SceneBloomPlan,
        textures: SceneOffscreenTexturePool.Pair,
        gaussianBlurPipeline: SceneGaussianBlurPipeline,
        bloomPipeline: SceneBloomPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let horizontalStep = SIMD2(plan.radius / Float(textures.secondary.width), 0)
        let verticalStep = SIMD2(0, plan.radius / Float(textures.secondary.height))
        guard bloomPipeline.encodeThreshold(
            source: textures.primary,
            target: textures.secondary,
            plan: plan,
            commandBuffer: commandBuffer
        ), gaussianBlurPipeline.encode(
            source: textures.secondary,
            target: textures.tertiary,
            step: horizontalStep,
            commandBuffer: commandBuffer
        ), gaussianBlurPipeline.encode(
            source: textures.tertiary,
            target: textures.secondary,
            step: verticalStep,
            commandBuffer: commandBuffer
        ), bloomPipeline.encodeComposite(
            source: textures.primary,
            bloom: textures.secondary,
            target: textures.tertiary,
            plan: plan,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        return textures.tertiary
    }

}
