import CoreGraphics
import Metal
import simd

enum SceneUtilityLayerRenderer {
    @discardableResult
    static func draw(
        layer: SceneRenderDescriptor.Layer,
        plan: SceneUtilityLayerRuntimePlan,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        time: Float,
        finalCompositeAlpha: Float,
        authoredEffectPlan: SceneAuthoredEffectExecutionPlan?,
        blocksLegacyGaussianBlur: Bool,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        offscreenTexturePool: SceneOffscreenTexturePool,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        guard plan.shouldCapture,
              let geometry = SceneCaptureGeometryResolver.resolve(
                  kind: plan.kind,
                  layerMVP: layerMVP,
                  viewportSize: viewportSize
              ) else {
            return false
        }
        return mainPass.withReadableTarget { sourceTexture, _ in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: sourceTexture,
                    masks: .empty,
                    textureFrame: geometry.sourceUV,
                    mvp: geometry.outputMVP,
                    uniforms: SceneImageLayerUniformValues(
                        time: time,
                        alpha: 1,
                        cursorUV: .zero
                    ),
                    offscreenTexturePool: offscreenTexturePool,
                    offscreenSize: geometry.pixelSize,
                    requiresSourceCopy: true,
                    finalCompositeAlpha: finalCompositeAlpha,
                    dependencyEffect: nil,
                    authoredEffectPlan: authoredEffectPlan,
                    blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? false
    }
}
