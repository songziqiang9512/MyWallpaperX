import Foundation

/// Conserves the authored source-order boundary for a utility layer whose
/// input is the current main target. Child-bearing composition layers follow
/// one of two routes: the legacy contiguous-prefix capture (the complete
/// subtree must be the first closed render-order interval and descendants
/// must be effect-free), or the D1 isolated composition-group target, whose
/// members may interleave with non-members and carry their own effects and
/// dependencies. Non-contiguous or effect-bearing inputs can never fall back
/// to the legacy route.
nonisolated enum SceneUtilityLayerSourceRoute {
    enum Failure: String, Error, Equatable {
        case utilityShape = "utility-shape"
        case compositionSubtreeShape = "utility-composition-subtree-shape"
    }

    struct Resolution: Equatable {
        let triggerLayerID: Int
        let capturesCompositionSubtree: Bool
        let orderedCompositionSubtreeLayerIDs: [Int]
        /// The D1 composition-group route: members render into a group-
        /// private offscreen target and the group composites once at its
        /// authored position. `false` on the legacy contiguous-prefix
        /// capture route and on childless utility captures.
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
        guard !layer.childLayerIDs.isEmpty else {
            return .success(.init(
                triggerLayerID: layer.id,
                capturesCompositionSubtree: false,
                orderedCompositionSubtreeLayerIDs: []
            ))
        }
        let legacy = resolveLegacyContiguousPrefix(
            layer: layer,
            utility: utility,
            descriptor: descriptor
        )
        if case let .success(resolution) = legacy {
            return .success(resolution)
        }
        return resolveIsolatedGroup(
            layer: layer,
            utility: utility,
            descriptor: descriptor
        )
    }

    /// Legacy route, unchanged: the subtree must be the first closed
    /// render-order interval and every descendant must be effect-free and
    /// dependency-free, because descendants draw into the main target before
    /// the root effect chain captures it.
    private static func resolveLegacyContiguousPrefix(
        layer: SceneRenderDescriptor.Layer,
        utility: SceneUtilityLayer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
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

    /// D1 composition-group route: the root owns a group-private render
    /// target, so members may interleave with non-members in the authored
    /// order and carry their own effects and dependencies. The group
    /// composites once at the position of its last member in render order.
    /// Nested composition roots are admitted as members and resolve their
    /// own group recursively; the ordered list therefore keeps every
    /// descendant so the trigger lands after all nested work.
    private static func resolveIsolatedGroup(
        layer: SceneRenderDescriptor.Layer,
        utility: SceneUtilityLayer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
        guard utility.kind == .composition,
              !utility.copyBackground,
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
        guard !descendants.isEmpty else {
            return .failure(.compositionSubtreeShape)
        }
        // Members keep their authored effects and dependencies; only content
        // the group target cannot host is rejected. Depth-tested models,
        // particles and spot lights need their own target plumbing and stay
        // on the flat route.
        for childID in descendants {
            guard let child = layersByID[childID] else {
                return .failure(.compositionSubtreeShape)
            }
            if let childUtility = child.utilityLayer {
                guard childUtility.kind == .composition,
                      child.contentKind == childUtility.kind.rawValue,
                      !childUtility.copyBackground,
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
        // 组内只过滤成员、不按层号排序：合成顺序沿用现役 render order。
        let orderIndex = Dictionary(uniqueKeysWithValues:
            order.enumerated().map { ($0.element, $0.offset) }
        )
        guard descendants.allSatisfy({ childID in
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
        let orderedMembers = order.filter { descendants.contains($0) }
        guard let triggerLayerID = orderedMembers.last else {
            return .failure(.compositionSubtreeShape)
        }
        return .success(.init(
            triggerLayerID: triggerLayerID,
            capturesCompositionSubtree: true,
            orderedCompositionSubtreeLayerIDs: orderedMembers,
            usesIsolatedGroupTarget: true
        ))
    }

    /// Legacy-route guard: descendants are drawn into the main target before
    /// the root effect chain captures it, so any authored or live group alpha
    /// would be applied after those descendants and could not restore
    /// previous-current semantics. The isolated-group route does not use
    /// this proof: a translucent group target composites legally.
    private static func hasImplicitOpaqueCompositionAlpha(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.alpha == nil
            && layer.displayScriptOwnership?.alpha != true
            && !layer.timelines.contains(where: { $0.host == .alpha })
            && !(layer.scriptBindings ?? []).contains(where: { $0.host == "alpha" })
    }
}
