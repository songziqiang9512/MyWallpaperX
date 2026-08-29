import Foundation

nonisolated struct SceneScriptLayerTopologySnapshot: Sendable {
    let dynamicLayers: [SceneRenderDescriptor.Layer]
    let renderOrderLayerIDs: [Int]
}

/// Launch-scoped topology transaction. VM callbacks publish bounded mutations;
/// rendering reads one immutable snapshot and commits successful mutations only
/// after the current frame, so new/destroyed layers become visible next frame.
nonisolated final class SceneScriptDynamicLayerRuntime: @unchecked Sendable {
    private let authoredLayerIDs: Set<Int>
    private var order: [Int]
    private var dynamicLayersByID: [Int: SceneRenderDescriptor.Layer] = [:]

    init(descriptor: SceneRenderDescriptor) {
        authoredLayerIDs = Set(descriptor.layers.map(\.id))
        order = descriptor.renderOrderLayerIDs
    }

    func snapshot() -> SceneScriptLayerTopologySnapshot {
        .init(
            dynamicLayers: order.compactMap { dynamicLayersByID[$0] },
            renderOrderLayerIDs: order
        )
    }

    func apply(
        _ mutations: [SceneScriptLayerMutation]
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        guard mutations.count <= 192 else {
            return .failure(.mutationOverflow("frame layer mutation budget exceeded"))
        }
        var candidateOrder = order
        var candidateLayers = dynamicLayersByID
        for mutation in mutations {
            guard mutation.orderIndex >= 0,
                  mutation.alpha.isFinite, (0...1).contains(mutation.alpha),
                  mutation.pointSize.isFinite, (1...1024).contains(mutation.pointSize),
                  mutation.origin.x.isFinite, mutation.origin.y.isFinite,
                  mutation.origin.z.isFinite, mutation.scale.x.isFinite,
                  mutation.scale.y.isFinite, mutation.scale.z.isFinite,
                  mutation.angles.x.isFinite, mutation.angles.y.isFinite,
                  mutation.angles.z.isFinite, mutation.color.x.isFinite,
                  mutation.color.y.isFinite, mutation.color.z.isFinite,
                  mutation.text.utf8.count <= 4_096,
                  mutation.font.utf8.count <= 1_024 else {
                return .failure(.invalidArgument("invalid dynamic layer mutation"))
            }
            if !mutation.isDynamic {
                return .failure(.invalidArgument("authored layer mutation is unsupported"))
            }
            guard !authoredLayerIDs.contains(mutation.layerID) else {
                return .failure(.invalidArgument("dynamic layer identity collides with authored layer"))
            }
            switch mutation.kind {
            case .destroy:
                guard candidateLayers.removeValue(forKey: mutation.layerID) != nil else {
                    return .failure(.staleOwner)
                }
                candidateOrder.removeAll { $0 == mutation.layerID }
            case .upsert:
                guard let layer = SceneRenderDescriptor.Layer.dynamicText(mutation) else {
                    return .failure(.invalidArgument("dynamic text layer is invalid"))
                }
                candidateLayers[mutation.layerID] = layer
                candidateOrder.removeAll { $0 == mutation.layerID }
                candidateOrder.insert(
                    mutation.layerID,
                    at: min(mutation.orderIndex, candidateOrder.count)
                )
            }
        }
        guard candidateLayers.count <= 256,
              Set(candidateOrder).count == candidateOrder.count,
              candidateLayers.keys.allSatisfy(candidateOrder.contains) else {
            return .failure(.mutationOverflow("dynamic layer topology budget exceeded"))
        }
        order = candidateOrder
        dynamicLayersByID = candidateLayers
        return .success(())
    }
}
