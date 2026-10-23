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
    private(set) var particlePlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    private let authoredLayerIDs: Set<Int>
    private let authoredLayersByID: [Int: SceneRenderDescriptor.Layer]
    private let cameraOriginInputLayerID: Int?
    private let cameraOriginClipSpan: (nearZ: Double, farZ: Double)
    private let supportsCompositionPerspective: Bool
    private var authoredDefinitionOrder: [SceneDynamicTarget] = []
    private var authoredDefinitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition] = [:]
    private var order: [Int]
    private var dynamicLayersByID: [Int: SceneRenderDescriptor.Layer] = [:]
    private var dynamicLayerCreatorTargetsByID: [Int: SceneDynamicTarget] = [:]
    private var textTemplateIdentitiesByLayerID: [Int: UInt64] = [:]
    private let textTemplates: [UInt64: SceneScriptPreparedTextTemplate]
    private var dynamicLayerValueRevision: UInt64 = 0
    private var destroyedAuthoredLayerIDs: Set<Int> = []
    private var authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    private var cachedSnapshotTopologyRevision: UInt64?
    private var cachedSnapshotDynamicLayerValueRevision: UInt64?
    private var cachedDynamicLayers: [SceneRenderDescriptor.Layer] = []
    private let preparedResourceLayerTemplates:
        [String: SceneScriptPreparedResourceLayerTemplate]
    private let layerOrderProjection: (@Sendable (Set<UInt64>)
        -> Result<[Int]?, SceneScriptScalarRuntimeFailure>)?

    init(
        descriptor: SceneRenderDescriptor,
        authoredMutationLayerIDs: Set<Int>,
        preparedResourceLayerTemplates:
            [String: SceneScriptPreparedResourceLayerTemplate] = [:],
        textTemplates: [UInt64: SceneScriptPreparedTextTemplate] = [:],
        layerOrderProjection: (@Sendable (Set<UInt64>)
            -> Result<[Int]?, SceneScriptScalarRuntimeFailure>)? = nil
    ) {
        authoredLayerIDs = Set(descriptor.layers.map(\.id))
        cameraOriginInputLayerID = descriptor.camera.default2DOriginInputLayerID
        cameraOriginClipSpan = (Double(descriptor.camera.nearZ), Double(descriptor.camera.farZ))
        supportsCompositionPerspective = (descriptor.camera.orthoHeight ?? 0) > 0
        authoredLayersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        self.preparedResourceLayerTemplates = preparedResourceLayerTemplates
        self.textTemplates = textTemplates
        self.layerOrderProjection = layerOrderProjection
        order = descriptor.renderOrderLayerIDs
        let initialDefinitions = descriptor.layers.flatMap { layer -> [SceneDynamicTargetDefinition] in
            var definitions = authoredMutationLayerIDs.contains(layer.id)
                ? Self.initialAuthoredDefinitions(for: layer)
                : [Self.definition(for: .layer(layerID: layer.id, field: .visibility), layer: layer)].compactMap { $0 }
            // A prepared authored handle may receive its first visibility write
            // this cadence. Register the typed lane before callbacks, including
            // ancestor containers, so the shared snapshot can consume it now.
            if let alpha = Self.definition(for: .particle(layerID: layer.id, field: .alpha), layer: layer) {
                definitions.append(alpha)
            }
            guard let cameraLayerID = descriptor.camera.default2DOriginInputLayerID else { return definitions }
            return definitions.filter { $0.target != .layer(layerID: cameraLayerID, field: .origin) }
        }
        authoredDefinitionOrder = initialDefinitions.map(\.target)
        authoredDefinitionsByTarget = Dictionary(
            uniqueKeysWithValues: initialDefinitions.map { ($0.target, $0) }
        )
    }

    /// Rebind an existing prepared property producer to accepted clone targets.
    /// Values remain owned by liveState; no property decoding or second evaluator.
    func projectPreparedTextUserValues(
        from values: [SceneDynamicTarget: SceneDynamicValue],
        previousValue: (SceneDynamicTarget) -> SceneDynamicValue? = { _ in nil }
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        guard !textTemplateIdentitiesByLayerID.isEmpty else { return values }
        var projected = values
        for (layerID, identity) in textTemplateIdentitiesByLayerID {
            guard let template = textTemplates[identity], template.outerUserInstruction != nil,
                  let value = values[template.sourceTarget] else { continue }
            let target = SceneDynamicTarget.text(layerID: layerID, field: .content)
            if case let .string(text) = value, SceneScriptLayerMutation.acceptsDynamicText(text) {
                projected[target] = value
            } else if case let .string(text)? = previousValue(target),
                      SceneScriptLayerMutation.acceptsDynamicText(text) {
                projected[target] = .string(text)
            } else {
                projected[target] = .string(template.authoredSeed)
            }
        }
        return projected
    }

    /// Interest is the committed template membership, not a catalog-wide scan.
    func preparedTextValues(in snapshot: SceneDynamicSnapshot) -> [Int: String] {
        var values: [Int: String] = [:]
        for layerID in textTemplateIdentitiesByLayerID.keys {
            if case let .string(value)? = snapshot[.text(layerID: layerID, field: .content)]?.value {
                values[layerID] = value
            }
        }
        return values
    }

    func snapshot() -> SceneScriptLayerTopologySnapshot {
        if cachedSnapshotTopologyRevision != topologyRevision {
            cachedSnapshotTopologyRevision = topologyRevision
            cachedSnapshotDynamicLayerValueRevision = nil
        }
        // Value-only upserts leave prepared topology stable but must publish
        // the next frame's transforms. Keep quiescent snapshots cached; only
        // an accepted dynamic mutation rebuilds the bounded layer records.
        if cachedSnapshotDynamicLayerValueRevision != dynamicLayerValueRevision {
            cachedDynamicLayers = order.compactMap { dynamicLayersByID[$0] }
            cachedSnapshotDynamicLayerValueRevision = dynamicLayerValueRevision
        }
        return .init(
            particlePlayback: particlePlayback,
            topologyRevision: topologyRevision,
            dynamicLayers: cachedDynamicLayers,
            renderOrderLayerIDs: order,
            destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs,
            authoredLayerValues: authoredLayerValues
        )
    }

    func apply(
        _ mutations: [SceneScriptLayerMutation]
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        let result = apply(mutations, publishingTopologyRevision: true)
        if case .success = result, mutations.contains(where: \.isDynamic) {
            dynamicLayerValueRevision &+= 1
        }
        return result.map { _ in () }
    }

    private struct AppliedChanges {
        let requiresRetirement: Bool
    }

    private func apply(
        _ mutations: [SceneScriptLayerMutation],
        publishingTopologyRevision: Bool,
        deferringFinalization: Bool = false,
        committedDestroyedAuthoredLayerIDs: Set<Int>? = nil
    ) -> Result<AppliedChanges, SceneScriptScalarRuntimeFailure> {
        guard mutations.count <= 512 else {
            return .failure(.mutationOverflow("frame layer mutation budget exceeded"))
        }
        var candidateOrder = order
        var candidateLayers = dynamicLayersByID
        var candidateCreators = dynamicLayerCreatorTargetsByID
        var candidateTextTemplates = textTemplateIdentitiesByLayerID
        var candidateDestroyedAuthoredLayerIDs = destroyedAuthoredLayerIDs
        var candidateAuthoredValues = authoredLayerValues
        var candidateDefinitionOrder = authoredDefinitionOrder
        var candidateDefinitions = authoredDefinitionsByTarget
        var authoredTargets = Set<SceneDynamicTarget>()
        // A parent can retire only when this same atomic owner request also
        // explicitly retires every live child. Each requested child is checked
        // in turn, so a deeper incomplete branch still rejects the whole owner.
        let requestedAuthoredDestroyIDs = Set(mutations.compactMap { mutation in
            !mutation.isDynamic && mutation.kind == .destroy ? mutation.layerID : nil
        })
        let previouslyRetiredIDs = committedDestroyedAuthoredLayerIDs
            ?? destroyedAuthoredLayerIDs
        // Values and membership validate locally. Only the domain journal
        // projects render order after the accepted owner set has settled.
        var requiresRetirement = false
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
                    guard mutation.fields.isEmpty, mutation.orderIndex >= 0,
                          authoredLayer.childLayerIDs.allSatisfy({
                              requestedAuthoredDestroyIDs.contains($0)
                                  || previouslyRetiredIDs.contains($0)
                          }),
                          !authoredLayersByID.values.contains(where: { child in
                              child.parentID == mutation.layerID
                                  && !requestedAuthoredDestroyIDs.contains(child.id)
                                  && !previouslyRetiredIDs.contains(child.id)
                          }),
                          !candidateDestroyedAuthoredLayerIDs.contains(mutation.layerID) else {
                        return .failure(.invalidArgument(
                            "invalid authored layer destroy"
                        ))
                    }
                    candidateDestroyedAuthoredLayerIDs.insert(mutation.layerID)
                    requiresRetirement = true
                    candidateAuthoredValues = candidateAuthoredValues.filter {
                        Self.layerID(for: $0.key, cameraOriginInputLayerID: cameraOriginInputLayerID) != mutation.layerID
                    }
                    continue
                }
                // Sort participation lives in the owner-effect package, so a
                // sort DTO can merge with attributes or be trimmed by a return.
                if mutation.fields.isEmpty {
                    guard mutation.kind == .upsert,
                          mutation.orderIndex >= 0,
                          !candidateDestroyedAuthoredLayerIDs.contains(
                              mutation.layerID
                          ),
                          candidateOrder.contains(mutation.layerID) else {
                        return .failure(.invalidArgument(
                            "invalid authored layer sort"
                        ))
                    }
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
                        : Self.authoredTransformTarget(layerID: mutation.layerID, field: targetField,
                            cameraOriginInputLayerID: cameraOriginInputLayerID)
                    if target == .camera(.origin),
                       !SceneDefault2DCameraInputProfile.acceptsOrigin([value.x, value.y, value.z],
                           nearZ: cameraOriginClipSpan.nearZ, farZ: cameraOriginClipSpan.farZ) {
                        return .failure(.invalidArgument("invalid default 2D camera origin mutation"))
                    }
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
                        cameraOriginInputLayerID: cameraOriginInputLayerID,
                        order: &candidateDefinitionOrder,
                        definitions: &candidateDefinitions
                    )
                }
                if mutation.fields.contains(.alpha) {
                    guard mutation.alpha.isFinite else {
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
                if mutation.fields.contains(.particleAlpha) {
                    guard authoredLayer.contentKind == "particle", mutation.particleAlpha.isFinite else {
                        return .failure(.invalidArgument("invalid authored particle instance alpha"))
                    }
                    let target = SceneDynamicTarget.particle(layerID: mutation.layerID, field: .alpha)
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument("conflicting authored particle instance alpha"))
                    }
                    candidateAuthoredValues[target] = .scalar(mutation.particleAlpha)
                    Self.ensureDefinition(for: target, layer: authoredLayer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
                }
                if mutation.fields.contains(.color),
                   ![mutation.color.x, mutation.color.y, mutation.color.z]
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                    return .failure(.invalidArgument("invalid authored layer color"))
                }
                if mutation.fields.contains(.perspective),
                   (mutation.perspective == nil || !authoredLayer.hasPerspectiveGeometryConsumer
                    || (authoredLayer.utilityLayer != nil && !supportsCompositionPerspective)) {
                    return .failure(.invalidArgument("layer has no perspective geometry consumer"))
                }
                for (flag, field, value): (SceneScriptLayerMutation.Fields, SceneDynamicLayerField, Bool)
                    in [(.visibility, .visibility, mutation.visible), (.solid, .solid, mutation.solid),
                        (.perspective, .perspective, mutation.perspective ?? false)]
                    where mutation.fields.contains(flag) {
                    let target = SceneDynamicTarget.layer(layerID: mutation.layerID, field: field)
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument("conflicting authored layer mutation target"))
                    }
                    candidateAuthoredValues[target] = .bool(value)
                    Self.ensureDefinition(for: target, layer: authoredLayer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
                }
                guard mutation.fields.contains(.effectVisibility) == !mutation.effectVisibilities.isEmpty else {
                    return .failure(.invalidArgument("invalid effect visibility mutation fields"))
                }
                for (effectIndex, visible) in mutation.effectVisibilities {
                    guard authoredLayer.effects.indices.contains(effectIndex) else {
                        return .failure(.invalidArgument("effect visibility index outside layer"))
                    }
                    let target = SceneDynamicTarget.effectVisibility(layerID: mutation.layerID, effectIndex: effectIndex)
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument("conflicting effect visibility mutation"))
                    }
                    candidateAuthoredValues[target] = .bool(visible)
                    Self.ensureDefinition(for: target, layer: authoredLayer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
                }
                if mutation.fields.contains(.text) {
                    guard authoredLayer.contentKind == "text",
                          authoredLayer.text != nil,
                          authoredLayer.textStyle != nil,
                          SceneScriptLayerMutation.acceptsDynamicText(mutation.text),
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
                if mutation.fields.contains(.pointSize) {
                    let target = SceneDynamicTarget.text(layerID: mutation.layerID, field: .pointSize)
                    guard authoredLayer.contentKind == "text", authoredLayer.textStyle != nil,
                          SceneScriptValueOwner.acceptsScalar(mutation.pointSize, for: target) else {
                        return .failure(.invalidArgument("invalid authored text point size mutation"))
                    }
                    guard authoredTargets.insert(target).inserted else {
                        return .failure(.invalidArgument("conflicting authored layer mutation target"))
                    }
                    candidateAuthoredValues[target] = .scalar(mutation.pointSize)
                    Self.ensureDefinition(for: target, layer: authoredLayer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
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
            let pointSizeTarget = SceneDynamicTarget.text(layerID: mutation.layerID, field: .pointSize)
            let hasPointSizeInput = mutation.assetPath == nil && (
                mutation.fields.contains(.pointSize) || candidateDefinitions[pointSizeTarget] != nil
            )
            guard mutation.orderIndex >= 0,
                  mutation.alpha.isFinite,
                  mutation.pointSize.isFinite,
                  hasPointSizeInput || (1...1024).contains(mutation.pointSize),
                  !mutation.fields.contains(.pointSize) || mutation.assetPath == nil,
                  mutation.color.x.isFinite,
                  mutation.color.y.isFinite, mutation.color.z.isFinite,
                  SceneScriptLayerMutation.acceptsDynamicText(mutation.text),
                  mutation.font.utf8.count <= 1_024 else {
                return .failure(.invalidArgument("invalid dynamic layer mutation"))
            }
            if let size = mutation.size {
                guard mutation.assetPath != nil, size.x > 0, size.y > 0,
                      Float(size.x).isFinite, Float(size.y).isFinite else {
                    return .failure(.invalidArgument("invalid dynamic image dimensions"))
                }
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
                candidateCreators.removeValue(forKey: mutation.layerID)
                candidateTextTemplates.removeValue(forKey: mutation.layerID)
                candidateDefinitionOrder.removeAll {
                    Self.layerID(for: $0, cameraOriginInputLayerID: cameraOriginInputLayerID) == mutation.layerID
                }
                candidateDefinitions = candidateDefinitions.filter {
                    Self.layerID(for: $0.key, cameraOriginInputLayerID: cameraOriginInputLayerID) != mutation.layerID
                }
                candidateAuthoredValues = candidateAuthoredValues.filter {
                    Self.layerID(for: $0.key, cameraOriginInputLayerID: cameraOriginInputLayerID) != mutation.layerID
                }
                requiresRetirement = true
            case .upsert:
                let layer: SceneRenderDescriptor.Layer?
                if let assetPath = mutation.assetPath {
                    guard let template = preparedResourceLayerTemplates[
                        assetPath.lowercased()
                    ] else {
                        return .failure(.invalidArgument(
                            "prepared resource layer is not launch-ready"
                        ))
                    }
                    guard template.kind != .composition || supportsCompositionPerspective else {
                        return .failure(.invalidArgument("composition requires an orthographic canvas"))
                    }
                    layer = .preparedResourceLayer(mutation, template: template)
                } else {
                    layer = .dynamicText(mutation)
                }
                guard let layer else {
                    return .failure(.invalidArgument("dynamic layer is invalid"))
                }
                if candidateLayers[mutation.layerID] == nil {
                    candidateOrder.append(mutation.layerID)
                    if let creator = mutation.ownerTarget {
                        candidateCreators[mutation.layerID] = creator
                        requiresRetirement = requiresRetirement || (Self.layerID(for: creator,
                            cameraOriginInputLayerID: cameraOriginInputLayerID)
                            .map(candidateDestroyedAuthoredLayerIDs.contains) ?? false)
                    }
                }
                if mutation.textTemplateIdentity != 0 {
                    guard mutation.assetPath == nil,
                          let template = textTemplates[mutation.textTemplateIdentity],
                          candidateTextTemplates[mutation.layerID].map({
                              $0 == mutation.textTemplateIdentity
                          }) ?? true else {
                        return .failure(.invalidArgument("dynamic text template identity is unavailable"))
                    }
                    candidateTextTemplates[mutation.layerID] = mutation.textTemplateIdentity
                    let definition = template.definition(layerID: mutation.layerID)
                    if candidateDefinitions[definition.target] == nil {
                        candidateDefinitionOrder.append(definition.target)
                        candidateDefinitions[definition.target] = definition
                    }
                } else if candidateTextTemplates[mutation.layerID] != nil {
                    return .failure(.invalidArgument("dynamic text template identity changed"))
                }
                if candidateLayers[mutation.layerID] != nil,
                   candidateTextTemplates[mutation.layerID] != nil,
                   mutation.fields.contains(.text) {
                    candidateAuthoredValues[.text(layerID: mutation.layerID, field: .content)] = .string(mutation.text)
                }
                if mutation.fields.contains(.pointSize) {
                    let target = SceneDynamicTarget.text(layerID: mutation.layerID, field: .pointSize)
                    candidateAuthoredValues[target] = .scalar(mutation.pointSize)
                    Self.ensureDefinition(for: target, layer: layer,
                        order: &candidateDefinitionOrder, definitions: &candidateDefinitions)
                }
                candidateLayers[mutation.layerID] = layer
            }
        }
        if !deferringFinalization {
            let projected: [Int]?
            switch projectedLayerOrder(for: candidateOrder, accepting: []) {
            case let .success(value): projected = value
            case let .failure(failure): return .failure(failure)
            }
            Self.finalizeTopology(requiresRetirement: requiresRetirement, projectedOrder: projected,
                destroyedAuthoredLayerIDs: candidateDestroyedAuthoredLayerIDs, authoredLayerIDs: authoredLayerIDs,
                cameraOriginInputLayerID: cameraOriginInputLayerID,
                order: &candidateOrder, layers: &candidateLayers, creators: &candidateCreators,
                definitionOrder: &candidateDefinitionOrder, definitions: &candidateDefinitions,
                values: &candidateAuthoredValues)
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
        dynamicLayerCreatorTargetsByID = candidateCreators
        textTemplateIdentitiesByLayerID = candidateTextTemplates.filter { candidateLayers[$0.key] != nil }
        destroyedAuthoredLayerIDs = candidateDestroyedAuthoredLayerIDs
        authoredLayerValues = candidateAuthoredValues
        authoredDefinitionOrder = candidateDefinitionOrder
        authoredDefinitionsByTarget = candidateDefinitions
        if publishingTopologyRevision,
           dynamicTopologyChanged {
            topologyRevision &+= 1
        }
        return .success(.init(requiresRetirement: requiresRetirement))
    }

    /// Raw C positions include authored tombstones and creator copies until the
    /// shared commit boundary. Place all surviving and deferred slots first,
    /// then remove retired identities in one projection, across all peer owners.
    private static func finalizeTopology(
        requiresRetirement: Bool, projectedOrder: [Int]?,
        destroyedAuthoredLayerIDs: Set<Int>, authoredLayerIDs: Set<Int>, cameraOriginInputLayerID: Int?,
        order: inout [Int],
        layers: inout [Int: SceneRenderDescriptor.Layer],
        creators: inout [Int: SceneDynamicTarget],
        definitionOrder: inout [SceneDynamicTarget],
        definitions: inout [SceneDynamicTarget: SceneDynamicTargetDefinition],
        values: inout [SceneDynamicTarget: SceneDynamicValue]
    ) {
        if let projectedOrder { order = projectedOrder }
        guard requiresRetirement else { return }
        var retiredDynamicIDs: Set<Int> = []
        while true {
            let newlyRetired = Set(creators.compactMap { dynamicID, creator -> Int? in
                guard let creatorLayerID = layerID(for: creator, cameraOriginInputLayerID: cameraOriginInputLayerID),
                      destroyedAuthoredLayerIDs.contains(creatorLayerID)
                        || retiredDynamicIDs.contains(creatorLayerID)
                        || (!authoredLayerIDs.contains(creatorLayerID) && layers[creatorLayerID] == nil)
                else { return nil }
                return dynamicID
            }).subtracting(retiredDynamicIDs)
            guard !newlyRetired.isEmpty else { break }
            retiredDynamicIDs.formUnion(newlyRetired)
            for layerID in newlyRetired {
                layers.removeValue(forKey: layerID)
                creators.removeValue(forKey: layerID)
            }
        }
        let removedLayerIDs = destroyedAuthoredLayerIDs.union(retiredDynamicIDs)
        order.removeAll { destroyedAuthoredLayerIDs.contains($0) || retiredDynamicIDs.contains($0) }
        definitionOrder.removeAll { target in
            layerID(for: target, cameraOriginInputLayerID: cameraOriginInputLayerID).map(removedLayerIDs.contains) ?? false
        }
        definitions = definitions.filter { target, _ in
            !(layerID(for: target, cameraOriginInputLayerID: cameraOriginInputLayerID).map(removedLayerIDs.contains) ?? false)
        }
        values = values.filter { target, _ in
            !(layerID(for: target, cameraOriginInputLayerID: cameraOriginInputLayerID).map(removedLayerIDs.contains) ?? false)
        }
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
        _ mutations: [SceneScriptLayerMutation],
        topologyOwners: [SceneDynamicTarget: UInt64] = [:]
    ) -> SceneScriptLayerMutationPlan {
        let originalOrder = order
        let originalLayers = dynamicLayersByID
        let originalCreators = dynamicLayerCreatorTargetsByID
        let originalTextTemplates = textTemplateIdentitiesByLayerID
        let originalDestroyedAuthoredLayerIDs = destroyedAuthoredLayerIDs
        let originalValues = authoredLayerValues
        let originalDefinitionOrder = authoredDefinitionOrder
        let originalDefinitions = authoredDefinitionsByTarget
        let outcome = applyIsolatingOwnersToCurrentState(mutations, topologyOwners: topologyOwners)
        let dynamicTopologyChanged = Self.dynamicTopologyChanged(
            currentOrder: originalOrder,
            currentLayers: originalLayers,
            candidateOrder: order,
            candidateLayers: dynamicLayersByID
        )
        let publishCandidate = !outcome.failures.contains { $0.ownerTarget == nil }
        let plan = SceneScriptLayerMutationPlan(
            particlePlayback: particlePlayback,
            outcome: outcome,
            order: publishCandidate ? order : originalOrder,
            dynamicLayersByID: publishCandidate ? dynamicLayersByID : originalLayers,
            dynamicLayerCreatorTargetsByID: publishCandidate ? dynamicLayerCreatorTargetsByID : originalCreators,
            destroyedAuthoredLayerIDs: publishCandidate ? destroyedAuthoredLayerIDs : originalDestroyedAuthoredLayerIDs,
            authoredLayerValues: publishCandidate ? authoredLayerValues : originalValues,
            authoredDefinitionOrder: publishCandidate ? authoredDefinitionOrder : originalDefinitionOrder,
            authoredDefinitionsByTarget: publishCandidate ? authoredDefinitionsByTarget : originalDefinitions,
            dynamicTopologyChanged: publishCandidate && dynamicTopologyChanged,
            textTemplateIdentitiesByLayerID: publishCandidate ? textTemplateIdentitiesByLayerID : originalTextTemplates,
            retiredDynamicLayerIDs: publishCandidate ? Set(originalLayers.keys).subtracting(dynamicLayersByID.keys) : [],
            createdPreparedTextValues: publishCandidate ? Dictionary(uniqueKeysWithValues:
                textTemplateIdentitiesByLayerID.keys.filter { originalLayers[$0] == nil }.compactMap { layerID in
                    dynamicLayersByID[layerID]?.text.map {
                        (SceneDynamicTarget.text(layerID: layerID, field: .content), SceneDynamicValue.string($0))
                    }
                }) : [:]
        )
        order = originalOrder
        dynamicLayersByID = originalLayers
        dynamicLayerCreatorTargetsByID = originalCreators
        textTemplateIdentitiesByLayerID = originalTextTemplates
        destroyedAuthoredLayerIDs = originalDestroyedAuthoredLayerIDs
        authoredLayerValues = originalValues
        authoredDefinitionOrder = originalDefinitionOrder
        authoredDefinitionsByTarget = originalDefinitions
        return plan
    }

    func preflightOwnerEffects(
        _ effects: [SceneScriptOwnerEffects],
        particleObservations: [Int: SceneParticlePlaybackObservation] = [:]
    ) -> SceneScriptOwnerEffectsAdmission {
        var admitted = effects
        var rejected: [SceneScriptLayerMutationOwnerFailure] = []
        var rejectedTargets = Set<SceneDynamicTarget>()
        var plan = particlePlaybackPlan(for: admitted, observations: particleObservations,
            layerPlan: preflightIsolatingOwners(admitted.flatMap(\.layerMutations),
                    topologyOwners: Dictionary(admitted.compactMap { effect in
                        effect.layerTopologyOwnerIdentity.map { (effect.ownerTarget, $0) }
                    }, uniquingKeysWith: { _, current in current })))
        while !plan.outcome.failures.isEmpty {
            var newlyRejected = Set<SceneDynamicTarget>()
            for failure in plan.outcome.failures {
                if let owner = failure.ownerTarget {
                    newlyRejected.insert(owner)
                    rejected.append(failure)
                } else {
                    let affected = admitted.compactMap { candidate in
                        candidate.layerMutations.isEmpty && candidate.layerTopologyOwnerIdentity == nil
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
            plan = particlePlaybackPlan(for: admitted, observations: particleObservations,
                layerPlan: preflightIsolatingOwners(admitted.flatMap(\.layerMutations),
                    topologyOwners: Dictionary(admitted.compactMap { effect in
                        effect.layerTopologyOwnerIdentity.map { (effect.ownerTarget, $0) }
                    }, uniquingKeysWith: { _, current in current })))
        }
        // An admitted play returns this property to its prepared Timeline,
        // including when the callback also writes it or immediately pauses.
        // Clear only the candidate value: external rejection rebuilds the plan
        // from current state, preserving setters from rejected commands.
        for effect in admitted {
            for mutation in effect.animationMutations where mutation.command == .play {
                plan.authoredLayerValues.removeValue(forKey: mutation.target)
            }
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
        excludingOwners: Set<SceneDynamicTarget> = [],
        particleObservations: [Int: SceneParticlePlaybackObservation] = [:],
        validateParticleTransitions: ([SceneParticlePlaybackTransition]) -> Bool = { $0.isEmpty },
        rejectingParticleTransitions: ([SceneParticlePlaybackTransition], [SceneScriptOwnerEffects], Set<SceneDynamicTarget>) -> Set<SceneDynamicTarget> = { _, _, _ in [] },
        rejectingDependents: (Set<SceneDynamicTarget>) -> Set<SceneDynamicTarget> = { $0 },
        rejectingExternally: ([SceneScriptOwnerEffects])
            -> Set<SceneDynamicTarget>
    ) -> SceneScriptOwnerEffectsFixedPointAdmission {
        var externallyRejected = excludingOwners
        var dependencySeedFailures: [SceneScriptLayerMutationOwnerFailure] = []
        while true {
            let candidates = effects.filter {
                !externallyRejected.contains($0.ownerTarget)
            }
            let admission = preflightOwnerEffects(candidates, particleObservations: particleObservations)
            let admittedOwners = Set(admission.admittedEffects.map(
                \.ownerTarget
            ))
            var newlyRejected = rejectingExternally(
                admission.admittedEffects
            ).intersection(admittedOwners)
            if !validateParticleTransitions(admission.layerPlan.particleTransitions) {
                newlyRejected.formUnion(admission.admittedEffects.filter { !$0.particlePlaybackCommands.isEmpty }.map(\.ownerTarget))
            }
            newlyRejected.formUnion(rejectingParticleTransitions(
                admission.layerPlan.particleTransitions, admission.admittedEffects,
                externallyRejected.union(admission.rejectedOwners.compactMap(\.ownerTarget)).union(newlyRejected)))
            newlyRejected.subtract(externallyRejected)
            if !newlyRejected.isEmpty {
                externallyRejected.formUnion(newlyRejected)
                continue
            }
            // First settle command/layer validation. A storage reader can have
            // only a typed value, so dependency rejection must not intersect
            // the list of owners that emitted layer/command effects.
            let rejected = externallyRejected.union(admission.rejectedOwners.compactMap(\.ownerTarget))
            let expanded = rejectingDependents(rejected).union(rejected)
            guard !expanded.subtracting(rejected).isEmpty else {
                return .init(admission: .init(
                    admittedEffects: admission.admittedEffects,
                    rejectedOwners: dependencySeedFailures + admission.rejectedOwners,
                    layerPlan: admission.layerPlan
                ), externallyRejectedOwners: externallyRejected)
            }
            // Once the settled plan rejects an owner, its readers cannot reuse
            // the value it produced. Keep that decision while closing further
            // dependency and quota failures; independent admitted peers survive.
            dependencySeedFailures.append(contentsOf: admission.rejectedOwners)
            externallyRejected.formUnion(expanded)
        }
    }

    func commit(_ plan: SceneScriptLayerMutationPlan) {
        // Definitions grow on admitted writes and retire with authored layers.
        // Their stable order is the cheapest complete invalidation key;
        // authored values remain frame-varying state and do not invalidate
        // the launch schema.
        let definitionsChanged = authoredDefinitionOrder
            != plan.authoredDefinitionOrder
        particlePlayback = plan.particlePlayback
        order = plan.order
        dynamicLayersByID = plan.dynamicLayersByID
        dynamicLayerCreatorTargetsByID = plan.dynamicLayerCreatorTargetsByID
        textTemplateIdentitiesByLayerID = plan.textTemplateIdentitiesByLayerID
        destroyedAuthoredLayerIDs = plan.destroyedAuthoredLayerIDs
        authoredLayerValues = plan.authoredLayerValues
        authoredDefinitionOrder = plan.authoredDefinitionOrder
        authoredDefinitionsByTarget = plan.authoredDefinitionsByTarget
        if plan.dynamicTopologyChanged {
            topologyRevision &+= 1
        }
        if plan.outcome.committedDynamicMutationCount > 0 {
            dynamicLayerValueRevision &+= 1
        }
        if definitionsChanged {
            authoredDefinitionRevision &+= 1
        }
    }

    private func applyIsolatingOwnersToCurrentState(
        _ mutations: [SceneScriptLayerMutation],
        topologyOwners: [SceneDynamicTarget: UInt64]
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
        var requiresRetirement = false
        let committedDestroyedIDs = destroyedAuthoredLayerIDs
        for owner in ownerOrder {
            guard let batch = grouped[owner] else { continue }
            let authoredValues = batch.flatMap {
                Self.authoredValues($0, cameraOriginInputLayerID: cameraOriginInputLayerID)
            }
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
            switch apply(batch, publishingTopologyRevision: false, deferringFinalization: true,
                         committedDestroyedAuthoredLayerIDs: committedDestroyedIDs) {
            case let .success(changes):
                requiresRetirement = requiresRetirement || changes.requiresRetirement
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
        let rejected = Set(failures.compactMap(\.ownerTarget))
        let identities = Set(topologyOwners.compactMap { rejected.contains($0.key) ? nil : $0.value })
        let projectedOrder: [Int]?
        switch projectedLayerOrder(for: order, accepting: identities) {
        case let .success(value): projectedOrder = value
        case let .failure(failure):
            return .init(committedMutationCount: 0, committedDynamicMutationCount: 0,
                failures: failures + [.init(ownerTarget: nil, failure: failure)])
        }
        Self.finalizeTopology(requiresRetirement: requiresRetirement, projectedOrder: projectedOrder,
            destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs, authoredLayerIDs: authoredLayerIDs,
            cameraOriginInputLayerID: cameraOriginInputLayerID,
            order: &order, layers: &dynamicLayersByID, creators: &dynamicLayerCreatorTargetsByID,
            definitionOrder: &authoredDefinitionOrder, definitions: &authoredDefinitionsByTarget,
            values: &authoredLayerValues)
        textTemplateIdentitiesByLayerID = textTemplateIdentitiesByLayerID.filter { dynamicLayersByID[$0.key] != nil }
        return .init(
            committedMutationCount: committedMutationCount,
            committedDynamicMutationCount: committedDynamicMutationCount,
            failures: failures
        )
    }

    private func projectedLayerOrder(for candidate: [Int], accepting owners: Set<UInt64>)
        -> Result<[Int]?, SceneScriptScalarRuntimeFailure> {
        guard let layerOrderProjection else {
            return owners.isEmpty ? .success(nil)
                : .failure(.invalidArgument("VM layer order projection is unavailable"))
        }
        return layerOrderProjection(owners).flatMap { projected in
            guard projected.map({ Set($0) == Set(candidate) && $0.count == candidate.count }) ?? owners.isEmpty else {
                return .failure(.invalidArgument("candidate layer order identities diverged"))
            }
            return .success(projected)
        }
    }

}
