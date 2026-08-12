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
        textureFrame: SceneTextureUVTransform,
        tint: SIMD3<Float>,
        dependencyBlendMode: Int?
    ) -> SceneLayerFragmentUniforms {
        return SceneLayerFragmentUniforms(
            time: values.time,
            alpha: values.alpha,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            usesDependencyBlend: dependencyBlendMode == nil ? 0 : 1,
            cursorUV: values.cursorUV,
            _pad1: .zero,
            tint: SIMD4(tint.x, tint.y, tint.z, 1),
            textureFrame0: textureFrame.uniform0,
            textureFrame1: textureFrame.uniform1
        )
    }

    func sourceFragmentUniforms(
        for request: SceneImageLayerDrawRequest,
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
            textureFrame: textureFrame,
            tint: tint * brightness,
            dependencyBlendMode: routesOffscreen
                ? nil : request.dependencyEffect?.blendMode
        )
    }

    func offscreenDimensions(
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
