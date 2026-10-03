import CoreGraphics
import Foundation
import Metal
import simd

extension SceneMetalRenderer {
    func renderUtilityPlans(
        triggeredBy layerID: Int,
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
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        resolvedMaterialFrameTargetPlans: [
            Int: SceneResolvedMaterialFrameTargetPlan
        ] = [:],
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime? = nil,
        utilityExecution: SceneUtilityLayerRuntimePlanner.Execution,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        guard let planned = utilityExecution.plansByTriggerLayerID[layerID],
              let imagePipeline, let offscreenTexturePool else { return true }
        let plans = planned.filter {
            resolvedMaterialFrameTargetPlans[$0.layerID] != nil
        }
        guard !plans.isEmpty else { return true }
        // D1: only one render encoder may be active per command buffer, and a
        // utility composite must encode into the
        // main/enclosing pass while member passes are closed.
        compositionGroupRuntime?.closeAllGroupEncoders()
        let encoded = SceneUtilityPlanFrameRenderer.render(
            renderer: self,
            plans: plans,
            dependencyRuntime: dependencyRuntime,
            imageCompositor: imageCompositor,
            utilityCaptureTelemetry: utilityCaptureTelemetry,
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
            resolvedMaterialFrameTargetPlans: resolvedMaterialFrameTargetPlans,
            compositionGroupRuntime: compositionGroupRuntime,
            layersByID: layersByID
        )
        // The composite opened the main/enclosing pass; the layer loop's
        // pass bookkeeping does not track it, so close every encoder the
        // composite may have left open. Re-opening is lazy and cheap.
        mainPass.closeForOffscreen()
        compositionGroupRuntime?.closeAllGroupEncoders()
        return encoded
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
