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
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        var visibleUniforms = uniforms
        visibleUniforms.distanceFog = distanceFog
        return SceneLayerColorBlendRenderer.draw(
            texture: texture,
            mvp: mvp,
            uniforms: visibleUniforms,
            dependencyTexture: dependencyTexture,
            layer: layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            geometryProduct: geometryProduct,
            mainPass: mainPass
        )
    }
}
