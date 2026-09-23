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
            aggregate.referenceSlots.count
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

    /// This composition consumer declares an *external* dependency but the
    /// projection produced no executable route for it — no binding, no
    /// aggregate, and no static-model binding — so its composition route
    /// cannot execute (the utility plan records the same consumer as
    /// `unsupportedDependencies`). Admitting it anyway would only leave the
    /// graph demanding execution evidence no route can produce, so the
    /// projection is the single authority for the executable set too. Keying on
    /// "no route" rather than on one issue kind also covers the
    /// missing/cyclic/secondary-variant refusals, which emit other kinds.
    ///
    /// Three shapes stay outside on purpose: a self reference (`provider ==
    /// layer`), which this compiler routes as `graph-internal`; a static-model
    /// bound consumer, whose provider arrives through its own binding map; and
    /// an ordinary image consumer, which keeps the designed per-effect
    /// fail-soft (only its unbound dependency stage degrades and the rest of
    /// the chain still executes).
    static func refusedCompositionConsumer(
        layer: SceneRenderDescriptor.Layer,
        layerID: Int,
        layerReferences: [SceneDependencyRenderPlan.Reference],
        plan: SceneDependencyRenderPlan
    ) -> Bool {
        guard layer.utilityLayer?.kind == .composition,
              layerReferences.contains(where: { $0.providerLayerID != layerID })
        else { return false }
        return plan.bindingsByConsumerLayerID[layerID] == nil
            && plan.multiProviderAggregatesByConsumerLayerID[layerID] == nil
            && plan.staticModelBindingsByConsumerLayerID[layerID] == nil
    }

    static func structuralUtilityConsumerLayerIDs(
        in descriptor: SceneRenderDescriptor
    ) -> Set<Int> {
        Set(descriptor.layers.compactMap { layer in
            guard layer.contentKind == "composition",
                  layer.utilityLayer?.kind == .composition,
                  layer.childLayerIDs.isEmpty,
                  !layer.dependencyLayerIDs.isEmpty,
                  layer.authoredDependencies.isEmpty,
                  (layer.dependencyLayerIDs.count == 1
                    || SceneDependencyRenderPlan
                        .isMultiProviderUtilityCandidate(
                            layer: layer,
                            references: SceneDependencyGraphAnalysis.references(
                                in: descriptor.layers
                            ).filter { $0.consumerLayerID == layer.id }
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

        if let aggregate {
            let declaredProviderIDs = Set(
                layer.dependencyLayerIDs.filter { $0 != layer.id }
            )
            let activeProviderIDs = SceneDependencyRenderPlan
                .activeDependencyProviderLayerIDs(
                    layer: layer,
                    references: effectiveReferences
                )
            guard binding == nil,
                  aggregate.consumerLayerID == layer.id,
                  layer.authoredDependencies.isEmpty,
                  layer.dependencyLayerIDs.count > 1,
                  layer.dependencyLayerIDs.count == declaredProviderIDs.count,
                  activeProviderIDs != nil,
                  Set(aggregate.bindings.map(\.providerLayerID))
                      == (activeProviderIDs ?? []),
                  aggregate.admits(effectiveReferences),
                  aggregate.bindings.allSatisfy({ candidate in
                      candidate.consumerLayerID == layer.id
                  }) else { return nil }
            return .externalAggregate(aggregate)
        }

        if let binding {
            let supportedBinding = switch binding.kind {
            case .resolvedMaterial:
                binding.slot.slotIndex == 1 && binding.blendMode == 0
            case .solidLayer:
                binding.slot.passIndex == 0
                    && binding.blendMode == 0
                    && (
                        binding.slot.slotIndex == 3
                            || (binding.slot.slotIndex == 1
                                && binding.requiresResolvedMaterialProgram)
                    )
            case .imageLayerBlend:
                binding.slot.passIndex == 0
                    && binding.slot.slotIndex == 1
                    && (binding.requiresResolvedMaterialProgram
                        || binding.blendMode == 0)
            case .geometryLayer:
                binding.slot.passIndex == 0
                    && binding.slot.slotIndex == 1
                    && binding.blendMode == 0
                    && binding.requiresResolvedMaterialProgram
            case .visibleImageGraphOutput:
                binding.slot.passIndex == 0
                    && binding.slot.slotIndex == 1
                    && binding.blendMode == 0
            }
            guard supportedBinding,
                  binding.consumerLayerID == layer.id,
                  layer.authoredDependencies.isEmpty,
                  // The dependency plan has already source-proved inactive
                  // alternatives and selected the one active publication.
                  // Ownership consumes that binding instead of re-reading the
                  // descriptor's all-variant dependency superset.
                  layer.dependencyLayerIDs.contains(binding.providerLayerID),
                  (binding.kind == .resolvedMaterial
                    || (binding.kind == .imageLayerBlend
                        && binding.requiresResolvedMaterialProgram)
                    || effectiveReferences.count == 1),
                  effectiveReferences.first != nil,
                  binding.referenceSlots == effectiveReferences.map(\.slot),
                  effectiveReferences.allSatisfy({ candidate in
                      candidate.consumerLayerID == binding.consumerLayerID
                          && candidate.providerLayerID == binding.providerLayerID
                          && candidate.slot.slotIndex == binding.slot.slotIndex
                          && candidate.variant == .primary
                  }) else {
                return nil
            }
            return .externalPrimary(binding)
        }

        // Same-layer primary references name the layer's own composite. The
        // declared form (`dependencies == [self]`) keeps the historical
        // previous-shadow proof; authored texture slots without a declaration
        // are the same ownership: the layer's own base source publishes the
        // composite during graph execution, so no external provider binding
        // may claim the reference.
        guard layer.authoredDependencies.isEmpty,
              layer.dependencyLayerIDs.isEmpty
                  || layer.dependencyLayerIDs == [layer.id],
              !effectiveReferences.isEmpty,
              Set(effectiveReferences).count == effectiveReferences.count,
              effectiveReferences.allSatisfy({
                  $0.consumerLayerID == layer.id
                      && $0.providerLayerID == layer.id
                      && $0.variant == .primary
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

    /// A forward primary provider is not executable in the current frame
    /// order. When every such reference belongs to an exact ordinary
    /// single-pass effect, that effect may be replaced by previous-current
    /// while unrelated suffix effects keep the layer-local pair chain. This
    /// does not authorize the provider or change dependency ordering.
    static func forwardUnavailableEffectKeys(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        descriptor: SceneRenderDescriptor,
        references: [Reference],
        binding: SceneDependencyRenderPlan.Binding?
    ) -> Set<Graph.EffectKey>? {
        let effectiveReferences = ownerRequiringReferences(
            references,
            layer: layer,
            graph: graph
        )
        guard binding == nil,
              layer.authoredDependencies.isEmpty,
              effectiveReferences.count == 1,
              Set(effectiveReferences).count == effectiveReferences.count,
              effectiveReferences.allSatisfy({
                  $0.consumerLayerID == layer.id
                    && $0.providerLayerID != layer.id
                    && $0.variant == .primary
              }),
              let graph, graph.layerID == layer.id,
              graph.blockers.isEmpty,
              let consumerOrder = descriptor.renderOrderLayerIDs.firstIndex(
                  of: layer.id
              ) else { return nil }

        let providerIDs = Set(effectiveReferences.map(\.providerLayerID))
        guard providerIDs.count == 1,
              layer.dependencyLayerIDs.count == 1,
              Set(layer.dependencyLayerIDs) == providerIDs,
              providerIDs.allSatisfy({ providerID in
                  descriptor.layers.filter({ $0.id == providerID }).count == 1
                    && descriptor.renderOrderLayerIDs.firstIndex(of: providerID)
                        .map({ $0 > consumerOrder }) == true
              }) else { return nil }

        var keys = Set<Graph.EffectKey>()
        for reference in effectiveReferences {
            guard let key = exactSinglePassPassthroughEffectKey(
                for: reference,
                layer: layer,
                graph: graph
            ) else { return nil }
            keys.insert(key)
        }
        return keys.isEmpty ? nil : keys
    }

    /// An owner-requiring reference without any supported binding cannot be
    /// satisfied in this launch: the provider may be hidden, ordered in an
    /// unsupported direction, or the consumer/utility shape may have no
    /// binding contract. When every such reference belongs to an exact
    /// ordinary single-pass material effect, only those effects fail soft to
    /// previous-current while unrelated effects keep the layer-local pair
    /// chain. This does not authorize the provider, publish a named target or
    /// change dependency ordering; the layer keeps `.none` ownership.
    static func unsupportedReferenceEffectKeys(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        references: [Reference],
        binding: SceneDependencyRenderPlan.Binding?
    ) -> Set<Graph.EffectKey>? {
        let effectiveReferences = ownerRequiringReferences(
            references,
            layer: layer,
            graph: graph
        )
        guard binding == nil,
              layer.authoredDependencies.isEmpty,
              !effectiveReferences.isEmpty,
              Set(effectiveReferences).count == effectiveReferences.count,
              effectiveReferences.allSatisfy({ $0.consumerLayerID == layer.id }),
              let graph, graph.layerID == layer.id,
              graph.blockers.isEmpty else { return nil }
        var keys = Set<Graph.EffectKey>()
        for reference in effectiveReferences {
            guard let key = exactSinglePassPassthroughEffectKey(
                for: reference,
                layer: layer,
                graph: graph
            ) else { return nil }
            keys.insert(key)
        }
        return keys.isEmpty ? nil : keys
    }

    /// The exact ordinary single-pass material effect that owns one
    /// unavailable reference. Multi-node, command, condition, compose and
    /// render-target owning effects are not replaceable by previous-current
    /// and therefore keep the whole layer fail-closed.
    private static func exactSinglePassPassthroughEffectKey(
        for reference: Reference,
        layer: SceneRenderDescriptor.Layer,
        graph: Graph
    ) -> Graph.EffectKey? {
        let descriptorMatches = layer.effects.enumerated().filter {
            $0.element.id == reference.slot.effectID
                && $0.element.visible != false
        }
        guard descriptorMatches.count == 1,
              let descriptorMatch = descriptorMatches.first,
              descriptorMatch.element.passes.filter({
                  $0.passIndex == reference.slot.passIndex
              }).count == 1 else { return nil }
        let key = Graph.EffectKey(
            layerID: layer.id,
            effectIndex: descriptorMatch.offset,
            descriptorID: descriptorMatch.element.id
        )
        let effectMatches = graph.effects.filter { $0.key == key }
        guard effectMatches.count == 1, let effect = effectMatches.first,
              effect.nodeIndices.count == 1,
              graph.renderTargets.allSatisfy({ $0.texture.effect != key })
        else { return nil }
        let nodes = graph.nodes.filter { $0.effect == key }
        guard nodes.count == 1, let node = nodes.first,
              node.kind == .material,
              node.instancePassIndex == reference.slot.passIndex,
              node.target == effect.output,
              node.commandSource == nil,
              node.commandTarget == nil,
              node.conditions == nil,
              node.compose == nil || node.compose == .bool(false),
              node.bindings.isEmpty || node.bindings.contains(where: {
                  $0.slot == reference.slot.slotIndex
                    && ($0.texture == effect.input
                        || $0.texture.kind == .unresolved)
              }) else { return nil }
        return key
    }

    /// A secondary self reference has no producer contract yet. If it belongs
    /// to one exact effect whose loss-preserving graph already maps that slot
    /// to the effect input, the entire effect may fail soft to previous-current.
    /// This does not authorize `_b` publication or consumption.
    static func secondarySelfUnavailableEffectKeys(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        references: [Reference],
        binding: SceneDependencyRenderPlan.Binding?
    ) -> Set<Graph.EffectKey>? {
        guard binding == nil,
              layer.authoredDependencies.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              references.count == 1,
              let reference = references.first,
              reference.consumerLayerID == layer.id,
              reference.providerLayerID == layer.id,
              reference.variant == .secondary,
              let graph, graph.layerID == layer.id,
              graph.blockers.isEmpty else { return nil }

        let descriptorMatches = layer.effects.enumerated().filter {
            $0.element.id == reference.slot.effectID
                && $0.element.visible != false
        }
        guard descriptorMatches.count == 1,
              let descriptorMatch = descriptorMatches.first,
              descriptorMatch.element.passes.filter({
                  $0.passIndex == reference.slot.passIndex
              }).count == 1 else { return nil }
        let key = Graph.EffectKey(
            layerID: layer.id,
            effectIndex: descriptorMatch.offset,
            descriptorID: descriptorMatch.element.id
        )
        let effectMatches = graph.effects.filter { $0.key == key }
        guard effectMatches.count == 1, let effect = effectMatches.first else {
            return nil
        }
        let nodeMatches = graph.nodes.filter {
            $0.effect == key
                && $0.instancePassIndex == reference.slot.passIndex
        }
        guard nodeMatches.count == 1, let node = nodeMatches.first,
              node.kind == .material,
              node.commandSource == nil,
              node.commandTarget == nil,
              node.conditions == nil,
              node.compose == nil || node.compose == .bool(false) else {
            return nil
        }
        let bindingMatches = node.bindings.filter {
            $0.slot == reference.slot.slotIndex
        }
        guard bindingMatches.count == 1,
              bindingMatches.first?.texture == effect.input else { return nil }
        return [key]
    }
}
