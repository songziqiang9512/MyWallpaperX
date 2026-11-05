import simd

/// Surface-scoped projection cache for the small descriptor delta produced by
/// SceneScript dynamic layers. Dynamic values stay outside this cache; only
/// the descriptor indexes and static world frames are reused by revision.
final class SceneDynamicLayerRenderTopologyCache {
    struct Projection {
        let descriptor: SceneRenderDescriptor
        let layersByID: [Int: SceneRenderDescriptor.Layer]
        let staticWorldFrames: [Int: simd_float4x4]
        let orderedLayers: [SceneRenderDescriptor.Layer]
        let orderedLayerIDs: [Int]
        let dynamicLayerIDs: Set<Int>
        let lightLayerIDs: [Int]
        let imageMaterialStateLayerIDs: Set<Int>
        let utilityExecution: SceneUtilityLayerRuntimePlanner.Execution
        let renderLayerIDs: Set<Int>
        let framebufferSourceLayerIDs: Set<Int>
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
            return projection
        }
        lastResolveWasCacheHit = false
        let descriptor = baseDescriptor.applying(topology)
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
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
        let lightLayerIDs = SceneLightSnapshot.orderedLightLayerIDs(
            descriptor: descriptor,
            layersByID: layersByID
        )
        let projection = Projection(
            descriptor: descriptor,
            layersByID: layersByID,
            staticWorldFrames: SceneLayerWorldFrameResolver.compute(
                descriptor: descriptor, byID: layersByID
            ),
            orderedLayers: orderedLayers,
            orderedLayerIDs: orderedLayers.map(\.id),
            dynamicLayerIDs: dynamicLayerIDs,
            lightLayerIDs: lightLayerIDs,
            imageMaterialStateLayerIDs: Set(descriptor.layers.compactMap {
                $0.imageMaterialRenderState == nil ? nil : $0.id
            }),
            utilityExecution: utilityExecution,
            renderLayerIDs: Set(executionLayerIDs),
            framebufferSourceLayerIDs: Set(orderedLayers.compactMap {
                $0.utilityLayer?.framebufferSource == nil ? nil : $0.id
            })
        )
        revision = topology.topologyRevision
        self.projection = projection
        return projection
    }
}
