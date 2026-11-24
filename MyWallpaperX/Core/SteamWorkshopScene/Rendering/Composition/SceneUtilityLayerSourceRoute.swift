import Foundation

/// Selects the prepared source and authored capture point for a utility.
/// Isolated groups collect their descendants; Fullscreen can read a child
/// block already drawn into the enclosing main target.
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
        // nil keeps the legacy route. Each nested source needs its own Program.
        var nestedReplayLayerIDs: Set<Int>? = nil

        var allowsPerspectiveReplay: Bool { nestedReplayLayerIDs != nil }
    }

    static func preparedResolutions(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int>
    ) -> [Int: Resolution] {
        var routes: [Int: Resolution] = [:]
        for layer in descriptor.layers where layer.utilityLayer != nil {
            guard var route = try? resolve(layer: layer, descriptor: descriptor).get() else {
                continue
            }
            if let nestedIDs = route.nestedReplayLayerIDs,
               !resolvedMaterialLayerIDs.isSuperset(of: nestedIDs)
                || (!resolvedMaterialLayerIDs.contains(layer.id)
                    && layer.effects.contains { $0.visible != false }) {
                route.nestedReplayLayerIDs = nil
            }
            routes[layer.id] = route
        }
        return routes
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
        if utility.kind == .fullscreen {
            guard layer.parentID == nil,
                  descriptor.camera.authoredOrthographicProjectionActive == true,
                  !utility.passthrough,
                  layer.dependencyLayerIDs.isEmpty, layer.authoredDependencies.isEmpty,
                  descendants.count == layer.childLayerIDs.count,
                  descendants.allSatisfy({
                      layersByID[$0]?.utilityLayer == nil && layersByID[$0]?.usesPerspective != true
                  }) else { return .failure(.compositionSubtreeShape) }
            let inBlock: (Int) -> Bool = { $0 == layer.id || descendants.contains($0) }
            guard let first = order.firstIndex(where: inBlock),
                  let last = order.lastIndex(where: inBlock),
                  last - first == descendants.count else {
                return .failure(.compositionSubtreeShape)
            }
            return .success(.init(
                triggerLayerID: order[last],
                capturesCompositionSubtree: false,
                orderedCompositionSubtreeLayerIDs: []
            ))
        }
        // A composition's local canvas belongs to its admitted structure,
        // independently of root effect declarations or visibility. Keep the
        // same source when an effect is inactive. Nested passthroughs retain
        // structural membership instead of adding source/output owners.
        let flatMembers = descriptor.camera.authoredOrthographicProjectionActive == true
            && !descendants.isEmpty && descendants.allSatisfy {
                layersByID[$0]?.usesPerspective != true
            }
        let localSource = flatMembers && layer.usesPerspective != true
            && descendants.allSatisfy {
                guard let child = layersByID[$0] else { return false }
                return child.utilityLayer?.passthrough == true
                    || child.utilityLayer?.copyBackground != true
                    || child.childLayerIDs.isEmpty
            }
        guard !utility.passthrough || layer.childLayerIDs.isEmpty
                || (layer.parentID == nil && localSource) else {
            return .failure(.compositionSubtreeShape)
        }
        var replayGroupIDs: Set<Int>? = flatMembers && layer.parentID == nil
            && (descriptor.camera.orthoWidth ?? 0) > 0
            && (descriptor.camera.orthoHeight ?? 0) > 0
            && supportsLocalCompositionReplay(layer, utility: utility) ? [] : nil
        for childID in descendants {
            guard let child = layersByID[childID] else {
                return .failure(.compositionSubtreeShape)
            }
            if let childUtility = child.utilityLayer {
                // Newly admitted passthrough roots contain plain producers.
                // Nested utilities retain their original group/preparation
                // policy until their effect-visibility closure is qualified.
                guard !utility.passthrough, childUtility.kind != .fullscreen,
                      child.contentKind == childUtility.kind.rawValue,
                      !childUtility.passthrough || (localSource
                        && (child.childLayerIDs.isEmpty || child.effects.isEmpty)) else {
                    return .failure(.compositionSubtreeShape)
                }
                if child.parentID == layer.id,
                   !childUtility.copyBackground || utility.copyBackground,
                   supportsLocalCompositionReplay(child, utility: childUtility) {
                    replayGroupIDs?.insert(childID)
                } else {
                    replayGroupIDs = nil
                }
            }
        }
        return .success(.init(
            triggerLayerID: layer.id,
            capturesCompositionSubtree: !descendants.isEmpty,
            orderedCompositionSubtreeLayerIDs: order.filter { descendants.contains($0) },
            usesIsolatedGroupTarget: true,
            usesAuthoredLocalSource: localSource,
            nestedReplayLayerIDs: replayGroupIDs
        ))
    }

    private static func supportsLocalCompositionReplay(
        _ layer: SceneRenderDescriptor.Layer,
        utility: SceneUtilityLayer
    ) -> Bool {
        guard utility.kind == .composition && !utility.passthrough
            && utility.framebufferSource == nil && !layer.childLayerIDs.isEmpty
            && layer.dependencyLayerIDs.isEmpty && layer.authoredDependencies.isEmpty,
              let size = layer.renderSizeWH, size.count == 2 else { return false }
        return size.allSatisfy { $0.isFinite && $0 > 0 }
    }
}
