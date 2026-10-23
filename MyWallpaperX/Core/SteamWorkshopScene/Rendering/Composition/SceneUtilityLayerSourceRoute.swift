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
        var usesAuthoredLocalSource: Bool = false
    }

    static func resolve(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor
    ) -> Result<Resolution, Failure> {
        guard let utility = layer.utilityLayer,
              layer.contentKind == utility.kind.rawValue else {
            return .failure(.utilityShape)
        }
        // Background capture is an authored source choice. Named sampler
        // dependencies do not request a copy of the enclosing main target.
        if layer.childLayerIDs.isEmpty,
           utility.kind != .composition || utility.copyBackground {
            return .success(.init(
                triggerLayerID: layer.id,
                capturesCompositionSubtree: false,
                orderedCompositionSubtreeLayerIDs: []
            ))
        }
        // A childless passthrough has no members to pass through. Its explicit
        // background choice still owns the effect input, including transparency.
        guard utility.kind == .composition,
              layer.childLayerIDs.isEmpty
                || (layer.dependencyLayerIDs.isEmpty
                    && layer.authoredDependencies.isEmpty) else {
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
        // A composition's local canvas belongs to its admitted structure,
        // independently of root effect declarations or visibility. Keep the
        // same source when an effect is inactive. Nested passthroughs retain
        // structural membership instead of adding source/output owners.
        let localSource = descriptor.camera.authoredOrthographicProjectionActive == true
            && !descendants.isEmpty
            && layer.usesPerspective != true
            && descendants.allSatisfy { childID in
                guard let child = layersByID[childID], child.usesPerspective != true else {
                    return false
                }
                // A nested background group still requires its original
                // viewport copy. Do not change that input by partial migration.
                return child.utilityLayer?.kind != .composition
                    || child.utilityLayer?.passthrough == true
                    || child.utilityLayer?.copyBackground != true
                    || child.childLayerIDs.isEmpty
            }
        guard !utility.passthrough || layer.childLayerIDs.isEmpty
                || (layer.parentID == nil && localSource) else {
            return .failure(.compositionSubtreeShape)
        }
        // Existing color producers can draw into this target. Depth-tested
        // models, particles and lights retain their existing unsupported route.
        // Plain members may own transform-parent chains; membership follows
        // the full parent closure, so only the member kind is restricted.
        for childID in descendants {
            guard let child = layersByID[childID] else {
                return .failure(.compositionSubtreeShape)
            }
            if let childUtility = child.utilityLayer {
                // Newly admitted passthrough roots contain plain producers.
                // Nested utilities retain their original group/preparation
                // policy until their effect-visibility closure is qualified.
                guard !utility.passthrough, childUtility.kind == .composition,
                      child.contentKind == childUtility.kind.rawValue,
                      !childUtility.passthrough || (localSource
                        && (child.childLayerIDs.isEmpty || child.effects.isEmpty)) else {
                    return .failure(.compositionSubtreeShape)
                }
            } else {
                guard ["image", "solid", "text"].contains(child.contentKind) else {
                    return .failure(.compositionSubtreeShape)
                }
            }
        }
        return .success(.init(
            triggerLayerID: layer.id,
            capturesCompositionSubtree: !descendants.isEmpty,
            orderedCompositionSubtreeLayerIDs: order.filter { descendants.contains($0) },
            usesIsolatedGroupTarget: true,
            usesAuthoredLocalSource: localSource
        ))
    }
}
