import Foundation

/// Selects the prepared source for a utility. Composition descendants belong
/// to their root's input in authored relative order, independent of the root's
/// array position. Background inclusion is an authored flag, never a prefix
/// or child-count inference.
nonisolated enum SceneUtilityLayerSourceRoute {
    enum Failure: String, Error, Equatable {
        case utilityShape = "utility-shape"
        case compositionSubtreeShape = "utility-composition-subtree-shape"
    }

    struct Resolution: Equatable {
        let triggerLayerID: Int
        let capturesCompositionSubtree: Bool
        let orderedCompositionSubtreeLayerIDs: [Int]
        var usesIsolatedGroupTarget: Bool = false
    }

    static func resolve(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
        guard let utility = layer.utilityLayer,
              layer.contentKind == utility.kind.rawValue else {
            return .failure(.utilityShape)
        }
        // A childless background capture retains the existing readable-pass
        // route. Explicit false needs a transparent source even without children.
        if layer.childLayerIDs.isEmpty,
           utility.kind != .composition || utility.copyBackground
                || utility.passthrough || !layer.dependencyLayerIDs.isEmpty
                || !layer.authoredDependencies.isEmpty {
            return .success(.init(
                triggerLayerID: layer.id,
                capturesCompositionSubtree: false,
                orderedCompositionSubtreeLayerIDs: []
            ))
        }
        guard utility.kind == .composition,
              !utility.passthrough,
              layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty else {
            return .failure(.compositionSubtreeShape)
        }
        let groupedLayers = Dictionary(grouping: descriptor.layers, by: \.id)
        let order = descriptor.renderOrderLayerIDs
        guard groupedLayers.values.allSatisfy({ $0.count == 1 }),
              Set(order).count == order.count,
              order.count == descriptor.layers.count,
              Set(order) == Set(descriptor.layers.map(\.id)) else {
            return .failure(.compositionSubtreeShape)
        }
        let layersByID = groupedLayers.compactMapValues { $0.first }
        let actualChildrenByParentID = Dictionary(
            grouping: descriptor.layers.compactMap { candidate in
                candidate.parentID.map { ($0, candidate.id) }
            },
            by: { $0.0 }
        ).mapValues { $0.map { $0.1 } }
        var descendants = Set<Int>()
        var pending = [layer.id]
        while let parentID = pending.popLast() {
            guard let parent = layersByID[parentID],
                  Set(parent.childLayerIDs).count == parent.childLayerIDs.count,
                  Set(parent.childLayerIDs)
                    == Set(actualChildrenByParentID[parentID] ?? []) else {
                return .failure(.compositionSubtreeShape)
            }
            for childID in parent.childLayerIDs {
                guard childID != layer.id,
                      let child = layersByID[childID],
                      child.parentID == parentID,
                      descendants.insert(childID).inserted else {
                    return .failure(.compositionSubtreeShape)
                }
                pending.append(childID)
            }
        }
        // Existing color producers can draw into this target. Depth-tested
        // models, particles and lights retain their existing unsupported route.
        for childID in descendants {
            guard let child = layersByID[childID] else {
                return .failure(.compositionSubtreeShape)
            }
            if let childUtility = child.utilityLayer {
                guard childUtility.kind == .composition,
                      child.contentKind == childUtility.kind.rawValue,
                      !childUtility.passthrough else {
                    return .failure(.compositionSubtreeShape)
                }
            } else {
                guard ["image", "solid", "text"].contains(child.contentKind),
                      child.childLayerIDs.isEmpty else {
                    return .failure(.compositionSubtreeShape)
                }
            }
        }
        return .success(.init(
            triggerLayerID: layer.id,
            capturesCompositionSubtree: !descendants.isEmpty,
            orderedCompositionSubtreeLayerIDs: order.filter { descendants.contains($0) },
            usesIsolatedGroupTarget: true
        ))
    }
}
