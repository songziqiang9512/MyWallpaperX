import Foundation
import Metal
import simd

struct SceneMetalRendererFrameWorldProjection {
    let descriptor: SceneRenderDescriptor
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let orderedLayers: [SceneRenderDescriptor.Layer]
    let dynamicLayerIDs: Set<Int>
    let lightLayerIDs: [Int]
    let worldFrames: [Int: simd_float4x4]
    let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
    let preparationLayers: [SceneRenderDescriptor.Layer]?
}

extension SceneMetalRenderer {
    func resolveFrameWorldProjection(
        layerTopology: SceneScriptLayerTopologySnapshot?,
        dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot
    ) -> SceneMetalRendererFrameWorldProjection {
        let descriptor: SceneRenderDescriptor
        let layersByID: [Int: SceneRenderDescriptor.Layer]
        let staticWorldFrames: [Int: simd_float4x4]
        let orderedLayers: [SceneRenderDescriptor.Layer]
        let dynamicLayerIDs: Set<Int>
        let lightLayerIDs: [Int]
        let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
        let preparationLayers: [SceneRenderDescriptor.Layer]?
        if let layerTopology,
           !layerTopology.dynamicLayers.isEmpty
                || layerTopology.renderOrderLayerIDs
                    != renderDescriptor.renderOrderLayerIDs
                || !layerTopology.destroyedAuthoredLayerIDs.isEmpty {
            let projection = dynamicLayerTopologyCache.resolve(
                baseDescriptor: renderDescriptor,
                topology: layerTopology,
                dependencyRuntime: dependencyRuntime,
                resolvedMaterialLayerIDs:
                    imageCompositor.resolvedMaterialRuntime?.executionLayerIDs ?? []
            )
            descriptor = projection.descriptor
            layersByID = projection.layersByID
            staticWorldFrames = projection.staticWorldFrames
            orderedLayers = projection.orderedLayers
            dynamicLayerIDs = projection.dynamicLayerIDs
            lightLayerIDs = projection.lightLayerIDs
            utilityExecution = projection.utilityExecution
            preparationLayers = projection.preparationLayers
        } else {
            descriptor = renderDescriptor
            layersByID = self.layersByID
            staticWorldFrames = worldFramesByLayerID
            orderedLayers = authoredLayers
            dynamicLayerIDs = []
            lightLayerIDs = self.lightLayerIDs
            utilityExecution = self.utilityExecution
            preparationLayers = resolvedMaterialPreparationLayers
        }
        return SceneMetalRendererFrameWorldProjection(
            descriptor: descriptor,
            layersByID: layersByID,
            orderedLayers: orderedLayers,
            dynamicLayerIDs: dynamicLayerIDs,
            lightLayerIDs: lightLayerIDs,
            worldFrames: SceneLayerDynamicWorldFrameResolver.resolve(
                descriptor: descriptor,
                byID: layersByID,
                snapshot: dynamicValues,
                staticFrames: staticWorldFrames,
                dynamicLayerIDs: dynamicLayerIDs,
                puppetAttachmentFrames: puppetAttachmentFrames
            ),
            utilityExecution: utilityExecution,
            preparationLayers: preparationLayers
        )
    }

#if DEBUG
    func reportDynamicLayerRenderEvidence(
        projection: SceneMetalRendererFrameWorldProjection,
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicValues: SceneDynamicSnapshot,
        encodedLayerCount: Int,
        passthroughLayerCount: Int,
        frameIndex: UInt64,
        topologyRevision: UInt64,
        commandBuffer: MTLCommandBuffer
    ) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
              frameIndex <= 2,
              !projection.dynamicLayerIDs.isEmpty else { return }
        let visibleCount = projection.dynamicLayerIDs.intersection(
            SceneLayerVisibility.visibleLayerIDs(
                in: projection.descriptor,
                layersByID: projection.layersByID,
                snapshot: dynamicValues
            )
        ).count
        let publicationCount = projection.dynamicLayerIDs.reduce(into: 0) {
            count, layerID in
            guard let texture = imageTextures[layerID],
                  imageTextures.explicitLayerSourcePublication(
                    for: layerID,
                    matching: texture
                  ) != nil else { return }
            count += 1
        }
        NSLog(
            "MWX DEBUG SCENE: phase=dynamic-layer-render frame=%llu topologyRevision=%llu cacheHit=%@ descriptor=%d visible=%d sourcePublications=%d encoded=%d passthrough=%d",
            frameIndex,
            topologyRevision,
            String(dynamicLayerTopologyCache.lastResolveWasCacheHit),
            projection.dynamicLayerIDs.count,
            visibleCount,
            publicationCount,
            encodedLayerCount,
            passthroughLayerCount
        )
        commandBuffer.addCompletedHandler { buffer in
            NSLog(
                "MWX DEBUG SCENE: phase=dynamic-layer-render-completion frame=%llu status=%@ error=%@",
                frameIndex,
                String(describing: buffer.status),
                buffer.error.map(String.init(describing:)) ?? "none"
            )
        }
    }
#endif
}
