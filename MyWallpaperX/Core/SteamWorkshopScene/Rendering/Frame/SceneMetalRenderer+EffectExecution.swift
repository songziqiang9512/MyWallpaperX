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
        // D1 嵌套组由内向外准备：同一 trigger 可能同时承载内层与外层组
        // plan（内层组位于 renderOrder 末尾时，内层最后成员即外层最后
        // 成员）。utilityPlansByTriggerLayerID 按 Dictionary 哈希序构建，
        // 顺序不确定；必须按成员集合大小升序（更小的内层组先合成），
        // 外层 composite 才恒在其全部嵌套内层 composite 之后读取自身
        // target。键互异（嵌套组内层集合严格小于外层；兄弟组成员集不
        // 相交、不可能共享 trigger），排序结果确定。legacy plan 无组
        // 成员，落在最后，其顺序与本排序无关。
        let orderedPlans = plans.sorted {
            ($0.isolatedGroupMembers?.count ?? Int.max)
                < ($1.isolatedGroupMembers?.count ?? Int.max)
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
