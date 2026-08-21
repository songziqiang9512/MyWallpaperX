import Foundation

nonisolated enum SceneResolvedMaterialDependencyOwnership: Equatable {
    typealias Binding = SceneDependencyRenderPlan.Binding

    case none
    case graphInternal(referenceCount: Int)
    case externalPrimary(Binding)

    var reportKind: String {
        switch self {
        case .none:
            "none"
        case .graphInternal:
            "graph-internal"
        case .externalPrimary:
            "external-primary"
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
        }
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
        Set(descriptor.layers.compactMap { layer in
            guard layer.contentKind == "composition",
                  layer.utilityLayer?.kind == .composition,
                  layer.childLayerIDs.isEmpty,
                  layer.dependencyLayerIDs.count == 1,
                  layer.authoredDependencies.isEmpty else { return nil }
            return layer.id
        })
    }

    static func compile(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        references: [Reference],
        binding: SceneDependencyRenderPlan.Binding?
    ) -> SceneResolvedMaterialDependencyOwnership? {
        let hasDependencyMetadata = !layer.dependencyLayerIDs.isEmpty
            || !layer.authoredDependencies.isEmpty
            || !references.isEmpty
        guard hasDependencyMetadata else {
            return SceneResolvedMaterialDependencyOwnership.none
        }

        if let binding {
            let supportedBinding = switch binding.kind {
            case .resolvedMaterial:
                binding.slot.slotIndex == 1 && binding.blendMode == 0
            case .proceduralNoiseLayer:
                binding.slot.passIndex == 0
                    && binding.slot.slotIndex == 3
                    && binding.blendMode == 0
            case .imageLayerBlend:
                binding.slot.passIndex == 0
                    && binding.slot.slotIndex == 1
                    && binding.blendMode == 0
            }
            guard supportedBinding,
                  binding.consumerLayerID == layer.id,
                  layer.authoredDependencies.isEmpty,
                  layer.dependencyLayerIDs == [binding.providerLayerID],
                  (binding.kind == .resolvedMaterial || references.count == 1),
                  references.first != nil,
                  binding.referenceSlots == references.map(\.slot),
                  references.allSatisfy({ candidate in
                      candidate.consumerLayerID == binding.consumerLayerID
                          && candidate.providerLayerID == binding.providerLayerID
                          && candidate.slot.slotIndex == binding.slot.slotIndex
                          && candidate.variant == .primary
                  }) else {
                return nil
            }
            return .externalPrimary(binding)
        }

        guard layer.authoredDependencies.isEmpty,
              layer.dependencyLayerIDs == [layer.id],
              !references.isEmpty,
              Set(references).count == references.count,
              references.allSatisfy({
                  $0.consumerLayerID == layer.id
                      && $0.providerLayerID == layer.id
                      && $0.variant == .primary
              }), let graph,
              graph.layerID == layer.id,
              references.allSatisfy({ graphOwns($0, graph: graph) }) else {
            return nil
        }
        return .graphInternal(referenceCount: references.count)
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
        guard binding == nil,
              layer.authoredDependencies.isEmpty,
              references.count == 1,
              Set(references).count == references.count,
              references.allSatisfy({
                  $0.consumerLayerID == layer.id
                    && $0.providerLayerID != layer.id
                    && $0.variant == .primary
              }),
              let graph, graph.layerID == layer.id,
              graph.blockers.isEmpty,
              let consumerOrder = descriptor.renderOrderLayerIDs.firstIndex(
                  of: layer.id
              ) else { return nil }

        let providerIDs = Set(references.map(\.providerLayerID))
        guard providerIDs.count == 1,
              layer.dependencyLayerIDs.count == 1,
              Set(layer.dependencyLayerIDs) == providerIDs,
              providerIDs.allSatisfy({ providerID in
                  descriptor.layers.filter({ $0.id == providerID }).count == 1
                    && descriptor.renderOrderLayerIDs.firstIndex(of: providerID)
                        .map({ $0 > consumerOrder }) == true
              }) else { return nil }

        var keys = Set<Graph.EffectKey>()
        for reference in references {
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
            keys.insert(key)
        }
        return keys.isEmpty ? nil : keys
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

    private static func graphOwns(_ reference: Reference, graph: Graph) -> Bool {
        let effectMatches = graph.effects.enumerated().filter {
            $0.element.key.descriptorID == reference.slot.effectID
        }
        guard effectMatches.count == 1,
              let consumer = effectMatches.first,
              consumer.offset > graph.effects.startIndex else { return false }

        let effect = consumer.element
        let priorEffect = graph.effects[graph.effects.index(before: consumer.offset)]
        guard effect.input == priorEffect.output,
              effect.input.kind == .effectOutput,
              effect.input.effect == priorEffect.key else { return false }

        let nodeMatches = graph.nodes.filter {
            $0.effect == effect.key
                && $0.instancePassIndex == reference.slot.passIndex
        }
        guard nodeMatches.count == 1, let node = nodeMatches.first else { return false }
        let bindingMatches = node.bindings.filter {
            $0.slot == reference.slot.slotIndex
        }
        guard bindingMatches.count == 1, let binding = bindingMatches.first else {
            return false
        }
        return binding.authoredName == "previous"
            && binding.texture == effect.input
    }
}
