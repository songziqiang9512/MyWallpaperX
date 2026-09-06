import simd

/// Surface-scoped projection cache for the small descriptor delta produced by
/// SceneScript dynamic layers. Dynamic values stay outside this cache; only
/// the descriptor indexes and static world frames are reused by revision.
final class SceneDynamicLayerRenderTopologyCache {
    struct Projection {
        let descriptor: SceneRenderDescriptor
        let layersByID: [Int: SceneRenderDescriptor.Layer]
        let layerIndicesByID: [Int: Int]
        let staticWorldFrames: [Int: simd_float4x4]
        let authoredLayerIDs: [Int]

        /// Dynamic layer values are surface/frame scoped. Keep the complete
        /// value record out of the revision cache so two surfaces cannot
        /// inherit the first surface's transform, visibility or tint.
        func applyingFrameValues(
            from topology: SceneScriptLayerTopologySnapshot
        ) -> Self {
            guard !topology.dynamicLayers.isEmpty else { return self }
            var descriptor = descriptor
            var layersByID = layersByID
            for layer in topology.dynamicLayers {
                guard let index = layerIndicesByID[layer.id] else { continue }
                descriptor.layers[index] = layer
                layersByID[layer.id] = layer
            }
            return .init(
                descriptor: descriptor,
                layersByID: layersByID,
                layerIndicesByID: layerIndicesByID,
                staticWorldFrames: staticWorldFrames,
                authoredLayerIDs: authoredLayerIDs
            )
        }
    }

    private var revision: UInt64?
    private var projection: Projection?
    private(set) var lastResolveWasCacheHit = false

    func resolve(
        baseDescriptor: SceneRenderDescriptor,
        topology: SceneScriptLayerTopologySnapshot
    ) -> Projection {
        if revision == topology.topologyRevision, let projection {
            lastResolveWasCacheHit = true
            return projection.applyingFrameValues(from: topology)
        }
        lastResolveWasCacheHit = false
        let descriptor = baseDescriptor.applying(topology)
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        let layerIndicesByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let projection = Projection(
            descriptor: descriptor,
            layersByID: layersByID,
            layerIndicesByID: layerIndicesByID,
            staticWorldFrames: SceneLayerWorldFrameResolver.compute(
                descriptor: descriptor, byID: layersByID
            ),
            authoredLayerIDs: descriptor.renderOrderLayerIDs
        )
        revision = topology.topologyRevision
        self.projection = projection
        return projection.applyingFrameValues(from: topology)
    }
}
