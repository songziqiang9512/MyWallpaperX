import Metal
import simd

enum SceneImageLayerMainPassRenderer {
    static func draw(
        texture: MTLTexture,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        colorBlendPipeline: SceneLayerColorBlendPipeline?,
        distanceFog: SceneImageDistanceFogUniforms = .init(),
        geometryProduct: SceneGeometryProduct? = nil,
        terminalDepth: SceneImageLayerTerminalDepthBinding? = nil,
        terminalMaterialState: SceneMaterialRenderState? = nil,
        terminalMVP: simd_float4x4? = nil,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        if let terminalMaterialState {
            let needsDepth = terminalMaterialState.requiresDepthAttachment
            guard needsDepth == (terminalMVP != nil) else { return false }
        } else if terminalMVP != nil {
            return false
        }
        var visibleUniforms = uniforms
        visibleUniforms.distanceFog = distanceFog
        let encoded = SceneLayerColorBlendRenderer.draw(
            texture: texture,
            mvp: mainPass.rasterModelViewProjection(terminalMVP ?? mvp),
            uniforms: visibleUniforms,
            dependencyTexture: dependencyTexture,
            layer: layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            geometryProduct: geometryProduct,
            terminalDepth: terminalDepth,
            terminalMaterialState: terminalMaterialState,
            mainPass: mainPass
        )
#if DEBUG
        if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
            var source = SceneCompositionTextureObservation(texture, role: "layer-color")
            source.uv = [uniforms.textureFrame0.x, uniforms.textureFrame0.y,
                uniforms.textureFrame0.z, uniforms.textureFrame0.w,
                uniforms.textureFrame1.x, uniforms.textureFrame1.y,
                uniforms.textureFrame1.z, uniforms.textureFrame1.w]
            source.sampling = String(describing: uniforms.sourceSampling)
            trace.recordComposition(.init(kind: geometryProduct != nil ? "geometry" : layer.contentKind == "composition" ? "group" : "ordinary",
                layerID: layer.id, slot: 0, source: source, target: mainPass.compositionTarget,
                outcome: encoded ? "draw-encoded" : "failed",
                reason: encoded ? nil : "layer-draw-rejected",
                details: ["contentKind": layer.contentKind]))
            if let dependencyTexture, uniforms.usesDependencyBlend != 0 {
                let usesDependencyBinding = geometryProduct == nil && (layer.colorBlendMode ?? 0) == 0
                trace.recordComposition(.init(kind: "ordinary-dependency", layerID: layer.id, slot: 1,
                    source: .init(dependencyTexture, role: "dependency"), target: mainPass.compositionTarget,
                    access: usesDependencyBinding && encoded ? "texture-bind" : "selected",
                    outcome: usesDependencyBinding ? (encoded ? "draw-encoded" : "failed") : "prepared",
                    reason: geometryProduct != nil ? "geometry-dependency-consumption-unobserved"
                        : (layer.colorBlendMode ?? 0) != 0 ? "color-blend-slot1-is-background"
                        : encoded ? nil : "layer-draw-rejected"))
            }
        }
#endif
        return encoded
    }
}
