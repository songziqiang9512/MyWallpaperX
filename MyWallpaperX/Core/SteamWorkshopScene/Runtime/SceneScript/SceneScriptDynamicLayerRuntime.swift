import Foundation

nonisolated struct SceneScriptLayerTopologySnapshot: Sendable {
    let dynamicLayers: [SceneRenderDescriptor.Layer]
    let renderOrderLayerIDs: [Int]
    let authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue]
    let dynamicMaterialColorTargetsByLayerID: [Int: SceneDynamicTarget]

    func resolvingDynamicMaterialColors(
        from values: SceneDynamicSnapshot
    ) -> Self {
        var resolvedLayers = dynamicLayers
        for index in resolvedLayers.indices {
            let layerID = resolvedLayers[index].id
            guard let target = dynamicMaterialColorTargetsByLayerID[layerID],
                  case let .vector3(red, green, blue)? = values[target]?.value,
                  red.isFinite, green.isFinite, blue.isFinite else { continue }
            resolvedLayers[index].colorRGB = [red, green, blue].map {
                Float(max(0, min($0, 1)))
            }
        }
        return .init(
            dynamicLayers: resolvedLayers,
            renderOrderLayerIDs: renderOrderLayerIDs,
            authoredLayerValues: authoredLayerValues,
            dynamicMaterialColorTargetsByLayerID:
                dynamicMaterialColorTargetsByLayerID
        )
    }
}

nonisolated struct SceneScriptDynamicImageLayerTemplate: Sendable {
    let modelPath: String
    let renderSizeWH: [Float]
    let materialColorTarget: SceneDynamicTarget?
}

nonisolated struct SceneScriptLayerMutationOwnerFailure: Sendable {
    let ownerTarget: SceneDynamicTarget?
    let failure: SceneScriptScalarRuntimeFailure
}

nonisolated struct SceneScriptLayerMutationApplyOutcome: Sendable {
    let committedMutationCount: Int
    let failures: [SceneScriptLayerMutationOwnerFailure]
}

/// Opaque, side-effect-free candidate state. Rendering keeps using the snapshot
/// captured before this plan; committing it only publishes accepted owner
/// mutations to the next frame.
nonisolated struct SceneScriptLayerMutationPlan: Sendable {
    let outcome: SceneScriptLayerMutationApplyOutcome
    fileprivate let order: [Int]
    fileprivate let dynamicLayersByID: [Int: SceneRenderDescriptor.Layer]
    fileprivate let authoredLayerValues:
        [SceneDynamicTarget: SceneDynamicValue]
    fileprivate let authoredDefinitionOrder: [SceneDynamicTarget]
    fileprivate let authoredDefinitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition]
}

nonisolated struct SceneScriptOwnerEffectsAdmission: Sendable {
    let admittedEffects: [SceneScriptOwnerEffects]
    let rejectedOwners: [SceneScriptLayerMutationOwnerFailure]
    let layerPlan: SceneScriptLayerMutationPlan
}

nonisolated struct SceneScriptOwnerEffectsFixedPointAdmission: Sendable {
    let admission: SceneScriptOwnerEffectsAdmission
    let externallyRejectedOwners: Set<SceneDynamicTarget>
}

/// Launch-scoped layer mutation transaction. VM callbacks publish bounded
/// mutations; rendering reads one immutable snapshot and commits successful
/// dynamic topology or authored fields only after the current frame.
nonisolated final class SceneScriptDynamicLayerRuntime: @unchecked Sendable {
    var authoredLayerDefinitions: [SceneDynamicTargetDefinition] {
        authoredDefinitionOrder.compactMap { authoredDefinitionsByTarget[$0] }
    }
    private let authoredLayerIDs: Set<Int>
    private let authoredLayersByID: [Int: SceneRenderDescriptor.Layer]
    private var authoredDefinitionOrder: [SceneDynamicTarget] = []
    private var authoredDefinitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition] = [:]
    private var order: [Int]
    private var dynamicLayersByID: [Int: SceneRenderDescriptor.Layer] = [:]
    private var authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    private let dynamicImageTemplates:
        [String: SceneScriptDynamicImageLayerTemplate]

    init(
        descriptor: SceneRenderDescriptor,
        authoredMutationLayerIDs: Set<Int>,
        dynamicImageTemplates:
            [String: SceneScriptDynamicImageLayerTemplate] = [:]
    ) {
        authoredLayerIDs = Set(descriptor.layers.map(\.id))
        authoredLayersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        self.dynamicImageTemplates = dynamicImageTemplates
        order = descriptor.renderOrderLayerIDs
        let initialDefinitions = descriptor.layers.filter {
            authoredMutationLayerIDs.contains($0.id)
        }.flatMap {
            layer -> [SceneDynamicTargetDefinition] in
            Self.initialAuthoredDefinitions(for: layer)
        }
        authoredDefinitionOrder = initialDefinitions.map(\.target)
        authoredDefinitionsByTarget = Dictionary(
            uniqueKeysWithValues: initialDefinitions.map { ($0.target, $0) }
        )
    }

    func snapshot() -> SceneScriptLayerTopologySnapshot {
        let colorTargets: [(Int, SceneDynamicTarget)] = dynamicLayersByID
            .compactMap { layerID, layer in
                guard let modelPath = layer.imagePath,
                      let target = dynamicImageTemplates[
                        modelPath.lowercased()
                      ]?.materialColorTarget else { return nil }
                return (layerID, target)
            }
        let dynamicMaterialColorTargetsByLayerID = Dictionary(
            uniqueKeysWithValues: colorTargets
        )
        return .init(
            dynamicLayers: order.compactMap { dynamicLayersByID[$0] },
            renderOrderLayerIDs: order,
            authoredLayerValues: authoredLayerValues,
            dynamicMaterialColorTargetsByLayerID:
                dynamicMaterialColorTargetsByLayerID
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
        var candidateDefinitionOrder = authoredDefinitionOrder
        var candidateDefinitions = authoredDefinitionsByTarget
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
                      let authoredLayer = authoredLayersByID[mutation.layerID],
                      authoredLayerIDs.contains(mutation.layerID),
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
                    Self.ensureDefinition(
                        for: target,
                        layer: authoredLayer,
                        order: &candidateDefinitionOrder,
                        definitions: &candidateDefinitions
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
                    Self.ensureDefinition(
                        for: target,
                        layer: authoredLayer,
                        order: &candidateDefinitionOrder,
                        definitions: &candidateDefinitions
                    )
                }
                if mutation.fields.contains(.text) {
                    guard authoredLayer.contentKind == "text",
                          authoredLayer.text != nil,
                          authoredLayer.textStyle != nil,
                          mutation.text.utf8.count <= 4_096,
                          !mutation.text.contains("\0") else {
                        return .failure(.invalidArgument(
                            "invalid authored text layer mutation"
                        ))
                    }
                    let target = SceneDynamicTarget.text(
                        layerID: mutation.layerID, field: .content
                    )
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument(
                            "conflicting authored layer mutation target"
                        ))
                    }
                    candidateAuthoredValues[target] = .string(mutation.text)
                    Self.ensureDefinition(
                        for: target,
                        layer: authoredLayer,
                        order: &candidateDefinitionOrder,
                        definitions: &candidateDefinitions
                    )
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
                let layer: SceneRenderDescriptor.Layer?
                if let assetPath = mutation.assetPath {
                    guard let template = dynamicImageTemplates[
                        assetPath.lowercased()
                    ] else {
                        return .failure(.invalidArgument(
                            "dynamic image resource is not launch-ready"
                        ))
                    }
                    layer = .dynamicImage(mutation, template: template)
                } else {
                    layer = .dynamicText(mutation)
                }
                guard let layer else {
                    return .failure(.invalidArgument("dynamic layer is invalid"))
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
        authoredDefinitionOrder = candidateDefinitionOrder
        authoredDefinitionsByTarget = candidateDefinitions
        return .success(())
    }

    /// Product frame commit keeps each VM owner atomic while allowing
    /// disjoint owners to survive a bad peer mutation. Authored target
    /// conflicts remain hard for the later owner in authored execution order.
    func applyIsolatingOwners(
        _ mutations: [SceneScriptLayerMutation]
    ) -> SceneScriptLayerMutationApplyOutcome {
        let plan = preflightIsolatingOwners(mutations)
        commit(plan)
        return plan.outcome
    }

    func preflightIsolatingOwners(
        _ mutations: [SceneScriptLayerMutation]
    ) -> SceneScriptLayerMutationPlan {
        let originalOrder = order
        let originalLayers = dynamicLayersByID
        let originalValues = authoredLayerValues
        let originalDefinitionOrder = authoredDefinitionOrder
        let originalDefinitions = authoredDefinitionsByTarget
        let outcome = applyIsolatingOwnersToCurrentState(mutations)
        let plan = SceneScriptLayerMutationPlan(
            outcome: outcome,
            order: order,
            dynamicLayersByID: dynamicLayersByID,
            authoredLayerValues: authoredLayerValues,
            authoredDefinitionOrder: authoredDefinitionOrder,
            authoredDefinitionsByTarget: authoredDefinitionsByTarget
        )
        order = originalOrder
        dynamicLayersByID = originalLayers
        authoredLayerValues = originalValues
        authoredDefinitionOrder = originalDefinitionOrder
        authoredDefinitionsByTarget = originalDefinitions
        return plan
    }

    func preflightOwnerEffects(
        _ effects: [SceneScriptOwnerEffects]
    ) -> SceneScriptOwnerEffectsAdmission {
        var admitted = effects
        var rejected: [SceneScriptLayerMutationOwnerFailure] = []
        var rejectedTargets = Set<SceneDynamicTarget>()
        var plan = preflightIsolatingOwners(
            admitted.flatMap(\.layerMutations)
        )
        while !plan.outcome.failures.isEmpty {
            var newlyRejected = Set<SceneDynamicTarget>()
            for failure in plan.outcome.failures {
                if let owner = failure.ownerTarget {
                    newlyRejected.insert(owner)
                    rejected.append(failure)
                } else {
                    let affected = admitted.compactMap { candidate in
                        candidate.layerMutations.isEmpty
                            ? nil : candidate.ownerTarget
                    }
                    newlyRejected.formUnion(affected)
                    rejected.append(contentsOf: affected.map {
                        .init(ownerTarget: $0, failure: failure.failure)
                    })
                }
            }
            newlyRejected.subtract(rejectedTargets)
            guard !newlyRejected.isEmpty else { break }
            rejectedTargets.formUnion(newlyRejected)
            admitted.removeAll {
                rejectedTargets.contains($0.ownerTarget)
            }
            plan = preflightIsolatingOwners(
                admitted.flatMap(\.layerMutations)
            )
        }
        return .init(
            admittedEffects: admitted,
            rejectedOwners: rejected,
            layerPlan: plan
        )
    }

    /// External command validation can remove an owner whose layer mutations
    /// made a later owner admissible. Rebuild from the original authored order
    /// until command rejection and layer admission reach the same fixed point.
    func preflightOwnerEffectsToFixedPoint(
        _ effects: [SceneScriptOwnerEffects],
        rejectingExternally: ([SceneScriptOwnerEffects])
            -> Set<SceneDynamicTarget>
    ) -> SceneScriptOwnerEffectsFixedPointAdmission {
        var externallyRejected = Set<SceneDynamicTarget>()
        while true {
            let candidates = effects.filter {
                !externallyRejected.contains($0.ownerTarget)
            }
            let admission = preflightOwnerEffects(candidates)
            let admittedOwners = Set(admission.admittedEffects.map(
                \.ownerTarget
            ))
            var newlyRejected = rejectingExternally(
                admission.admittedEffects
            ).intersection(admittedOwners)
            newlyRejected.subtract(externallyRejected)
            guard !newlyRejected.isEmpty else {
                return .init(
                    admission: admission,
                    externallyRejectedOwners: externallyRejected
                )
            }
            externallyRejected.formUnion(newlyRejected)
        }
    }

    func commit(_ plan: SceneScriptLayerMutationPlan) {
        order = plan.order
        dynamicLayersByID = plan.dynamicLayersByID
        authoredLayerValues = plan.authoredLayerValues
        authoredDefinitionOrder = plan.authoredDefinitionOrder
        authoredDefinitionsByTarget = plan.authoredDefinitionsByTarget
    }

    private func applyIsolatingOwnersToCurrentState(
        _ mutations: [SceneScriptLayerMutation]
    ) -> SceneScriptLayerMutationApplyOutcome {
        guard mutations.count <= 192 else {
            return .init(
                committedMutationCount: 0,
                failures: [.init(
                    ownerTarget: nil,
                    failure: .mutationOverflow(
                        "frame layer mutation budget exceeded"
                    )
                )]
            )
        }
        var ownerOrder: [SceneDynamicTarget?] = []
        var grouped: [SceneDynamicTarget?: [SceneScriptLayerMutation]] = [:]
        for mutation in mutations {
            let owner = mutation.ownerTarget
            if grouped[owner] == nil { ownerOrder.append(owner) }
            grouped[owner, default: []].append(mutation)
        }
        var claimedAuthoredTargets = Set<SceneDynamicTarget>()
        var failures: [SceneScriptLayerMutationOwnerFailure] = []
        var committedMutationCount = 0
        for owner in ownerOrder {
            guard let batch = grouped[owner] else { continue }
            let targets = Set(batch.flatMap(Self.authoredTargets))
            if !claimedAuthoredTargets.isDisjoint(with: targets) {
                failures.append(.init(
                    ownerTarget: owner,
                    failure: .invalidArgument(
                        "conflicting authored layer mutation owner"
                    )
                ))
                continue
            }
            switch apply(batch) {
            case .success:
                claimedAuthoredTargets.formUnion(targets)
                committedMutationCount += batch.count
            case let .failure(failure):
                failures.append(.init(
                    ownerTarget: owner, failure: failure
                ))
            }
        }
        return .init(
            committedMutationCount: committedMutationCount,
            failures: failures
        )
    }

    private static func authoredTargets(
        _ mutation: SceneScriptLayerMutation
    ) -> [SceneDynamicTarget] {
        guard !mutation.isDynamic, mutation.kind == .upsert else { return [] }
        var targets: [SceneDynamicTarget] = []
        if mutation.fields.contains(.origin) {
            targets.append(.layer(layerID: mutation.layerID, field: .origin))
        }
        if mutation.fields.contains(.scale) {
            targets.append(.layer(layerID: mutation.layerID, field: .scale))
        }
        if mutation.fields.contains(.angles) {
            targets.append(.layer(layerID: mutation.layerID, field: .angles))
        }
        if mutation.fields.contains(.visibility) {
            targets.append(.layer(
                layerID: mutation.layerID, field: .visibility
            ))
        }
        if mutation.fields.contains(.text) {
            targets.append(.text(layerID: mutation.layerID, field: .content))
        }
        return targets
    }

    private static func initialAuthoredDefinitions(
        for layer: SceneRenderDescriptor.Layer
    ) -> [SceneDynamicTargetDefinition] {
        [
            .layer(layerID: layer.id, field: .origin),
            .layer(layerID: layer.id, field: .scale),
            .layer(layerID: layer.id, field: .angles),
            .layer(layerID: layer.id, field: .visibility),
        ].compactMap { definition(for: $0, layer: layer) }
    }

    private static func ensureDefinition(
        for target: SceneDynamicTarget,
        layer: SceneRenderDescriptor.Layer,
        order: inout [SceneDynamicTarget],
        definitions: inout [SceneDynamicTarget: SceneDynamicTargetDefinition]
    ) {
        guard definitions[target] == nil,
              let definition = definition(for: target, layer: layer) else {
            return
        }
        definitions[target] = definition
        order.append(target)
    }

    private static func definition(
        for target: SceneDynamicTarget,
        layer: SceneRenderDescriptor.Layer
    ) -> SceneDynamicTargetDefinition? {
        switch target {
        case let .layer(layerID, .origin) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.originXYZ, fallback: [0, 0, 0])
            )
        case let .layer(layerID, .scale) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.scaleXYZ, fallback: [1, 1, 1])
            )
        case let .layer(layerID, .angles) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.anglesXYZ, fallback: [0, 0, 0])
            )
        case let .layer(layerID, .visibility) where layerID == layer.id:
            .init(
                target: target, valueType: .bool,
                authoredValue: .bool(layer.visible ?? true)
            )
        case let .text(layerID, .content)
            where layerID == layer.id && layer.contentKind == "text"
                && layer.textStyle != nil:
            .init(
                target: target, valueType: .string,
                authoredValue: .string(layer.text ?? "")
            )
        default:
            nil
        }
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
