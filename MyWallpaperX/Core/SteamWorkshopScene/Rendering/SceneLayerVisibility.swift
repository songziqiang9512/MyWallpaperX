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

    /// Source passthrough may consume the same committed visibility authority
    /// as the normal layer walk. It must not revive authored/user fallback or
    /// bypass the still-unsupported alpha owner.
    nonisolated static func hasCurrentSourceDisplayAuthority(
        for layer: SceneRenderDescriptor.Layer,
        snapshot: SceneDynamicSnapshot?
    ) -> Bool {
        if let resolved = snapshot?[
            .layer(layerID: layer.id, field: .visibility)
        ], layer.displayScriptOwnership?.alpha != true,
           resolved.source == .sceneScript,
           case let .bool(value) = resolved.value {
            return value
        }
        guard let ownership = layer.displayScriptOwnership,
              !ownership.isEmpty else { return layer.visible != false }
        guard ownership.alpha != true,
              ownership.visible == true,
              let resolved = snapshot?[
                  .layer(layerID: layer.id, field: .visibility)
              ],
              resolved.source == .sceneScript,
              case .bool(true) = resolved.value else {
            return false
        }
        return true
    }

    nonisolated private static func isEffectivelyVisible(
        _ layer: SceneRenderDescriptor.Layer,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot?
    ) -> Bool {
        var current: SceneRenderDescriptor.Layer? = layer
        var visited: Set<Int> = []
        while let candidate = current {
            let scriptVisibility = snapshot?[
                .layer(layerID: candidate.id, field: .visibility)
            ].flatMap { resolved -> Bool? in
                guard resolved.source == .sceneScript,
                      case let .bool(value) = resolved.value else { return nil }
                return value
            }
            guard hasCurrentSourceDisplayAuthority(
                for: candidate,
                snapshot: snapshot
            ),
                  scriptVisibility ?? candidate.visible ?? true,
                  visited.insert(candidate.id).inserted else {
                return false
            }
            current = candidate.parentID.flatMap { layersByID[$0] }
        }
        return true
    }
}
