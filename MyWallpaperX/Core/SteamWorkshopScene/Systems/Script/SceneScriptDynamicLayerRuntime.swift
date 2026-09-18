import Foundation

/// Launch-scoped layer mutation transaction. VM callbacks publish bounded
/// mutations; rendering reads one immutable snapshot and commits successful
/// dynamic topology or authored fields only after the current frame.
nonisolated final class SceneScriptDynamicLayerRuntime: @unchecked Sendable {
    var authoredLayerDefinitions: [SceneDynamicTargetDefinition] {
        authoredDefinitionOrder.compactMap { authoredDefinitionsByTarget[$0] }
    }
    /// Bumps only when the set or order of authored dynamic definitions is
    /// published. Frame-varying values do not invalidate the launch schema.
    private(set) var authoredDefinitionRevision: UInt64 = 0
    /// Bumps when an admitted dynamic layer mutation changes the projected
    /// descriptor. Static descriptor indexes and world frames can then be
    /// reused between revisions without treating every frame as a rebuild.
    private(set) var topologyRevision: UInt64 = 0
    private let authoredLayerIDs: Set<Int>
    private let authoredLayersByID: [Int: SceneRenderDescriptor.Layer]
    private var authoredDefinitionOrder: [SceneDynamicTarget] = []
    private var authoredDefinitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition] = [:]
    private var order: [Int]
    private var dynamicLayersByID: [Int: SceneRenderDescriptor.Layer] = [:]
    private var destroyedAuthoredLayerIDs: Set<Int> = []
    private var authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    private var cachedSnapshotTopologyRevision: UInt64?
    private var cachedDynamicLayers: [SceneRenderDescriptor.Layer] = []
    private var cachedDynamicMaterialColorTargetsByLayerID:
        [Int: SceneDynamicTarget] = [:]
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
        if cachedSnapshotTopologyRevision != topologyRevision {
            cachedDynamicLayers = order.compactMap { dynamicLayersByID[$0] }
            let colorTargets: [(Int, SceneDynamicTarget)] = dynamicLayersByID
                .compactMap { layerID, layer in
                    guard let modelPath = layer.imagePath,
                          let target = dynamicImageTemplates[
                            modelPath.lowercased()
                          ]?.materialColorTarget else { return nil }
                    return (layerID, target)
                }
            cachedDynamicMaterialColorTargetsByLayerID = Dictionary(
                uniqueKeysWithValues: colorTargets
            )
            cachedSnapshotTopologyRevision = topologyRevision
        }
        return .init(
            topologyRevision: topologyRevision,
            dynamicLayers: cachedDynamicLayers,
            renderOrderLayerIDs: order,
            destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs,
            authoredLayerValues: authoredLayerValues,
            dynamicMaterialColorTargetsByLayerID:
                cachedDynamicMaterialColorTargetsByLayerID
        )
    }

    func apply(
        _ mutations: [SceneScriptLayerMutation]
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        apply(mutations, publishingTopologyRevision: true)
    }

    private func apply(
        _ mutations: [SceneScriptLayerMutation],
        publishingTopologyRevision: Bool
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        guard mutations.count <= 512 else {
            return .failure(.mutationOverflow("frame layer mutation budget exceeded"))
        }
        var candidateOrder = order
        var candidateLayers = dynamicLayersByID
        var candidateDestroyedAuthoredLayerIDs = destroyedAuthoredLayerIDs
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
                guard let authoredLayer = authoredLayersByID[mutation.layerID],
                      authoredLayerIDs.contains(mutation.layerID),
                      mutation.fields.isSubset(of: .authoredFields) else {
                    return .failure(.invalidArgument("invalid authored layer mutation"))
                }
                if mutation.kind == .destroy {
                    guard mutation.fields.isEmpty,
                          authoredLayer.childLayerIDs.isEmpty else {
                        return .failure(.invalidArgument(
                            "invalid authored layer destroy"
                        ))
                    }
                    candidateDestroyedAuthoredLayerIDs.insert(mutation.layerID)
                    candidateOrder.removeAll { $0 == mutation.layerID }
                    candidateAuthoredValues = candidateAuthoredValues.filter {
                        Self.layerID(for: $0.key) != mutation.layerID
                    }
                    continue
                }
                // An order-only authored mutation is a script-driven sort: the
                // C catalog shifted its order atomically, and the reported
                // index is the new position. Move the layer; every other
                // layer shifts implicitly because both sides start from the
                // same pre-state.
                if mutation.fields.isEmpty {
                    guard mutation.kind == .upsert,
                          mutation.orderIndex >= 0,
                          !candidateDestroyedAuthoredLayerIDs.contains(
                              mutation.layerID
                          ),
                          let current = candidateOrder.firstIndex(
                              of: mutation.layerID
                          ) else {
                        return .failure(.invalidArgument(
                            "invalid authored layer sort"
                        ))
                    }
                    candidateOrder.remove(at: current)
                    candidateOrder.insert(
                        mutation.layerID,
                        at: min(mutation.orderIndex, candidateOrder.count)
                    )
                    continue
                }
                guard mutation.kind == .upsert,
                      !candidateDestroyedAuthoredLayerIDs.contains(
                          mutation.layerID
                      ),
                      !mutation.fields.isEmpty else {
                    return .failure(.invalidArgument(
                        "invalid authored layer mutation"
                    ))
                }
                let values: [(
                    SceneScriptLayerMutation.Fields,
                    SceneDynamicLayerField,
                    SIMD3<Double>
                )] = [
                    (.origin, .origin, mutation.origin),
                    (.scale, .scale, mutation.scale),
                    (.angles, .angles, mutation.angles),
                    (.color, .color, mutation.color),
                ]
                for (field, targetField, value) in values where mutation.fields.contains(field) {
                    let target: SceneDynamicTarget = targetField == .color
                        && authoredLayer.contentKind == "text"
                        ? .text(layerID: mutation.layerID, field: .color)
                        : .layer(layerID: mutation.layerID, field: targetField)
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
                if mutation.fields.contains(.alpha) {
                    guard mutation.alpha.isFinite, (0...1).contains(mutation.alpha) else {
                        return .failure(.invalidArgument("invalid authored layer alpha"))
                    }
                    let target = SceneDynamicTarget.layer(layerID: mutation.layerID, field: .alpha)
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument("conflicting authored layer mutation target"))
                    }
                    candidateAuthoredValues[target] = .scalar(mutation.alpha)
                    Self.ensureDefinition(for: target, layer: authoredLayer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
                }
                if mutation.fields.contains(.color),
                   ![mutation.color.x, mutation.color.y, mutation.color.z]
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                    return .failure(.invalidArgument("invalid authored layer color"))
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
                if mutation.fields.contains(.font) {
                    guard authoredLayer.contentKind == "text",
                          authoredLayer.textStyle != nil,
                          !mutation.font.isEmpty,
                          mutation.font.utf8.count <= 1_024,
                          !mutation.font.contains("\0") else {
                        return .failure(.invalidArgument(
                            "invalid authored text font mutation"
                        ))
                    }
                    let target = SceneDynamicTarget.text(
                        layerID: mutation.layerID, field: .font
                    )
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument(
                            "conflicting authored layer mutation target"
                        ))
                    }
                    candidateAuthoredValues[target] = .string(mutation.font)
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
        let dynamicTopologyChanged = Self.dynamicTopologyChanged(
            currentOrder: order,
            currentLayers: dynamicLayersByID,
            candidateOrder: candidateOrder,
            candidateLayers: candidateLayers
        )
        order = candidateOrder
        dynamicLayersByID = candidateLayers
        destroyedAuthoredLayerIDs = candidateDestroyedAuthoredLayerIDs
        authoredLayerValues = candidateAuthoredValues
        authoredDefinitionOrder = candidateDefinitionOrder
        authoredDefinitionsByTarget = candidateDefinitions
        if publishingTopologyRevision,
           dynamicTopologyChanged {
            topologyRevision &+= 1
        }
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
        let originalDestroyedAuthoredLayerIDs = destroyedAuthoredLayerIDs
        let originalValues = authoredLayerValues
        let originalDefinitionOrder = authoredDefinitionOrder
        let originalDefinitions = authoredDefinitionsByTarget
        let outcome = applyIsolatingOwnersToCurrentState(mutations)
        let dynamicTopologyChanged = Self.dynamicTopologyChanged(
            currentOrder: originalOrder,
            currentLayers: originalLayers,
            candidateOrder: order,
            candidateLayers: dynamicLayersByID
        )
        let plan = SceneScriptLayerMutationPlan(
            outcome: outcome,
            order: order,
            dynamicLayersByID: dynamicLayersByID,
            destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs,
            authoredLayerValues: authoredLayerValues,
            authoredDefinitionOrder: authoredDefinitionOrder,
            authoredDefinitionsByTarget: authoredDefinitionsByTarget,
            dynamicTopologyChanged: dynamicTopologyChanged
        )
        order = originalOrder
        dynamicLayersByID = originalLayers
        destroyedAuthoredLayerIDs = originalDestroyedAuthoredLayerIDs
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
        // Definitions are append-only for the lifetime of a launch. Their
        // stable order is therefore the cheapest complete invalidation key;
        // authored values remain frame-varying state and do not invalidate
        // the launch schema.
        let definitionsChanged = authoredDefinitionOrder
            != plan.authoredDefinitionOrder
        order = plan.order
        dynamicLayersByID = plan.dynamicLayersByID
        destroyedAuthoredLayerIDs = plan.destroyedAuthoredLayerIDs
        authoredLayerValues = plan.authoredLayerValues
        authoredDefinitionOrder = plan.authoredDefinitionOrder
        authoredDefinitionsByTarget = plan.authoredDefinitionsByTarget
        if plan.dynamicTopologyChanged {
            topologyRevision &+= 1
        }
        if definitionsChanged {
            authoredDefinitionRevision &+= 1
        }
    }

    private func applyIsolatingOwnersToCurrentState(
        _ mutations: [SceneScriptLayerMutation]
    ) -> SceneScriptLayerMutationApplyOutcome {
        guard mutations.count <= 512 else {
            return .init(
                committedMutationCount: 0,
                committedDynamicMutationCount: 0,
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
        var claimedAuthoredValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneScriptLayerMutationOwnerFailure] = []
        var committedMutationCount = 0
        var committedDynamicMutationCount = 0
        for owner in ownerOrder {
            guard let batch = grouped[owner] else { continue }
            let authoredValues = batch.flatMap(Self.authoredValues)
            let hasConflict = authoredValues.contains { target, value in
                claimedAuthoredValues[target].map { $0 != value } ?? false
            }
            if hasConflict {
                failures.append(.init(
                    ownerTarget: owner,
                    failure: .invalidArgument(
                        "conflicting authored layer mutation owner"
                    )
                ))
                continue
            }
            switch apply(batch, publishingTopologyRevision: false) {
            case .success:
                for (target, value) in authoredValues
                where claimedAuthoredValues[target] == nil {
                    claimedAuthoredValues[target] = value
                }
                committedMutationCount += batch.count
                committedDynamicMutationCount += batch.filter(\.isDynamic).count
            case let .failure(failure):
                failures.append(.init(
                    ownerTarget: owner, failure: failure
                ))
            }
        }
        return .init(
            committedMutationCount: committedMutationCount,
            committedDynamicMutationCount: committedDynamicMutationCount,
            failures: failures
        )
    }

    private static func authoredTargets(
        _ mutation: SceneScriptLayerMutation
    ) -> [SceneDynamicTarget] {
        authoredValues(mutation).map(\.0)
    }

    private static func layerID(for target: SceneDynamicTarget) -> Int? {
        switch target {
        case let .layer(layerID, _), let .text(layerID, _):
            layerID
        default:
            nil
        }
    }

    /// Multiple authored owners may intentionally publish the same field and
    /// value (for example, duplicated controller layers in one authored
    /// scene). Such writes are idempotent and preserve authored order. A later
    /// owner that disagrees remains a hard conflict because accepting it would
    /// make the final value depend on an implicit last-writer policy.
    private static func authoredValues(
        _ mutation: SceneScriptLayerMutation
    ) -> [(SceneDynamicTarget, SceneDynamicValue)] {
        guard !mutation.isDynamic, mutation.kind == .upsert else { return [] }
        var values: [(SceneDynamicTarget, SceneDynamicValue)] = []
        if mutation.fields.contains(.alpha) {
            values.append((.layer(layerID: mutation.layerID, field: .alpha), .scalar(mutation.alpha)))
        }
        if mutation.fields.contains(.color) {
            values.append((.layer(layerID: mutation.layerID, field: .color),
                .vector3(mutation.color.x, mutation.color.y, mutation.color.z)))
        }
        if mutation.fields.contains(.origin) {
            values.append((
                .layer(layerID: mutation.layerID, field: .origin),
                .vector3(mutation.origin.x, mutation.origin.y, mutation.origin.z)
            ))
        }
        if mutation.fields.contains(.scale) {
            values.append((
                .layer(layerID: mutation.layerID, field: .scale),
                .vector3(mutation.scale.x, mutation.scale.y, mutation.scale.z)
            ))
        }
        if mutation.fields.contains(.angles) {
            values.append((
                .layer(layerID: mutation.layerID, field: .angles),
                .vector3(mutation.angles.x, mutation.angles.y, mutation.angles.z)
            ))
        }
        if mutation.fields.contains(.visibility) {
            values.append((
                .layer(layerID: mutation.layerID, field: .visibility),
                .bool(mutation.visible)
            ))
        }
        if mutation.fields.contains(.text) {
            values.append((
                .text(layerID: mutation.layerID, field: .content),
                .string(mutation.text)
            ))
        }
        if mutation.fields.contains(.font) {
            values.append((
                .text(layerID: mutation.layerID, field: .font),
                .string(mutation.font)
            ))
        }
        return values
    }

    /// Dynamic upserts carry their complete frame value record, but that does
    /// not make them a new graph topology. Only identity/order or the
    /// structural resource lane invalidates the renderer's prepared
    /// descriptor projection. Position, scale, angles, visibility, alpha,
    /// color, text and font are applied to the cached projection per frame.
    private static func dynamicTopologyChanged(
        currentOrder: [Int],
        currentLayers: [Int: SceneRenderDescriptor.Layer],
        candidateOrder: [Int],
        candidateLayers: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        guard currentOrder == candidateOrder,
              currentLayers.count == candidateLayers.count,
              currentLayers.keys == candidateLayers.keys else {
            return true
        }
        for layerID in currentLayers.keys {
            guard let current = currentLayers[layerID],
                  let candidate = candidateLayers[layerID],
                  current.id == candidate.id,
                  current.contentKind == candidate.contentKind,
                  current.imagePath == candidate.imagePath else {
                return true
            }
        }
        return false
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
        case let .layer(layerID, .alpha) where layerID == layer.id:
            .init(target: target, valueType: .scalar, authoredValue: .scalar(layer.alpha ?? 1))
        case let .layer(layerID, .color) where layerID == layer.id:
            .init(target: target, valueType: .vector3,
                  authoredValue: vector3(layer.colorRGB, fallback: [1, 1, 1]))
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
        case let .text(layerID, .font)
            where layerID == layer.id && layer.contentKind == "text"
                && layer.textStyle != nil:
            .init(
                target: target, valueType: .string,
                authoredValue: .string(layer.textStyle?.fontPath ?? "")
            )
        case let .text(layerID, .color) where layerID == layer.id && layer.contentKind == "text":
            .init(target: target, valueType: .vector3,
                  authoredValue: vector3(layer.textStyle?.colorRGB, fallback: [1, 1, 1]))
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
