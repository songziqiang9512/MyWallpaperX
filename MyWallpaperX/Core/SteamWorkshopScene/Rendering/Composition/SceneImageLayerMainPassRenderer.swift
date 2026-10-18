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
        return SceneLayerColorBlendRenderer.draw(
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
    }
}
