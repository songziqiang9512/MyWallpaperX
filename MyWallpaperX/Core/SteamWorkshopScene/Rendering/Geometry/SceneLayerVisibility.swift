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
        return visibleLayerIDs(
            in: descriptor,
            layersByID: layersByID,
            snapshot: snapshot
        )
    }

    nonisolated static func visibleLayerIDs(
        in descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot
    ) -> Set<Int> {
        // One pass with a shared per-call memo: every layer's authority is
        // resolved at most once, and a resolved ancestor terminates the walk
        // for all its descendants instead of re-walking the parent chain.
        var visibilityByLayerID: [Int: Bool] = [:]
        visibilityByLayerID.reserveCapacity(descriptor.layers.count)
        var chain: [Int] = []
        var result = Set<Int>()
        result.reserveCapacity(descriptor.layers.count)
        for layer in descriptor.layers {
            chain.removeAll(keepingCapacity: true)
            var chainVisible = true
            var current: SceneRenderDescriptor.Layer? = layer
            while let candidate = current {
                if let cached = visibilityByLayerID[candidate.id] {
                    chainVisible = cached
                    break
                }
                guard hasCurrentSourceDisplayAuthority(
                    for: candidate,
                    snapshot: snapshot
                ) else {
                    visibilityByLayerID[candidate.id] = false
                    chainVisible = false
                    break
                }
                if chain.contains(candidate.id) {
                    chainVisible = false
                    break
                }
                chain.append(candidate.id)
                current = candidate.parentID.flatMap { layersByID[$0] }
            }
            for layerID in chain {
                visibilityByLayerID[layerID] = chainVisible
            }
            if chainVisible {
                result.insert(layer.id)
            }
        }
        return result
    }

    nonisolated static func reportLines(
        in descriptor: SceneRenderDescriptor
    ) -> [String] {
        descriptor.layers.compactMap { layer in
            guard let ownership = layer.displayScriptOwnership,
                  !ownership.isEmpty else { return nil }
            let keepsPreviousCurrent = ownership.visible && !ownership.alpha
            return "scene layer display-state: layer=\(layer.id)"
                + " fields=\(ownership.fields.joined(separator: ","))"
                + (keepsPreviousCurrent
                    ? " disposition=previous-current"
                        + " reason=awaiting-scenescript-publication"
                    : " disposition=suppressed"
                        + " reason=unproven-inline-scenescript-alpha")
        }
    }

    /// Check one candidate and its parent chain without materializing the
    /// complete visible-layer set. Camera hit projection calls this for a
    /// single candidate on every input sample; the full set remains available
    /// for composition and publication paths.
    nonisolated static func isEffectivelyVisible(
        layerID: Int,
        in descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot
    ) -> Bool {
        guard let layer = layersByID[layerID] else { return false }
        return isEffectivelyVisible(layer, layersByID: layersByID, snapshot: snapshot)
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
                  ownership.visible == true else { return false }
            if let resolved, case let .bool(value) = resolved.value {
                return value
            }
            if snapshot == nil {
                // Launch admission runs before any script: the authored value
                // is only the seed a visibility script may override. Treat the
                // script-owned field as visible so routes and plans are not
                // frozen dead by the seed; every per-frame consumer passes a
                // snapshot and keeps gating by the published value.
                return true
            }
            return layer.visible != false
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
