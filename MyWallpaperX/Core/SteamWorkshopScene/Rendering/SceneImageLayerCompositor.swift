import Metal
import simd

struct SceneImageLayerCompositor {
    private let authoredEffectPipelines: SceneAuthoredEffectPipelineSet
    private let pipelineRepository: SceneImageEffectPipelineRepository
    private let colorBlendPipelineSlot: ScenePipelineSlot<SceneLayerColorBlendPipeline>

    init?(device: MTLDevice) {
        self.init(pipelineRepository: SceneImageEffectPipelineRepository(device: device))
    }

    init(pipelineRepository: SceneImageEffectPipelineRepository) {
        self.pipelineRepository = pipelineRepository
        authoredEffectPipelines = .init(repository: pipelineRepository)
        let device = pipelineRepository.device
        colorBlendPipelineSlot = .init {
            SceneLayerColorBlendPipeline(device: device)
        }
    }

    @discardableResult
    func draw(
        _ request: SceneImageLayerDrawRequest,
        pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        guard request.dependencyEffect.map({ $0.blendMode == 0 || $0.blendMode == 5 }) ?? true else {
            return false
        }
        let masks = request.masks
        let layerColorBlendMode = request.layer.colorBlendMode ?? 0
        guard SceneLayerColorBlendRenderer.supports(layerColorBlendMode) else { return false }
        let colorBlendPipeline = layerColorBlendMode == 0
            ? nil
            : colorBlendPipelineSlot.resolve()
        guard layerColorBlendMode == 0 || colorBlendPipeline != nil else { return false }
        let auxMask = masks.iris ?? masks.opacity
        let runtimeAuthoredPlan = request.authoredEffectPlan
            ?? request.authoredEffectChain?.singleStage
        let effectPlan = SceneEffectRuntimePlanner.plan(
            for: request.layer,
            hasIrisMask: masks.iris != nil,
            hasOpacityMask: masks.opacity != nil && masks.iris == nil,
            hasWaterMask: masks.water != nil,
            hasFoliageMask: masks.foliage != nil,
            hasWaterRippleNormal: masks.waterRippleNormal != nil,
            authoredEffectPlan: runtimeAuthoredPlan,
            blocksLegacyGaussianBlur: request.blocksLegacyGaussianBlur
        )
        guard request.authoredEffectChain != nil
            || effectPlan.skipsUnsupportedComposite == false else {
            return false
        }
        let routesOffscreen = effectPlan.offscreenPassCount > 0
            || request.requiresSourceCopy
            || request.authoredEffectChain != nil
            || layerColorBlendMode > 0
        guard !routesOffscreen
            || request.layer.contentKind != "solid"
            || request.offscreenSize != nil else {
            return false
        }
        let requestedOffscreenSize = request.resolvedOffscreenSize
        let requestedOffscreenWidth = max(
            1,
            Int((requestedOffscreenSize?.width ?? CGFloat(request.texture.width)).rounded(.up))
        )
        let requestedOffscreenHeight = max(
            1,
            Int((requestedOffscreenSize?.height ?? CGFloat(request.texture.height)).rounded(.up))
        )

        let sourceEffectInputs = request.authoredEffectChain == nil
            ? effectPlan.inputs
            : .neutral
        // 作者 `brightness` 是 layer 颜色乘数（随包 wave layer 用 3.0/4.0 做过曝发光），
        // 超过 1 的部分由 render target 精度裁剪。`contentKind == "text"` 的 layer 纹理来自
        // CoreText 栅格化，那一步已经乘过同一个 key（见 SceneTextTextureLoader），这里必须跳过。
        let brightness = request.layer.contentKind == "text"
            ? 1
            : max(0, Float(request.layer.brightness ?? 1))
        let baseTint: SIMD3<Float> = request.layer.contentKind == "solid"
            ? request.uniforms.tint
            : SIMD3(repeating: 1)
        let directUniforms = makeFragmentUniforms(
            values: request.uniforms,
            effectInputs: sourceEffectInputs,
            textureFrame: request.textureFrame,
            tint: baseTint * brightness,
            foliageMaskUVScale: masks.foliageUVScale,
            dependencyBlendMode: routesOffscreen ? nil : request.dependencyEffect?.blendMode
        )
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            var renderedTexture: MTLTexture?
            if let authoredChain = request.authoredEffectChain {
                guard let targets = pool.graphTargets(
                    for: authoredChain,
                    requestedWidth: requestedOffscreenWidth,
                    requestedHeight: requestedOffscreenHeight
                ) else {
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneAuthoredEffectChainRenderer.render(
                        sourceTexture: request.texture,
                        masks: masks,
                        targets: targets,
                        chain: authoredChain,
                        dynamicValues: request.dynamicValues,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        pipelines: authoredEffectPipelines,
                        cursorUV: request.uniforms.cursorUV,
                        pointerIsInside: request.uniforms.cursorIsInside,
                        audioSpectrum: request.audioSpectrum,
                        authoredShaderFrameInputs: request.authoredShaderFrameInputs,
                        commandBuffer: commandBuffer
                    )
                }
            } else if let authoredPlan = request.authoredEffectPlan {
                guard let targets = pool.graphTargets(
                    for: authoredPlan,
                    requestedWidth: requestedOffscreenWidth,
                    requestedHeight: requestedOffscreenHeight
                ) else {
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer -> MTLTexture? in
                    guard targets.encodeInitialHistoryClear(commandBuffer: commandBuffer) else {
                        return nil
                    }
                    switch authoredPlan.backend {
                    case .preciseGaussian:
                        guard let gaussianBlurPipeline =
                            authoredEffectPipelines.gaussianBlur else {
                            return nil
                        }
                        return SceneOffscreenEffectRenderer.renderPreciseBlur(
                            executionPlan: authoredPlan,
                            sourceTexture: request.texture,
                            waterMaskTexture: masks.water,
                            foliageMaskTexture: masks.foliage,
                            auxMaskTexture: auxMask,
                            targets: targets,
                            sourceUniforms: directUniforms,
                            pipeline: pipeline,
                            gaussianBlurPipeline: gaussianBlurPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .standardBlur(let blur):
                        guard let standardBlurPipeline =
                            authoredEffectPipelines.standardBlur else {
                            return nil
                        }
                        return SceneOffscreenEffectRenderer.renderStandardBlur(
                            sourceTexture: request.texture,
                            waterMaskTexture: masks.water,
                            foliageMaskTexture: masks.foliage,
                            auxMaskTexture: auxMask,
                            targets: targets,
                            plan: blur,
                            sourceUniforms: directUniforms,
                            pipeline: pipeline,
                            standardBlurPipeline: standardBlurPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .localContrast(let contrast):
                        guard let localContrastPipeline =
                            authoredEffectPipelines.localContrast else {
                            return nil
                        }
                        return SceneOffscreenEffectRenderer.renderLocalContrast(
                            sourceTexture: request.texture,
                            waterMaskTexture: masks.water,
                            foliageMaskTexture: masks.foliage,
                            auxMaskTexture: auxMask,
                            targets: targets,
                            plan: contrast,
                            strength: request.localContrastStrength
                                ?? contrast.staticOrFallbackStrength,
                            sourceUniforms: directUniforms,
                            pipeline: pipeline,
                            localContrastPipeline: localContrastPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .opacity(let opacity):
                        let alpha = opacity.resolvedAlpha(in: request.dynamicValues)
                        guard let opacityPipeline = authoredEffectPipelines.opacity,
                              targets.plan.logicalTargets.isEmpty,
                              SceneOffscreenEffectRenderer.captureSource(
                                  sourceTexture: request.texture,
                                  waterMaskTexture: masks.water,
                                  foliageMaskTexture: masks.foliage,
                                  auxMaskTexture: auxMask,
                                  target: targets.inputTexture,
                                  sourceUniforms: directUniforms,
                                  pipeline: pipeline,
                                  commandBuffer: commandBuffer
                              ) else {
                            return nil
                        }
                        return SceneOpacityRenderer.render(
                            alpha: alpha,
                            // 这条分支的 capture 用的是 effectPlan.inputs，遮罩已在
                            // EFFECT_OPACITY_MASK 里乘过，这里再乘一次就是双乘。
                            mask: nil,
                            maskUVScale: SIMD2(repeating: 1),
                            inputTexture: targets.inputTexture,
                            outputTexture: targets.outputTexture,
                            pipeline: opacityPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .workshopShadow(let shadow):
                        guard let workshopShadowPipeline =
                            authoredEffectPipelines.workshopShadow else {
                            return nil
                        }
                        return SceneOffscreenEffectRenderer.renderWorkshopShadow(
                            sourceTexture: request.texture,
                            waterMaskTexture: masks.water,
                            foliageMaskTexture: masks.foliage,
                            auxMaskTexture: auxMask,
                            targets: targets,
                            plan: shadow,
                            sourceUniforms: directUniforms,
                            pipeline: pipeline,
                            workshopShadowPipeline: workshopShadowPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .shake(let shake):
                        guard let resources = masks.shakeEffects[shake.effectKey.descriptorID],
                              let shakePipeline = authoredEffectPipelines.shake,
                              targets.plan.logicalTargets.isEmpty,
                              SceneOffscreenEffectRenderer.captureSource(
                                  sourceTexture: request.texture,
                                  waterMaskTexture: masks.water,
                                  foliageMaskTexture: masks.foliage,
                                  auxMaskTexture: auxMask,
                                  target: targets.inputTexture,
                                  sourceUniforms: directUniforms,
                                  pipeline: pipeline,
                                  commandBuffer: commandBuffer
                              ) else {
                            return nil
                        }
                        return SceneShakeRenderer.render(
                            plan: shake,
                            resources: resources,
                            time: directUniforms.time,
                            audioPulse: shake.audio.map {
                                SceneAudioResponse.evaluate(
                                    spectrum: request.audioSpectrum,
                                    parameters: $0
                                )
                            },
                            inputTexture: targets.inputTexture,
                            outputTexture: targets.outputTexture,
                            pipeline: shakePipeline,
                            commandBuffer: commandBuffer
                        )
                    case .waterFlow:
                        return nil
                    case .waterWaves(let waterWaves):
                        guard let waterWavesPipeline =
                            authoredEffectPipelines.waterWaves else {
                            return nil
                        }
                        return SceneWaterWavesRenderer.renderCaptured(
                            plan: waterWaves,
                            sourceTexture: request.texture,
                            masks: masks,
                            targets: targets,
                            sourceUniforms: directUniforms,
                            sourcePipeline: pipeline,
                            waterWavesPipeline: waterWavesPipeline,
                            time: directUniforms.time,
                            commandBuffer: commandBuffer
                        )
                    case .foliageSway, .waterRipple, .xRay, .blend, .tint, .transform,
                         .pulse, .godrays, .spin,
                         .proceduralNoise, .filmGrain, .lightShafts,
                         .colorKey, .workshopShiftHue, .workshopAudioBars, .workshopGradient,
                         .workshopAudioHueShift, .authoredShader:
                        return nil
                    }
                }
            } else {
                guard let textures = pool.textures(
                    width: requestedOffscreenWidth,
                    height: requestedOffscreenHeight
                ) else {
                    return false
                }
                renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                    SceneOffscreenEffectRenderer.render(
                        sourceTexture: request.texture,
                        waterMaskTexture: masks.water,
                        foliageMaskTexture: masks.foliage,
                        auxMaskTexture: auxMask,
                        offscreenPair: textures,
                        offscreenPassCount: max(effectPlan.offscreenPassCount, 1),
                        blurPlan: effectPlan.gaussianBlur,
                        bloomPlan: effectPlan.bloom,
                        gradientColorPlan: effectPlan.gradientColor,
                        waterRippleNormalPlan: effectPlan.waterRippleNormal,
                        waterRippleNormalTexture: masks.waterRippleNormal,
                        perspectiveOpacityPlan: effectPlan.perspectiveOpacity,
                        sourceUniforms: directUniforms,
                        pipeline: pipeline,
                        gaussianBlurPipeline: effectPlan.gaussianBlur == nil
                            && effectPlan.bloom == nil
                            ? nil
                            : authoredEffectPipelines.gaussianBlur,
                        bloomPipeline: effectPlan.bloom == nil
                            ? nil
                            : pipelineRepository.bloom(),
                        gradientColorPipeline: effectPlan.gradientColor == nil
                            ? nil
                            : pipelineRepository.gradientColor(),
                        waterRipplePipeline: effectPlan.waterRippleNormal == nil
                            ? nil
                            : authoredEffectPipelines.waterRipple,
                        perspectiveOpacityPipeline: effectPlan.perspectiveOpacity == nil
                            ? nil
                            : pipelineRepository.perspectiveOpacity(),
                        commandBuffer: commandBuffer
                    )
                }
            }
            guard let finalTexture = renderedTexture ?? (
                request.requiresSourceCopy
                    || request.authoredEffectPlan != nil
                    || request.authoredEffectChain != nil
                    ? nil
                    : request.texture
            ) else {
                return false
            }
            return SceneImageLayerMainPassRenderer.draw(
                texture: finalTexture,
                masks: .empty,
                mvp: request.mvp,
                uniforms: .neutral(
                    alpha: request.finalCompositeAlpha ?? 1,
                    dependencyBlendMode: request.dependencyEffect?.blendMode
                ),
                dependencyTexture: request.dependencyEffect?.texture,
                layer: request.layer,
                pipeline: pipeline,
                colorBlendPipeline: colorBlendPipeline,
                mainPass: mainPass
            )
        }
        if request.requiresSourceCopy
            || request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil
            || (routesOffscreen && request.dependencyEffect != nil) {
            return false
        }

        return SceneImageLayerMainPassRenderer.draw(
            texture: request.texture,
            masks: masks,
            mvp: request.mvp,
            uniforms: directUniforms,
            dependencyTexture: request.dependencyEffect?.texture,
            layer: request.layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            mainPass: mainPass
        )
    }
}
