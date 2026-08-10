import CoreGraphics
import Metal
import simd

extension SceneImageLayerCompositor {
    var shouldDeferResolvedMaterialFrame: Bool {
        resolvedMaterialRuntime?.shouldDeferFrame == true
    }

    func invalidateResolvedMaterialRuntime(
        reason: SceneGraphExecutionResetReason
    ) {
        resolvedMaterialRuntime?.invalidate(reason: reason)
    }

    func makeFragmentUniforms(
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

    func sourceFragmentUniforms(
        for request: SceneImageLayerDrawRequest,
        effectInputs: SceneLayerEffectInputs,
        routesOffscreen: Bool
    ) -> SceneLayerFragmentUniforms? {
        guard let textureFrame = request.resolvedBaseTextureFrame() else {
            return nil
        }
        let brightness = request.layer.contentKind == "text"
            ? 1 : max(0, Float(request.layer.brightness ?? 1))
        let usesAuthoredColor = request.layer.contentKind == "image"
            || request.layer.contentKind == "solid"
        let tint = usesAuthoredColor
            ? request.uniforms.tint : SIMD3<Float>(repeating: 1)
        return makeFragmentUniforms(
            values: request.uniforms,
            effectInputs: effectInputs,
            textureFrame: textureFrame,
            tint: tint * brightness,
            foliageMaskUVScale: request.masks.foliageUVScale,
            dependencyBlendMode: routesOffscreen
                || request.suppressesLegacyEffectFallback
                ? nil : request.dependencyEffect?.blendMode
        )
    }

    func legacyOffscreenDimensions(
        for request: SceneImageLayerDrawRequest
    ) -> (width: Int, height: Int) {
        let desired = request.offscreenSize ?? CGSize(
            width: CGFloat(request.texture.width),
            height: CGFloat(request.texture.height)
        )
        return (
            max(1, Int(desired.width.rounded(.up))),
            max(1, Int(desired.height.rounded(.up)))
        )
    }
}
