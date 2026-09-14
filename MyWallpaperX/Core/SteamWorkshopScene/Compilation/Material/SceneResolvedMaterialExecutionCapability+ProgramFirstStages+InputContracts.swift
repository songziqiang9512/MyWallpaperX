import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    /// Product Timeline admission conserves the exact typed definition and
    /// author fallback. Identity-only catalogs remain available to legacy
    /// standalone harnesses, but product launch always supplies definitions.
    static func timelineDefinitionMatches(
        _ dynamic: Template.DynamicUniform,
        producers: DynamicProducerCatalog
    ) -> Bool {
        guard !producers.timelineDefinitions.isEmpty else {
            return producers.timelineTargets.contains(dynamic.target)
        }
        let matches = producers.timelineDefinitions.filter {
            $0.target == dynamic.target
        }
        guard matches.count == 1,
              let definition = matches.first,
              let fallback = dynamic.authoredFallback,
              let authoredBits = timelineAuthoredBitPatterns(definition) else {
            return false
        }
        return fallback.componentBitPatterns == authoredBits
    }

    private static func timelineAuthoredBitPatterns(
        _ definition: SceneDynamicTargetDefinition
    ) -> [UInt64]? {
        guard definition.authoredValue.valueType == definition.valueType,
              definition.authoredValue.isFinite else { return nil }
        let components: [Double]
        switch definition.authoredValue {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        case let .vector4(x, y, z, w): components = [x, y, z, w]
        case .bool, .string: return nil
        }
        return components.map(\.bitPattern)
    }

    static func soleUserPropertyProducerMatches(
        _ propertyKey: String,
        dynamic: Template.DynamicUniform,
        producers: DynamicProducerCatalog
    ) -> Bool {
        let targetProducers = producers.userProperties.filter {
            $0.target == dynamic.target
        }
        guard targetProducers.count == 1,
              let producer = targetProducers.first else { return false }
        return producer.propertyKey == propertyKey
            && userPropertyValueTypeMatches(producer.valueType, dynamic: dynamic)
    }

    /// Exact direct bindings conserve the producer type before Program claims
    /// product output. Legacy/test catalogs without a type retain the previous
    /// identity-only behavior; product launch always publishes the real type.
    static func userPropertyValueTypeMatches(
        _ producerType: SceneDynamicValueType?,
        dynamic: Template.DynamicUniform
    ) -> Bool {
        guard let producerType else { return true }
        guard let fallback = dynamic.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: dynamic,
                  fallback: fallback
              ) else {
            return true
        }
        let expected: SceneDynamicValueType
        switch fallback.componentBitPatterns.count {
        case 1: expected = .scalar
        case 2: expected = .vector2
        case 3: expected = .vector3
        case 4: expected = .vector4
        default: return true
        }
        return producerType == expected
    }

}

nonisolated extension SceneResolvedMaterialDependencyOwnership {
    /// Returns the external provider slots owned by this exact single-effect
    /// stage. `nil` means the dependency owner cannot authorize a visual
    /// fallback for the stage. Empty slots mean this stage is independent of
    /// the layer's external dependency; it may use the ordinary framebuffer
    /// rollback proof without consuming or publishing that provider.
    func preEncodeVisualFailureSlots(
        in graph: SceneAuthoredEffectRenderPlan
    ) -> [SceneEffectPassSlot]? {
        switch self {
        case .none, .graphInternal:
            return []
        case let .externalPrimary(binding):
            guard graph.effects.count == 1,
                  let effect = graph.effects.first,
                  graph.layerID == binding.consumerLayerID,
                  effect.key.layerID == binding.consumerLayerID else {
                return nil
            }
            let slots = binding.referenceSlots.filter {
                $0.effectID == effect.key.descriptorID
            }
            guard !slots.isEmpty else { return [] }
            guard graph.renderTargets.isEmpty else { return nil }
            guard Set(slots).count == slots.count,
                  slots.allSatisfy({ slot in
                      graph.nodes.filter({ node in
                          node.effect == effect.key
                              && node.kind == .material
                              && node.instancePassIndex == slot.passIndex
                              && node.materialOrdinal != nil
                      }).count == 1
                  }) else { return nil }
            return slots
        case .externalAggregate:
            return nil
        }
    }
}
