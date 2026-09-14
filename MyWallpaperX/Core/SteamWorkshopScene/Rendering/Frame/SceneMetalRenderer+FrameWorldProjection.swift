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
        if let layerTopology,
           !layerTopology.dynamicLayers.isEmpty
                || layerTopology.renderOrderLayerIDs
                    != renderDescriptor.renderOrderLayerIDs {
            let projection = dynamicLayerTopologyCache.resolve(
                baseDescriptor: renderDescriptor,
                topology: layerTopology
            )
            descriptor = projection.descriptor
            layersByID = projection.layersByID
            staticWorldFrames = projection.staticWorldFrames
            orderedLayers = projection.orderedLayers
            dynamicLayerIDs = projection.dynamicLayerIDs
            lightLayerIDs = projection.lightLayerIDs
        } else {
            descriptor = renderDescriptor
            layersByID = self.layersByID
            staticWorldFrames = worldFramesByLayerID
            orderedLayers = authoredLayers
            dynamicLayerIDs = []
            lightLayerIDs = self.lightLayerIDs
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
            )
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
