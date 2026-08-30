import Foundation

nonisolated struct SceneScriptLayerTopologySnapshot: Sendable {
    let dynamicLayers: [SceneRenderDescriptor.Layer]
    let renderOrderLayerIDs: [Int]
    let authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue]
}

/// Launch-scoped layer mutation transaction. VM callbacks publish bounded
/// mutations; rendering reads one immutable snapshot and commits successful
/// dynamic topology or authored fields only after the current frame.
nonisolated final class SceneScriptDynamicLayerRuntime: @unchecked Sendable {
    let authoredLayerDefinitions: [SceneDynamicTargetDefinition]
    private let authoredLayerIDs: Set<Int>
    private let authoredMutationLayerIDs: Set<Int>
    private var order: [Int]
    private var dynamicLayersByID: [Int: SceneRenderDescriptor.Layer] = [:]
    private var authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue] = [:]

    init(
        descriptor: SceneRenderDescriptor,
        authoredMutationLayerIDs: Set<Int>
    ) {
        authoredLayerIDs = Set(descriptor.layers.map(\.id))
        self.authoredMutationLayerIDs = authoredMutationLayerIDs
        order = descriptor.renderOrderLayerIDs
        authoredLayerDefinitions = descriptor.layers.filter {
            authoredMutationLayerIDs.contains($0.id)
        }.flatMap {
            layer -> [SceneDynamicTargetDefinition] in
            let origin = Self.vector3(layer.originXYZ, fallback: [0, 0, 0])
            let scale = Self.vector3(layer.scaleXYZ, fallback: [1, 1, 1])
            let angles = Self.vector3(layer.anglesXYZ, fallback: [0, 0, 0])
            return [
                .init(
                    target: .layer(layerID: layer.id, field: .origin),
                    valueType: .vector3, authoredValue: origin
                ),
                .init(
                    target: .layer(layerID: layer.id, field: .scale),
                    valueType: .vector3, authoredValue: scale
                ),
                .init(
                    target: .layer(layerID: layer.id, field: .angles),
                    valueType: .vector3, authoredValue: angles
                ),
                .init(
                    target: .layer(layerID: layer.id, field: .visibility),
                    valueType: .bool,
                    authoredValue: .bool(layer.visible ?? true)
                ),
            ]
        }
    }

    func snapshot() -> SceneScriptLayerTopologySnapshot {
        .init(
            dynamicLayers: order.compactMap { dynamicLayersByID[$0] },
            renderOrderLayerIDs: order,
            authoredLayerValues: authoredLayerValues
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
        var candidateAuthoredValues = authoredLayerValues
        var authoredTargets = Set<SceneDynamicTarget>()
        for mutation in mutations {
            guard mutation.origin.x.isFinite, mutation.origin.y.isFinite,
                  mutation.origin.z.isFinite, mutation.scale.x.isFinite,
                  mutation.scale.y.isFinite, mutation.scale.z.isFinite,
                  mutation.angles.x.isFinite, mutation.angles.y.isFinite,
                  mutation.angles.z.isFinite else {
                return .failure(.invalidArgument("invalid layer transform mutation"))
            }
            if !mutation.isDynamic {
                guard mutation.kind == .upsert,
                      authoredLayerIDs.contains(mutation.layerID),
                      authoredMutationLayerIDs.contains(mutation.layerID),
                      !mutation.fields.isEmpty,
                      mutation.fields.isSubset(of: .authoredFields) else {
                    return .failure(.invalidArgument("invalid authored layer mutation"))
                }
                let values: [(
                    SceneScriptLayerMutation.Fields,
                    SceneDynamicLayerField,
                    SIMD3<Double>
                )] = [
                    (.origin, .origin, mutation.origin),
                    (.scale, .scale, mutation.scale),
                    (.angles, .angles, mutation.angles),
                ]
                for (field, targetField, value) in values where mutation.fields.contains(field) {
                    let target = SceneDynamicTarget.layer(
                        layerID: mutation.layerID, field: targetField
                    )
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument(
                            "conflicting authored layer mutation target"
                        ))
                    }
                    candidateAuthoredValues[target] = .vector3(
                        value.x, value.y, value.z
                    )
                }
                if mutation.fields.contains(.visibility) {
                    let target = SceneDynamicTarget.layer(
                        layerID: mutation.layerID, field: .visibility
                    )
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument(
                            "conflicting authored layer mutation target"
                        ))
                    }
                    candidateAuthoredValues[target] = .bool(mutation.visible)
                }
                continue
            }
            guard mutation.orderIndex >= 0,
                  mutation.alpha.isFinite, (0...1).contains(mutation.alpha),
                  mutation.pointSize.isFinite, (1...1024).contains(mutation.pointSize),
                  mutation.color.x.isFinite,
                  mutation.color.y.isFinite, mutation.color.z.isFinite,
                  mutation.text.utf8.count <= 4_096,
                  mutation.font.utf8.count <= 1_024 else {
                return .failure(.invalidArgument("invalid dynamic layer mutation"))
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
        authoredLayerValues = candidateAuthoredValues
        return .success(())
    }

    private static func vector3(
        _ values: [Float]?,
        fallback: [Double]
    ) -> SceneDynamicValue {
        let resolved = values?.map(Double.init) ?? fallback
        let padded = (0..<3).map { index in
            index < resolved.count ? resolved[index] : fallback[index]
        }
        return .vector3(padded[0], padded[1], padded[2])
    }
}
