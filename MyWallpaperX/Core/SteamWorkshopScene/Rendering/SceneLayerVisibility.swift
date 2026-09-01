import Foundation

enum SceneLayerVisibility {
    nonisolated static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            isEffectivelyVisible(layer, layersByID: layersByID, snapshot: nil)
                ? layer.id : nil
        })
    }

    nonisolated static func visibleLayerIDs(
        in descriptor: SceneRenderDescriptor,
        snapshot: SceneDynamicSnapshot
    ) -> Set<Int> {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            isEffectivelyVisible(layer, layersByID: layersByID, snapshot: snapshot)
                ? layer.id : nil
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

    /// Source passthrough consumes the same highest-priority committed Boolean
    /// as the normal layer walk. A SceneScript display owner still requires an
    /// actual SceneScript publication and the unsupported alpha owner remains
    /// fail closed.
    nonisolated static func hasCurrentSourceDisplayAuthority(
        for layer: SceneRenderDescriptor.Layer,
        snapshot: SceneDynamicSnapshot?
    ) -> Bool {
        let resolved = snapshot?[
            .layer(layerID: layer.id, field: .visibility)
        ]
        if let ownership = layer.displayScriptOwnership,
           !ownership.isEmpty {
            guard ownership.alpha != true,
                  ownership.visible == true,
                  resolved?.source == .sceneScript,
                  case .bool(true) = resolved?.value else { return false }
            return true
        }
        if let resolved, case let .bool(value) = resolved.value {
            return value
        }
        return layer.visible != false
    }

    nonisolated private static func isEffectivelyVisible(
        _ layer: SceneRenderDescriptor.Layer,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot?
    ) -> Bool {
        var current: SceneRenderDescriptor.Layer? = layer
        var visited: Set<Int> = []
        while let candidate = current {
            guard hasCurrentSourceDisplayAuthority(
                for: candidate,
                snapshot: snapshot
            ),
                  visited.insert(candidate.id).inserted else {
                return false
            }
            current = candidate.parentID.flatMap { layersByID[$0] }
        }
        return true
    }
}
