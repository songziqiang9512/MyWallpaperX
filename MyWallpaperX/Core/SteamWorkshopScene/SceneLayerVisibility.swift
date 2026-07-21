import Foundation

enum SceneLayerVisibility {
    nonisolated static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            isEffectivelyVisible(layer, layersByID: layersByID) ? layer.id : nil
        })
    }

    nonisolated private static func isEffectivelyVisible(
        _ layer: SceneRenderDescriptor.Layer,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        var current: SceneRenderDescriptor.Layer? = layer
        var visited: Set<Int> = []
        while let candidate = current {
            guard candidate.visible != false, visited.insert(candidate.id).inserted else {
                return false
            }
            current = candidate.parentID.flatMap { layersByID[$0] }
        }
        return true
    }
}
