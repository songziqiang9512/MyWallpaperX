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
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        SceneLayerColorBlendRenderer.draw(
            texture: texture,
            mvp: mvp,
            uniforms: uniforms,
            dependencyTexture: dependencyTexture,
            layer: layer,
            pipeline: pipeline,
            colorBlendPipeline: colorBlendPipeline,
            mainPass: mainPass
        )
    }
}
