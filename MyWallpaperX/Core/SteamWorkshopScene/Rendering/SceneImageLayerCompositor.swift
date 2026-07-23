import Metal
import simd

struct SceneImageLayerMasks {
    let iris: MTLTexture?
    let opacity: MTLTexture?
    let water: MTLTexture?
    let foliage: MTLTexture?
    let foliageUVScale: SIMD2<Float>
    let waterRippleNormal: MTLTexture?
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let tint: SIMD3<Float>

    init(
        time: Float,
        alpha: Float,
        cursorUV: SIMD2<Float>,
        tint: SIMD3<Float> = SIMD3(repeating: 1)
    ) {
        self.time = time
        self.alpha = alpha
        self.cursorUV = cursorUV
        self.tint = tint
    }
}

struct SceneDependencyEffectInput {
    let texture: MTLTexture
    let blendMode: Int
}

struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    let masks: SceneImageLayerMasks
    let textureFrame: SceneTextureUVTransform
    let mvp: simd_float4x4
    let uniforms: SceneImageLayerUniformValues
    let offscreenTexturePool: SceneOffscreenTexturePool?
    let offscreenSize: CGSize?
    let requiresSourceCopy: Bool
    let finalCompositeAlpha: Float?
    let dependencyEffect: SceneDependencyEffectInput?
    let authoredEffectPlan: SceneAuthoredEffectExecutionPlan?
    let blocksLegacyGaussianBlur: Bool
    var authoredEffectChain: SceneAuthoredEffectExecutionChain? = nil
    var dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0)
    var localContrastStrength: Float? = nil
}

struct SceneImageLayerCompositor {
    private let gaussianBlurPipeline: SceneGaussianBlurPipeline
    private let standardBlurPipeline: SceneStandardBlurPipeline
    private let localContrastPipeline: SceneLocalContrastPipeline
    private let opacityPipeline: SceneOpacityPipeline
    private let workshopShadowPipeline: SceneWorkshopShadowPipeline
    private let bloomPipeline: SceneBloomPipeline
    private let gradientColorPipeline: SceneGradientColorPipeline
    private let waterRipplePipeline: SceneWaterRipplePipeline
    private let perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline
    private let additivePipeline: SceneImageLayerPipeline

    init?(device: MTLDevice) {
        guard let gaussianBlurPipeline = SceneGaussianBlurPipeline(device: device),
              let standardBlurPipeline = SceneStandardBlurPipeline(device: device),
              let localContrastPipeline = SceneLocalContrastPipeline(device: device),
              let opacityPipeline = SceneOpacityPipeline(device: device),
              let workshopShadowPipeline = SceneWorkshopShadowPipeline(device: device),
              let bloomPipeline = SceneBloomPipeline(device: device),
              let gradientColorPipeline = SceneGradientColorPipeline(device: device),
              let waterRipplePipeline = SceneWaterRipplePipeline(device: device),
              let perspectiveOpacityPipeline = ScenePerspectiveOpacityPipeline(device: device),
              let additivePipeline = SceneImageLayerPipeline(device: device, blendMode: .additive) else {
            return nil
        }
        self.gaussianBlurPipeline = gaussianBlurPipeline
        self.standardBlurPipeline = standardBlurPipeline
        self.localContrastPipeline = localContrastPipeline
        self.opacityPipeline = opacityPipeline
        self.workshopShadowPipeline = workshopShadowPipeline
        self.bloomPipeline = bloomPipeline
        self.gradientColorPipeline = gradientColorPipeline
        self.waterRipplePipeline = waterRipplePipeline
        self.perspectiveOpacityPipeline = perspectiveOpacityPipeline
        self.additivePipeline = additivePipeline
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
        guard effectPlan.skipsUnsupportedComposite == false else { return false }
        let routesOffscreen = effectPlan.offscreenPassCount > 0
            || request.requiresSourceCopy
            || request.authoredEffectChain != nil
        let requestedOffscreenWidth = max(
            1,
            Int((request.offscreenSize?.width ?? CGFloat(request.texture.width)).rounded(.up))
        )
        let requestedOffscreenHeight = max(
            1,
            Int((request.offscreenSize?.height ?? CGFloat(request.texture.height)).rounded(.up))
        )

        let directUniforms = makeFragmentUniforms(
            values: request.uniforms,
            effectInputs: effectPlan.inputs,
            textureFrame: request.textureFrame,
            tint: request.layer.contentKind == "solid"
                ? request.uniforms.tint
                : SIMD3(repeating: 1),
            foliageMaskUVScale: masks.foliageUVScale,
            dependencyBlendMode: routesOffscreen ? nil : request.dependencyEffect?.blendMode
        )
        if routesOffscreen,
           let pool = request.offscreenTexturePool {
            let renderedTexture: MTLTexture?
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
                        gaussianBlurPipeline: gaussianBlurPipeline,
                        standardBlurPipeline: standardBlurPipeline,
                        localContrastPipeline: localContrastPipeline,
                        opacityPipeline: opacityPipeline,
                        workshopShadowPipeline: workshopShadowPipeline,
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
                        guard targets.plan.logicalTargets.isEmpty,
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
                            inputTexture: targets.inputTexture,
                            outputTexture: targets.outputTexture,
                            pipeline: opacityPipeline,
                            commandBuffer: commandBuffer
                        )
                    case .workshopShadow(let shadow):
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
                        gaussianBlurPipeline: gaussianBlurPipeline,
                        bloomPipeline: bloomPipeline,
                        gradientColorPipeline: gradientColorPipeline,
                        waterRipplePipeline: waterRipplePipeline,
                        perspectiveOpacityPipeline: perspectiveOpacityPipeline,
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
            return drawToMainPass(
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
                mainPass: mainPass
            )
        }
        if request.requiresSourceCopy
            || request.authoredEffectPlan != nil
            || request.authoredEffectChain != nil
            || (routesOffscreen && request.dependencyEffect != nil) {
            return false
        }

        return drawToMainPass(
            texture: request.texture,
            masks: masks,
            mvp: request.mvp,
            uniforms: directUniforms,
            dependencyTexture: request.dependencyEffect?.texture,
            layer: request.layer,
            pipeline: pipeline,
            mainPass: mainPass
        )
    }

    private func drawToMainPass(
        texture: MTLTexture,
        masks: SceneImageLayerMasks,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        guard let encoder = mainPass.encoder() else { return false }
        let compositePipeline = layer.colorBlendMode == 9 ? additivePipeline : pipeline
        compositePipeline.bind(encoder: encoder)
        compositePipeline.drawLayer(
            texture: texture,
            shakeMaskTexture: nil,
            waterMaskTexture: masks.water,
            foliageMaskTexture: masks.foliage,
            auxMaskTexture: masks.iris ?? masks.opacity,
            dependencyTexture: dependencyTexture,
            mvp: mvp,
            uniforms: uniforms,
            encoder: encoder
        )
        return true
    }

    private func makeFragmentUniforms(
        values: SceneImageLayerUniformValues,
        effectInputs: SceneLayerEffectInputs,
        textureFrame: SceneTextureUVTransform,
        tint: SIMD3<Float>,
        foliageMaskUVScale: SIMD2<Float>,
        dependencyBlendMode: Int?
    ) -> SceneLayerFragmentUniforms {
        var flags = effectInputs.flags
        if dependencyBlendMode != nil {
            flags.insert(.dependencyBlend)
        }
        return SceneLayerFragmentUniforms(
            time: values.time,
            alpha: values.alpha,
            effectFlags: flags.rawValue,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            cursorUV: values.cursorUV,
            _pad1: .zero,
            tint: SIMD4(tint.x, tint.y, tint.z, 1),
            effectParams0: effectInputs.params0,
            effectParams1: effectInputs.params1,
            effectParams2: effectInputs.params2,
            effectParams3: effectInputs.params3,
            effectParams4: effectInputs.params4,
            effectParams5: SIMD4(foliageMaskUVScale.x, foliageMaskUVScale.y, 0, 0),
            textureFrame0: textureFrame.uniform0,
            textureFrame1: textureFrame.uniform1
        )
    }
}

extension SceneImageLayerMasks {
    static let empty = SceneImageLayerMasks(
        iris: nil,
        opacity: nil,
        water: nil,
        foliage: nil,
        foliageUVScale: SIMD2(repeating: 1),
        waterRippleNormal: nil
    )
}
