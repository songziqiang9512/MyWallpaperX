import Foundation
import simd

// These value carriers delimit the topology cache's input boundary. The cache
// and its frame-value application are compiled unchanged from production.
struct SceneUtilityLayer { let framebufferSource: Int? }
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        var stamp = 0
        var imageMaterialRenderState: Int? = nil
        var utilityLayer: SceneUtilityLayer? = nil
        var light = false
    }
    var layers: [Layer]
    let renderOrderLayerIDs: [Int]

    func applying(_ topology: SceneScriptLayerTopologySnapshot) -> Self {
        var byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        for layer in topology.dynamicLayers { byID[layer.id] = layer }
        return .init(layers: topology.renderOrderLayerIDs.compactMap { byID[$0] },
            renderOrderLayerIDs: topology.renderOrderLayerIDs)
    }
}
struct SceneScriptLayerTopologySnapshot {
    let topologyRevision: UInt64
    let dynamicLayers: [SceneRenderDescriptor.Layer]
    let renderOrderLayerIDs: [Int]
}
final class SceneDependencyFrameRuntime {
    let plan = 0
    var rejectsPreparation = false
    func resolvedMaterialPreparationOrder(authoredLayerIDs: [Int]) -> [Int]? {
        rejectsPreparation ? nil : Array(authoredLayerIDs.reversed())
    }
}
enum SceneUtilityLayerRuntimePlanner {
    struct Execution { let orderedLayerIDs: [Int] }
    static func plans(in descriptor: SceneRenderDescriptor, dependencyPlan: Int,
                      resolvedMaterialLayerIDs: Set<Int>) -> Int { 0 }
    static func execution(in descriptor: SceneRenderDescriptor, plans: Int) -> Execution {
        .init(orderedLayerIDs: descriptor.renderOrderLayerIDs)
    }
}
enum SceneLayerWorldFrameResolver {
    static func compute(descriptor: SceneRenderDescriptor,
                        byID: [Int: SceneRenderDescriptor.Layer]) -> [Int: simd_float4x4] {
        Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, matrix_identity_float4x4) })
    }
}
enum SceneLightSnapshot {
    static func orderedLightLayerIDs(descriptor: SceneRenderDescriptor,
                                    layersByID: [Int: SceneRenderDescriptor.Layer]) -> [Int] {
        descriptor.layers.filter(\.light).map(\.id)
    }
}

@main private enum Harness {
    static func main() throws {
        let base = SceneRenderDescriptor(layers: [
            .init(id: 1, utilityLayer: .init(framebufferSource: 10)),
            .init(id: 2, imageMaterialRenderState: 1, light: true),
        ], renderOrderLayerIDs: [1, 2])
        let runtime = SceneDependencyFrameRuntime()
        let cache = SceneDynamicLayerRenderTopologyCache()
        let first = cache.resolve(baseDescriptor: base,
            topology: .init(topologyRevision: 7, dynamicLayers: [.init(id: 3, stamp: 10)],
                renderOrderLayerIDs: [1, 2, 3]), dependencyRuntime: runtime,
            resolvedMaterialLayerIDs: [1])
        let firstWasMiss = !cache.lastResolveWasCacheHit
        let second = cache.resolve(baseDescriptor: base,
            topology: .init(topologyRevision: 7, dynamicLayers: [.init(id: 3, stamp: 20)],
                renderOrderLayerIDs: [1, 2, 3]), dependencyRuntime: runtime,
            resolvedMaterialLayerIDs: [1])
        let sameRevisionWasHit = cache.lastResolveWasCacheHit
        let changed = cache.resolve(baseDescriptor: base,
            topology: .init(topologyRevision: 8,
                dynamicLayers: [.init(id: 4, stamp: 30, utilityLayer: .init(framebufferSource: 40))],
                renderOrderLayerIDs: [2, 4]), dependencyRuntime: runtime,
            resolvedMaterialLayerIDs: [1])
        let changedWasMiss = !cache.lastResolveWasCacheHit
        runtime.rejectsPreparation = true
        let rejected = cache.resolve(baseDescriptor: base,
            topology: .init(topologyRevision: 9, dynamicLayers: [], renderOrderLayerIDs: [1, 2]),
            dependencyRuntime: runtime, resolvedMaterialLayerIDs: [1])
        let checks: [String: Bool] = [
            "sameRevisionKeepsPreparedMembership": firstWasMiss && sameRevisionWasHit
                && first.orderedLayerIDs == [1, 2, 3]
                && second.orderedLayerIDs == first.orderedLayerIDs
                && first.preparationLayerIDs == [1, 2, 3]
                && second.preparationLayerIDs == first.preparationLayerIDs
                && first.framebufferSourceLayerIDs == [1]
                && second.framebufferSourceLayerIDs == first.framebufferSourceLayerIDs,
            "frameValuesPatchOrderedAndPreparation": second.layersByID[3]?.stamp == 20
                && second.orderedLayers.first(where: { $0.id == 3 })?.stamp == 20
                && second.preparationLayers?.first?.stamp == 20
                && first.layersByID[3]?.stamp == 10,
            "newRevisionRebuildsMembership": changedWasMiss && changed.orderedLayerIDs == [2, 4]
                && changed.preparationLayerIDs == [2, 4]
                && changed.framebufferSourceLayerIDs == [4]
                && changed.imageMaterialStateLayerIDs == [2] && changed.lightLayerIDs == [2],
            "missingPreparationRemainsInvalid": rejected.preparationLayers == nil
                && rejected.preparationLayerIDs.isEmpty && rejected.framebufferSourceLayerIDs.isEmpty,
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: checks))
    }
}
