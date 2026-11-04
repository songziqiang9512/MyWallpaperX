import Foundation

nonisolated enum SceneResolvedMaterialDependencyOwnership: Equatable {
    typealias Binding = SceneDependencyRenderPlan.Binding

    case none
    case graphInternal(referenceCount: Int)
    case externalPrimary(Binding)
    case externalAggregate(SceneDependencyRenderPlan.MultiProviderAggregate)

    var reportKind: String {
        switch self {
        case .none:
            "none"
        case .graphInternal:
            "graph-internal"
        case .externalPrimary:
            "external-primary"
        case .externalAggregate:
            "external-aggregate"
        }
    }

    var referenceCount: Int {
        switch self {
        case .none:
            0
        case let .graphInternal(referenceCount):
            referenceCount
        case let .externalPrimary(binding):
            binding.referenceSlots.count
        case let .externalAggregate(aggregate):
            aggregate.bindings.count
        }
    }

    var isAggregate: Bool {
        if case .externalAggregate = self { return true }
        return false
    }

}

/// Separates dependency metadata already conserved by the authored graph from
/// dependencies that still require an external layer/object execution owner.
nonisolated enum SceneResolvedMaterialDependencyOwnershipCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Reference = SceneDependencyRenderPlan.Reference

    static func structuralUtilityConsumerLayerIDs(
        in descriptor: SceneRenderDescriptor
    ) -> Set<Int> {
        let referencesByConsumer = Dictionary(
            grouping: SceneDependencyGraphAnalysis.references(in: descriptor.layers),
            by: \.consumerLayerID
        )
        return Set(descriptor.layers.compactMap { layer in
            let references = referencesByConsumer[layer.id] ?? []
            guard layer.contentKind == "composition",
                  layer.utilityLayer?.kind == .composition,
                  layer.childLayerIDs.isEmpty,
                  !layer.dependencyLayerIDs.isEmpty,
                  layer.authoredDependencies.isEmpty,
                  (layer.dependencyLayerIDs.count == 1
                    || SceneDependencyRenderPlan.activeDependencyProviderLayerIDs(
                        layer: layer, references: references
                    )?.count == 1
                    || SceneDependencyRenderPlan
                        .isMultiProviderUtilityCandidate(
                            layer: layer,
                            references: references
                        )) else { return nil }
            return layer.id
        })
    }

    static func compile(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        references: [Reference],
        binding: SceneDependencyRenderPlan.Binding?,
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate? = nil
    ) -> SceneResolvedMaterialDependencyOwnership? {
        let effectiveReferences = ownerRequiringReferences(
            references,
            layer: layer,
            graph: graph
        )
        let hasDependencyMetadata = !layer.dependencyLayerIDs.isEmpty
            || !layer.authoredDependencies.isEmpty
            || !effectiveReferences.isEmpty
        guard hasDependencyMetadata else {
            return SceneResolvedMaterialDependencyOwnership.none
        }

        if let aggregate { return .externalAggregate(aggregate) }
        if let binding { return .externalPrimary(binding) }

        // Same-layer composite references name the layer's own target. The
        // declared form (`dependencies == [self]`) keeps the historical
        // previous-shadow proof; authored texture slots without a declaration
        // are the same ownership: each self candidate resolves to the exact
        // consuming effect ingress, so no external provider binding may claim
        // the reference. The secondary (`_b`) variant qualifies
        // only in the authored composite form — its slot must be free of a
        // graph binding, because a `previous`-style binding at that slot is
        // shadow provenance with its own fail-soft contract, not a
        // composite-target consumer.
        let secondaryCompositeOnly = effectiveReferences
            .filter { $0.variant == .secondary }
            .allSatisfy { reference in
                (graph?.nodes ?? []).filter {
                    $0.effect.descriptorID == reference.slot.effectID
                        && $0.instancePassIndex == reference.slot.passIndex
                }.allSatisfy { node in
                    node.bindings.allSatisfy {
                        $0.slot != reference.slot.slotIndex
                    }
                }
            }
        guard layer.authoredDependencies.isEmpty,
              layer.dependencyLayerIDs.isEmpty
                  || layer.dependencyLayerIDs == [layer.id],
              // A declared `[self]` dependency whose references were all
              // shadowed still means graph-internal: the layer's own effect
              // chain consumes its previous output. Requiring a surviving
              // reference here rejects the whole layer when the shadow proof
              // succeeds, which is the opposite of what the proof intends.
              Set(effectiveReferences).count == effectiveReferences.count,
              effectiveReferences.allSatisfy({
                  $0.consumerLayerID == layer.id
                      && $0.providerLayerID == layer.id
                      && ($0.variant == .primary
                          || ($0.variant == .secondary && secondaryCompositeOnly))
              }), let graph,
              graph.layerID == layer.id else {
            return nil
        }
        return .graphInternal(referenceCount: effectiveReferences.count)
    }

    /// A same-layer named material reference is source provenance when the
    /// exact effect/pass/slot has an explicit `previous -> effect.input`
    /// binding. Template compilation preserves the reference below that graph
    /// override; dependency admission must therefore not invent a second owner.
    private static func ownerRequiringReferences(
        _ references: [Reference],
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?
    ) -> [Reference] {
        guard let graph else { return references }
        return references.filter {
            !isShadowedInputProvenance($0, layer: layer, graph: graph)
        }
    }

    private static func isShadowedInputProvenance(
        _ reference: Reference,
        layer: SceneRenderDescriptor.Layer,
        graph: Graph
    ) -> Bool {
        guard reference.consumerLayerID == layer.id,
              reference.providerLayerID == layer.id,
              graph.layerID == layer.id else { return false }
        let effects = graph.effects.filter {
            $0.key.descriptorID == reference.slot.effectID
        }
        guard effects.count == 1, let effect = effects.first,
              SceneResolvedMaterialExactPreviousInputShadow.accepts(
                  .init(
                      providerLayerID: reference.providerLayerID,
                      variant: reference.variant
                  ),
                  input: effect.input,
                  consumer: effect.key
              ) else { return false }
        let nodes = graph.nodes.filter {
            $0.effect == effect.key
                && $0.instancePassIndex == reference.slot.passIndex
        }
        guard nodes.count == 1, let node = nodes.first,
              node.kind == .material else { return false }
        let matches = node.bindings.filter {
            $0.slot == reference.slot.slotIndex
        }
        return matches.count == 1
            && matches[0].authoredName == "previous"
            && matches[0].texture == effect.input
    }


}

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct ResolvedExternalDependency: Equatable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
    }

    private struct ResolvedNamedCandidate {
        let key: MaterialKey
        let slot: Int
        let reference: SceneNamedTextureReference
    }

    enum ResolvedExternalDependencyAnalysis {
        case none
        case exact([ResolvedExternalDependency])
        case invalid
    }

    static func resolvedExternalDependencies(
        in stage: CompiledStages.Stage
    ) -> ResolvedExternalDependencyAnalysis {
        guard case let .resolved(materials, _) = stage.execution else {
            return .none
        }
        let product = stage.product
        var namedCandidates: [ResolvedNamedCandidate] = []
        // `materials` is a dictionary keyed by material identity. Its
        // iteration order is intentionally unspecified, while an aggregate
        // dependency is an authored slot vector. Use the graph's authored
        // effect/node order rather than lexical effect IDs at both collection
        // and final-vector boundaries.
        func authoredMaterialPrecedes(
            _ lhs: MaterialCapability,
            _ rhs: MaterialCapability
        ) -> Bool {
            let lhsEffectIndex = lhs.key.effect.effectIndex
            let rhsEffectIndex = rhs.key.effect.effectIndex
            if lhsEffectIndex != rhsEffectIndex {
                return lhsEffectIndex < rhsEffectIndex
            }
            let lhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == lhs.key.nodeIndex && $0.effect == lhs.key.effect
            } ?? Int.max
            let rhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == rhs.key.nodeIndex && $0.effect == rhs.key.effect
            } ?? Int.max
            if lhsNodeOrder != rhsNodeOrder {
                return lhsNodeOrder < rhsNodeOrder
            }
            if lhs.key.nodeIndex != rhs.key.nodeIndex {
                return lhs.key.nodeIndex < rhs.key.nodeIndex
            }
            return lhs.key.effect.descriptorID < rhs.key.effect.descriptorID
        }
        for material in materials.values.sorted(by: authoredMaterialPrecedes) {
            let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
            var consumedSlots = Set(snapshot.variants.flatMap { variant in
                variant.activeSamplers.keys
            })
            for variant in snapshot.variants {
                for binding in variant.preparedAssembly.preparedUniformBindings {
                    switch binding.source {
                    case let .host(.textureResolution(slot)),
                         let .host(.textureRotation(slot)),
                         let .host(.textureTranslation(slot)),
                         let .selfCompositeTextureResolution(slot, _):
                        consumedSlots.insert(slot)
                    default:
                        break
                    }
                }
            }
            for slot in material.template.textureSlots.compactMap({ $0 })
            where consumedSlots.contains(slot.index) {
                let reference: SceneNamedTextureReference?
                if let selected = slot.candidates.last,
                   case let .provider(.namedLayerTarget(value)) =
                    selected.reference {
                    reference = value
                } else if material.variants
                    .provesExactMixedNamedFallback(
                        slot: slot.index
                    ), slot.candidates.count == 2,
                    case let .provider(.namedLayerTarget(value)) =
                        slot.candidates[0].reference {
                    // The highest-precedence optional input may be absent at a
                    // concrete frame. The exact precompiled mixed-provider
                    // envelope then selects this lower compositor color
                    // publication, so dependency conservation must retain its
                    // provider edge even though it is not the static last
                    // candidate.
                    reference = value
                } else {
                    reference = nil
                }
                guard let reference else {
                    continue
                }
                namedCandidates.append(.init(
                    key: material.key,
                    slot: slot.index,
                    reference: reference
                ))
            }
        }
        guard !namedCandidates.isEmpty else { return .none }
        // A same-layer secondary candidate is the authored composite form
        // (`_rt_imageLayerComposite_<self>_b`): the layer's own graph
        // resolves both variants to the consuming effect ingress, so it carries
        // the same conservation contract as the primary. Cross-layer
        // secondary variants keep failing closed.
        func admitsCandidate(_ item: ResolvedNamedCandidate) -> Bool {
            guard item.key.effect.layerID == product.graph.layerID else {
                return false
            }
            switch item.reference.variant {
            case .primary:
                return true
            case .secondary:
                return item.reference.providerLayerID == item.key.effect.layerID
            case .unspecified:
                return false
            }
        }
        guard namedCandidates.allSatisfy(admitsCandidate) else {
            return .invalid
        }
        var result: [ResolvedExternalDependency] = []
        var dependenciesBySlot: [SceneEffectPassSlot: ResolvedExternalDependency] = [:]
        for item in namedCandidates {
            let nodeMatches = product.graph.nodes.filter {
                $0.nodeIndex == item.key.nodeIndex
                    && $0.effect == item.key.effect
            }
            let effectMatches = product.graph.effects.filter {
                $0.key == item.key.effect
            }
            guard nodeMatches.count == 1,
                  effectMatches.count == 1,
                  let node = nodeMatches.first else {
                return .invalid
            }
            let passIndex = node.instancePassIndex ?? node.definitionPassIndex
            let dependency = ResolvedExternalDependency(
                consumerLayerID: item.key.effect.layerID,
                providerLayerID: item.reference.providerLayerID,
                slot: .init(
                    effectID: item.key.effect.descriptorID,
                    passIndex: passIndex,
                    slotIndex: item.slot
                )
            )
            if let existing = dependenciesBySlot[dependency.slot] {
                guard existing == dependency else { return .invalid }
                continue
            }
            dependenciesBySlot[dependency.slot] = dependency
            result.append(dependency)
        }
        return .exact(result)
    }
}
