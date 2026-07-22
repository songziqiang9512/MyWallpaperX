import Metal
import simd

struct SceneImageLayerMasks {
    let iris: MTLTexture?
    let opacity: MTLTexture?
    let water: MTLTexture?
    let foliage: MTLTexture?
    let waterRippleNormal: MTLTexture?
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
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
}

struct SceneImageLayerCompositor {
    private let gaussianBlurPipeline: SceneGaussianBlurPipeline
    private let bloomPipeline: SceneBloomPipeline
    private let waterRipplePipeline: SceneWaterRipplePipeline
    private let perspectiveOpacityPipeline: ScenePerspectiveOpacityPipeline
    private let additivePipeline: SceneImageLayerPipeline

    init?(device: MTLDevice) {
        guard let gaussianBlurPipeline = SceneGaussianBlurPipeline(device: device),
              let bloomPipeline = SceneBloomPipeline(device: device),
              let waterRipplePipeline = SceneWaterRipplePipeline(device: device),
              let perspectiveOpacityPipeline = ScenePerspectiveOpacityPipeline(device: device),
              let additivePipeline = SceneImageLayerPipeline(device: device, blendMode: .additive) else {
            return nil
        }
        self.gaussianBlurPipeline = gaussianBlurPipeline
        self.bloomPipeline = bloomPipeline
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
        let masks = request.masks
        let auxMask = masks.iris ?? masks.opacity
        let effectPlan = SceneEffectRuntimePlanner.plan(
            for: request.layer,
            hasIrisMask: masks.iris != nil,
            hasOpacityMask: masks.opacity != nil && masks.iris == nil,
            hasWaterMask: masks.water != nil,
            hasFoliageMask: masks.foliage != nil,
            hasWaterRippleNormal: masks.waterRippleNormal != nil
        )
        guard effectPlan.skipsUnsupportedComposite == false else { return false }

        let directUniforms = makeFragmentUniforms(
            values: request.uniforms,
            effectInputs: effectPlan.inputs,
            textureFrame: request.textureFrame,
            tint: request.layer.contentKind == "solid"
                ? SIMD3(request.layer.colorRGB ?? [], fill: 1)
                : SIMD3(repeating: 1)
        )
        if effectPlan.offscreenPassCount > 0 || request.requiresSourceCopy,
           let pool = request.offscreenTexturePool,
           let textures = request.offscreenSize.map({ size in
               pool.textures(width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)))
           }) ?? pool.textures(for: request.texture) {
            let renderedTexture = mainPass.encodeOffscreen { commandBuffer in
                SceneOffscreenEffectRenderer.render(
                    sourceTexture: request.texture,
                    waterMaskTexture: masks.water,
                    foliageMaskTexture: masks.foliage,
                    auxMaskTexture: auxMask,
                    offscreenPair: textures,
                    offscreenPassCount: max(effectPlan.offscreenPassCount, 1),
                    blurPlan: effectPlan.gaussianBlur,
                    bloomPlan: effectPlan.bloom,
                    waterRippleNormalPlan: effectPlan.waterRippleNormal,
                    waterRippleNormalTexture: masks.waterRippleNormal,
                    perspectiveOpacityPlan: effectPlan.perspectiveOpacity,
                    sourceUniforms: directUniforms,
                    pipeline: pipeline,
                    gaussianBlurPipeline: gaussianBlurPipeline,
                    bloomPipeline: bloomPipeline,
                    waterRipplePipeline: waterRipplePipeline,
                    perspectiveOpacityPipeline: perspectiveOpacityPipeline,
                    commandBuffer: commandBuffer
                )
            }
            guard let finalTexture = renderedTexture ?? (request.requiresSourceCopy ? nil : request.texture) else {
                return false
            }
            return drawToMainPass(
                texture: finalTexture,
                masks: .empty,
                mvp: request.mvp,
                uniforms: .neutral(alpha: request.finalCompositeAlpha ?? 1),
                layer: request.layer,
                pipeline: pipeline,
                mainPass: mainPass
            )
        }
        if request.requiresSourceCopy { return false }

        return drawToMainPass(
            texture: request.texture,
            masks: masks,
            mvp: request.mvp,
            uniforms: directUniforms,
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
        tint: SIMD3<Float>
    ) -> SceneLayerFragmentUniforms {
        SceneLayerFragmentUniforms(
            time: values.time,
            alpha: values.alpha,
            effectFlags: effectInputs.flags.rawValue,
            _pad0: 0,
            cursorUV: values.cursorUV,
            _pad1: .zero,
            tint: SIMD4(tint.x, tint.y, tint.z, 1),
            effectParams0: effectInputs.params0,
            effectParams1: effectInputs.params1,
            effectParams2: effectInputs.params2,
            effectParams3: effectInputs.params3,
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
        waterRippleNormal: nil
    )
}
