import Foundation

enum SceneLayerVisibility {
    nonisolated static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            isEffectivelyVisible(layer, layersByID: layersByID) ? layer.id : nil
        })
    }

    nonisolated static func reportLines(
        in descriptor: SceneRenderDescriptor
    ) -> [String] {
        descriptor.layers.compactMap { layer in
            guard let ownership = layer.displayScriptOwnership,
                  !ownership.isEmpty else { return nil }
            return "scene layer display-state: layer=\(layer.id)"
                + " fields=\(ownership.fields.joined(separator: ","))"
                + " disposition=suppressed"
                + " reason=unproven-inline-scenescript"
        }
    }

    nonisolated private static func isEffectivelyVisible(
        _ layer: SceneRenderDescriptor.Layer,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        var current: SceneRenderDescriptor.Layer? = layer
        var visited: Set<Int> = []
        while let candidate = current {
            guard candidate.visible != false,
                  candidate.displayScriptOwnership?.isEmpty != false,
                  visited.insert(candidate.id).inserted else {
                return false
            }
            current = candidate.parentID.flatMap { layersByID[$0] }
        }
        return true
    }
}
