import CoreGraphics
import Foundation
import Metal
import simd

extension SceneMetalRenderer {
    func renderUtilityPlans(
        triggeredBy layerID: Int,
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        effectExecutionTrace: SceneEffectExecutionFrameTrace,
        resolvedMaterialFrameTargetPlans: [
            Int: SceneResolvedMaterialFrameTargetPlan
        ] = [:]
    ) {
        guard let planned = utilityPlansByTriggerLayerID[layerID],
              let imagePipeline, let offscreenTexturePool else { return }
        let plans = planned.filter {
            resolvedMaterialFrameTargetPlans[$0.layerID] != nil
        }
        guard !plans.isEmpty else { return }
        SceneUtilityPlanFrameRenderer.render(
            renderer: self,
            plans: plans,
            dependencyRuntime: dependencyRuntime,
            imageCompositor: imageCompositor,
            utilityCaptureTelemetry: utilityCaptureTelemetry,
            effectTextures: effectTextures,
            imagePipeline: imagePipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            viewportSize: viewportSize,
            time: time,
            mainPass: mainPass,
            commandBuffer: commandBuffer,
            effectExecutionTrace: effectExecutionTrace,
            resolvedMaterialFrameTargetPlans: resolvedMaterialFrameTargetPlans
        )
    }

    static func effectExecutionOrigin(
        for contentKind: String
    ) -> SceneEffectExecutionOrigin {
        switch contentKind {
        case "solid": .solid
        case "text": .text
        default: .image
        }
    }
}
