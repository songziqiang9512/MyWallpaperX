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
        let orderedLayers: [SceneRenderDescriptor.Layer]
        let orderedLayerIDs: [Int]
        let orderedLayerPositionsByID: [Int: Int]
        let dynamicLayerIDs: Set<Int>
        let lightLayerIDs: [Int]
        let imageMaterialStateLayerIDs: Set<Int>
        let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
        let preparationLayers: [SceneRenderDescriptor.Layer]?
        let preparationLayerPositionsByID: [Int: Int]
        let preparationLayerIDs: Set<Int>
        let framebufferSourceLayerIDs: Set<Int>

        /// Dynamic layer values are surface/frame scoped. Keep the complete
        /// value record out of the revision cache so two surfaces cannot
        /// inherit the first surface's transform, visibility or tint.
        func applyingFrameValues(
            from topology: SceneScriptLayerTopologySnapshot
        ) -> Self {
            guard !topology.dynamicLayers.isEmpty else { return self }
            var descriptor = descriptor
            var layersByID = layersByID
            var orderedLayers = orderedLayers
            var preparationLayers = preparationLayers
            for layer in topology.dynamicLayers {
                guard let index = layerIndicesByID[layer.id] else { continue }
                descriptor.layers[index] = layer
                layersByID[layer.id] = layer
                if let orderedIndex = orderedLayerPositionsByID[layer.id] {
                    orderedLayers[orderedIndex] = layer
                }
                if let index = preparationLayerPositionsByID[layer.id] {
                    preparationLayers?[index] = layer
                }
            }
            return .init(
                descriptor: descriptor,
                layersByID: layersByID,
                layerIndicesByID: layerIndicesByID,
                staticWorldFrames: staticWorldFrames,
                orderedLayers: orderedLayers,
                orderedLayerIDs: orderedLayerIDs,
                orderedLayerPositionsByID: orderedLayerPositionsByID,
                dynamicLayerIDs: dynamicLayerIDs,
                lightLayerIDs: lightLayerIDs,
                imageMaterialStateLayerIDs: imageMaterialStateLayerIDs,
                utilityExecution: utilityExecution,
                preparationLayers: preparationLayers,
                preparationLayerPositionsByID: preparationLayerPositionsByID,
                preparationLayerIDs: preparationLayerIDs,
                framebufferSourceLayerIDs: framebufferSourceLayerIDs
            )
        }
    }

    private var revision: UInt64?
    private var projection: Projection?
    private(set) var lastResolveWasCacheHit = false

    @discardableResult
    func reset() -> Bool {
        let hadProjection = projection != nil
        projection = nil
        revision = nil
        lastResolveWasCacheHit = false
        return hadProjection
    }

    func resolve(
        baseDescriptor: SceneRenderDescriptor,
        topology: SceneScriptLayerTopologySnapshot,
        dependencyRuntime: SceneDependencyFrameRuntime,
        resolvedMaterialLayerIDs: Set<Int>
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
        let dynamicLayerIDs = Set(topology.dynamicLayers.map(\.id))
        let utilityExecution = SceneUtilityLayerRuntimePlanner.execution(
            in: descriptor,
            plans: SceneUtilityLayerRuntimePlanner.plans(
                in: descriptor, dependencyPlan: dependencyRuntime.plan,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        )
        let executionLayerIDs = utilityExecution.orderedLayerIDs
        let orderedLayers = executionLayerIDs.compactMap { layersByID[$0] }
        let orderedLayerPositionsByID = Dictionary(
            uniqueKeysWithValues: executionLayerIDs.enumerated().compactMap {
                offset, layerID in
                layersByID[layerID] == nil ? nil : (layerID, offset)
            }
        )
        let lightLayerIDs = SceneLightSnapshot.orderedLightLayerIDs(
            descriptor: descriptor,
            layersByID: layersByID
        )
        let preparationLayerIDs = dependencyRuntime.resolvedMaterialPreparationOrder(
            authoredLayerIDs: executionLayerIDs
        )
        let preparationLayers = preparationLayerIDs.flatMap { ids in
            let layers = ids.compactMap { layersByID[$0] }
            return layers.count == ids.count ? layers : nil
        }
        let preparationLayerPositionsByID = Dictionary(uniqueKeysWithValues:
            (preparationLayerIDs ?? []).enumerated().map { ($0.element, $0.offset) }
        )
        let projection = Projection(
            descriptor: descriptor,
            layersByID: layersByID,
            layerIndicesByID: layerIndicesByID,
            staticWorldFrames: SceneLayerWorldFrameResolver.compute(
                descriptor: descriptor, byID: layersByID
            ),
            orderedLayers: orderedLayers,
            orderedLayerIDs: orderedLayers.map(\.id),
            orderedLayerPositionsByID: orderedLayerPositionsByID,
            dynamicLayerIDs: dynamicLayerIDs,
            lightLayerIDs: lightLayerIDs,
            imageMaterialStateLayerIDs: Set(descriptor.layers.compactMap {
                $0.imageMaterialRenderState == nil ? nil : $0.id
            }),
            utilityExecution: utilityExecution,
            preparationLayers: preparationLayers,
            preparationLayerPositionsByID: preparationLayerPositionsByID,
            preparationLayerIDs: Set((preparationLayers ?? []).map(\.id)),
            framebufferSourceLayerIDs: Set((preparationLayers ?? []).compactMap {
                $0.utilityLayer?.framebufferSource == nil ? nil : $0.id
            })
        )
        revision = topology.topologyRevision
        self.projection = projection
        return projection.applyingFrameValues(from: topology)
    }
}
