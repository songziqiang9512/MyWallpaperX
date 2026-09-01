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
        dependencyBlendMode: Int?,
        sourceSampling: SceneTextureSampling = .linearClamp
    ) -> SceneLayerFragmentUniforms {
        return SceneLayerFragmentUniforms(
            time: values.time,
            alpha: values.alpha,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            usesDependencyBlend: dependencyBlendMode == nil ? 0 : 1,
            cursorUV: values.cursorUV,
            sourceSampling: SIMD2(sourceSampling.imageLayerUniformMode, 0),
            tint: SIMD4(tint.x, tint.y, tint.z, 1),
            textureFrame0: textureFrame.uniform0,
            textureFrame1: textureFrame.uniform1
        )
    }

    func sourceFragmentUniforms(
        for request: SceneImageLayerDrawRequest,
        routesOffscreen: Bool
    ) -> SceneLayerFragmentUniforms? {
        guard let sourceSample = request.resolvedBaseTextureSample() else {
            return nil
        }
        return sourceFragmentUniforms(
            values: request.uniforms,
            layer: request.layer,
            sourceSample: sourceSample,
            routesOffscreen: routesOffscreen,
            dependencyBlendMode: request.dependencyEffect?.blendMode
        )
    }

    func sourceFragmentUniforms(
        values: SceneImageLayerUniformValues,
        layer: SceneRenderDescriptor.Layer,
        sourceSample: SceneBaseImageTextureSample,
        routesOffscreen: Bool,
        dependencyBlendMode: Int?
    ) -> SceneLayerFragmentUniforms {
        let brightness = layer.contentKind == "text"
            ? 1 : max(0, Float(layer.brightness ?? 1))
        let usesAuthoredColor = layer.contentKind == "image"
            || layer.contentKind == "solid"
        let tint = usesAuthoredColor
            ? values.tint : SIMD3<Float>(repeating: 1)
        return makeFragmentUniforms(
            values: values,
            textureFrame: sourceSample.textureFrame,
            tint: tint * brightness,
            dependencyBlendMode: routesOffscreen
                ? nil : dependencyBlendMode,
            sourceSampling: sourceSample.sampling
        )
    }

    func offscreenDimensions(
        for request: SceneImageLayerDrawRequest
    ) -> (width: Int, height: Int)? {
        guard let desired = request.effectSourceExtent?.pixelSize else {
            return nil
        }
        return (
            max(1, Int(desired.width.rounded(.up))),
            max(1, Int(desired.height.rounded(.up)))
        )
    }
}
