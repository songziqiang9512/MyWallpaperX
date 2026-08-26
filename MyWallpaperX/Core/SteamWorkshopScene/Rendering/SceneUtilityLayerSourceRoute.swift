import Foundation

/// Conserves the authored source-order boundary for a utility layer whose
/// input is the current main target. Child-bearing composition layers are
/// admitted only when their complete subtree is the first closed render-order
/// interval, so the existing main-target capture cannot absorb an unrelated
/// sibling or run before one of its descendants.
nonisolated enum SceneUtilityLayerSourceRoute {
    enum Failure: String, Error, Equatable {
        case utilityShape = "utility-shape"
        case compositionSubtreeShape = "utility-composition-subtree-shape"
    }

    struct Resolution: Equatable {
        let triggerLayerID: Int
        let capturesCompositionSubtree: Bool
        let orderedCompositionSubtreeLayerIDs: [Int]
    }

    static func resolve(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
        guard let utility = layer.utilityLayer,
              layer.contentKind == utility.kind.rawValue else {
            return .failure(.utilityShape)
        }
        guard !layer.childLayerIDs.isEmpty else {
            return .success(.init(
                triggerLayerID: layer.id,
                capturesCompositionSubtree: false,
                orderedCompositionSubtreeLayerIDs: []
            ))
        }
        guard utility.kind == .composition,
              !utility.copyBackground,
              !utility.passthrough,
              hasImplicitOpaqueCompositionAlpha(layer),
              layer.parentID == nil,
              layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty else {
            return .failure(.compositionSubtreeShape)
        }

        let groupedLayers = Dictionary(grouping: descriptor.layers, by: \.id)
        let layerIDs = descriptor.layers.map(\.id)
        let order = descriptor.renderOrderLayerIDs
        guard groupedLayers.values.allSatisfy({ $0.count == 1 }),
              Set(layerIDs).count == layerIDs.count,
              Set(order).count == order.count,
              order.count == layerIDs.count,
              Set(order) == Set(layerIDs),
              order.first == layer.id else {
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
        guard !descendants.isEmpty else {
            return .failure(.compositionSubtreeShape)
        }

        let subtreeIDs = descendants.union([layer.id])
        let orderedSubtree = Array(order.prefix(subtreeIDs.count))
        let orderIndex = Dictionary(uniqueKeysWithValues:
            order.enumerated().map { ($0.element, $0.offset) }
        )
        guard orderedSubtree.first == layer.id,
              Set(orderedSubtree) == subtreeIDs,
              orderedSubtree.count == subtreeIDs.count,
              descendants.allSatisfy({ childID in
                  guard let child = layersByID[childID],
                        let parentID = child.parentID,
                        let parentIndex = orderIndex[parentID],
                        let childIndex = orderIndex[childID] else {
                    return false
                  }
                  return parentIndex < childIndex
              }) else {
            return .failure(.compositionSubtreeShape)
        }

        for childID in descendants {
            guard let child = layersByID[childID],
                  child.dependencyLayerIDs.isEmpty,
                  child.authoredDependencies.isEmpty,
                  child.effects.isEmpty else {
                return .failure(.compositionSubtreeShape)
            }
            if let childUtility = child.utilityLayer {
                guard childUtility.kind == .composition,
                      child.contentKind == childUtility.kind.rawValue,
                      !childUtility.copyBackground,
                      !childUtility.passthrough,
                      hasImplicitOpaqueCompositionAlpha(child) else {
                    return .failure(.compositionSubtreeShape)
                }
            } else {
                guard child.childLayerIDs.isEmpty,
                      ["image", "solid", "text"].contains(child.contentKind) else {
                    return .failure(.compositionSubtreeShape)
                }
            }
        }
        guard let triggerLayerID = orderedSubtree.last else {
            return .failure(.compositionSubtreeShape)
        }
        return .success(.init(
            triggerLayerID: triggerLayerID,
            capturesCompositionSubtree: true,
            orderedCompositionSubtreeLayerIDs: orderedSubtree
        ))
    }

    /// Descendants are currently drawn into the main target before the root
    /// effect chain captures it. Until composition groups own an isolated
    /// target, any authored or live group alpha would be applied after those
    /// descendants and could not restore previous-current semantics.
    private static func hasImplicitOpaqueCompositionAlpha(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.alpha == nil
            && layer.displayScriptOwnership?.alpha != true
            && !layer.timelines.contains(where: { $0.host == .alpha })
            && !(layer.scriptBindings ?? []).contains(where: { $0.host == "alpha" })
    }
}
