import Foundation

nonisolated enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case graphInternal(referenceCount: Int)

    var reportKind: String {
        switch self {
        case .none:
            "none"
        case .graphInternal:
            "graph-internal"
        }
    }

    var referenceCount: Int {
        switch self {
        case .none:
            0
        case let .graphInternal(referenceCount):
            referenceCount
        }
    }
}

/// Separates dependency metadata already conserved by the authored graph from
/// dependencies that still require an external layer/object execution owner.
nonisolated enum SceneResolvedMaterialDependencyOwnershipCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Reference = SceneDependencyRenderPlan.Reference

    static func compile(
        layer: SceneRenderDescriptor.Layer,
        graph: Graph?,
        references: [Reference]
    ) -> SceneResolvedMaterialDependencyOwnership? {
        let hasDependencyMetadata = !layer.dependencyLayerIDs.isEmpty
            || !layer.authoredDependencies.isEmpty
            || !references.isEmpty
        guard hasDependencyMetadata else {
            return SceneResolvedMaterialDependencyOwnership.none
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
