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
    /// Projects the prepared external inputs belonging to this stage.
    func preEncodeVisualFailureSlots(
        in graph: SceneAuthoredEffectRenderPlan
    ) -> [SceneEffectPassSlot]? {
        guard let effect = graph.effects.first else { return nil }
        switch self {
        case .none, .graphInternal:
            return []
        case let .externalPrimary(binding):
            return binding.referenceSlots.filter { $0.effectID == effect.key.descriptorID }
        case let .externalAggregate(aggregate):
            return aggregate.bindings.flatMap(\.referenceSlots)
                .filter { $0.effectID == effect.key.descriptorID }
        }
    }
}
