import Foundation
import Metal
import simd

struct SceneMetalRendererFrameWorldProjection {
    let descriptor: SceneRenderDescriptor
    let layersByID: [Int: SceneRenderDescriptor.Layer]
    let orderedLayers: [SceneRenderDescriptor.Layer]
    let orderedLayerIDs: [Int]
    let dynamicLayerIDs: Set<Int>
    let lightLayerIDs: [Int]
    let worldFrames: [Int: simd_float4x4]
    let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
    let preparationLayers: [SceneRenderDescriptor.Layer]?
    let preparationLayerIDs: Set<Int>
    let framebufferSourceLayerIDs: Set<Int>
    var imageMaterialStateLayerIDs: Set<Int> = []
}

extension SceneMetalRenderer {
    func resolveFrameTopology(
        layerTopology: SceneScriptLayerTopologySnapshot?
    ) -> SceneDynamicLayerRenderTopologyCache.Projection {
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
            if !dynamicLayerTopologyCache.lastResolveWasCacheHit {
                textureRegistry.retireLayerSources(keeping: projection.layersByID.keys)
            }
            return projection
        }
        if dynamicLayerTopologyCache.reset() {
            textureRegistry.retireLayerSources(keeping: layersByID.keys)
        }
        return .init(descriptor: renderDescriptor, layersByID: layersByID,
            staticWorldFrames: worldFramesByLayerID, orderedLayers: authoredLayers,
            orderedLayerIDs: orderedLayerIDs, dynamicLayerIDs: [], lightLayerIDs: lightLayerIDs,
            imageMaterialStateLayerIDs: imageMaterialStateLayerIDs, utilityExecution: utilityExecution,
            preparationLayers: resolvedMaterialPreparationLayers, preparationLayerIDs: preparationLayerIDs,
            framebufferSourceLayerIDs: framebufferSourceLayerIDs)
    }

    func resolveFrameWorldProjection(
        layerTopology: SceneScriptLayerTopologySnapshot?,
        dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot
    ) -> SceneMetalRendererFrameWorldProjection {
        let topology = resolveFrameTopology(layerTopology: layerTopology)
        return SceneMetalRendererFrameWorldProjection(
            descriptor: topology.descriptor,
            layersByID: topology.layersByID,
            orderedLayers: topology.orderedLayers,
            orderedLayerIDs: topology.orderedLayerIDs,
            dynamicLayerIDs: topology.dynamicLayerIDs,
            lightLayerIDs: topology.lightLayerIDs,
            worldFrames: SceneLayerDynamicWorldFrameResolver.resolve(
                descriptor: topology.descriptor,
                byID: topology.layersByID,
                snapshot: dynamicValues,
                staticFrames: topology.staticWorldFrames,
                dynamicLayerIDs: topology.dynamicLayerIDs,
                puppetAttachmentFrames: puppetAttachmentFrames
            ),
            utilityExecution: topology.utilityExecution,
            preparationLayers: topology.preparationLayers,
            preparationLayerIDs: topology.preparationLayerIDs,
            framebufferSourceLayerIDs: topology.framebufferSourceLayerIDs,
            imageMaterialStateLayerIDs: topology.imageMaterialStateLayerIDs
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
