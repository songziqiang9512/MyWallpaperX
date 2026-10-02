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
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime? = nil
    ) -> Bool {
        guard let planned = utilityPlansByTriggerLayerID[layerID],
              let imagePipeline, let offscreenTexturePool else { return true }
        let plans = planned.filter {
            resolvedMaterialFrameTargetPlans[$0.layerID] != nil
        }
        guard !plans.isEmpty else { return true }
        // A childless capture inside a group executes before its enclosing
        // group at a shared trigger, just like a smaller nested group.
        let orderedPlans = plans.sorted {
            ($0.isolatedGroupMembers?.count ?? 0)
                < ($1.isolatedGroupMembers?.count ?? 0)
        }
        // D1: only one render encoder may be active per command buffer, and a
        // utility composite (legacy capture or group) must encode into the
        // main/enclosing pass while member passes are closed.
        compositionGroupRuntime?.closeAllGroupEncoders()
        let encoded = SceneUtilityPlanFrameRenderer.render(
            renderer: self,
            plans: orderedPlans,
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
            compositionGroupRuntime: compositionGroupRuntime
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
