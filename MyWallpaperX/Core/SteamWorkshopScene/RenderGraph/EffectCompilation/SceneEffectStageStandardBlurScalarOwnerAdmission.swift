import Foundation

extension SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission {
    nonisolated enum UserPropertyScalarOwnerSource: Equatable {
        case liveProducer
        case authoredFallback

        nonisolated var revocationToken: String {
            switch self {
            case .liveProducer: "typed-user-scalar-splat"
            case .authoredFallback: "authored-fallback-scalar-splat"
            }
        }
    }

    /// The whole Standard Blur stage must use one input mode. A mixed
    /// live/fallback stage keeps its incumbent because the two Gaussian passes
    /// would otherwise cross different failure and rebuild boundaries.
    nonisolated static func userPropertyScalarOwnerSource(
        propertyKey: String,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        producers: Set<SceneDynamicUserPropertyProducer>,
        definitions: [SceneDynamicTargetDefinition]
    ) -> UserPropertyScalarOwnerSource? {
        let sources = [1, 2].compactMap { ordinal in
            userPropertyScalarOwnerSource(
                propertyKey: propertyKey,
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                ordinal: ordinal,
                producers: producers,
                definitions: definitions
            )
        }
        guard sources.count == 2, sources[0] == sources[1] else {
            return nil
        }
        return sources[0]
    }

    nonisolated static func userPropertyScalarTargetMatches(
        ownerSource: UserPropertyScalarOwnerSource,
        expectedProducer: SceneDynamicUserPropertyProducer,
        targetProducers: Set<SceneDynamicUserPropertyProducer>,
        target: SceneDynamicTarget,
        fallbackComponentBitPatterns: [UInt64],
        definitions: [SceneDynamicTargetDefinition]
    ) -> Bool {
        switch ownerSource {
        case .liveProducer:
            return targetProducers == [expectedProducer]
        case .authoredFallback:
            return targetProducers.isEmpty
                && authoredScalarDefinition(
                    target: target,
                    matches: fallbackComponentBitPatterns,
                    definitions: definitions
                )
        }
    }

    /// Owner admission and the typed revocation token consume the same
    /// launch-scoped producer/definition facts. Exact duplicate definitions
    /// remain visible because this path intentionally receives an Array.
    nonisolated static func scaleProducerCohortIsProven(
        scale: ScaleCohort,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        propertyDefinitions: [SceneDynamicTargetDefinition],
        timelineDefinitions: Set<SceneDynamicTargetDefinition>
    ) -> Bool {
        switch scale {
        case let .userPropertyScalarSplat(propertyKey):
            return userPropertyScalarOwnerSource(
                propertyKey: propertyKey,
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                producers: userPropertyProducers,
                definitions: propertyDefinitions
            ) != nil
        case .timelineExactVector2:
            return [1, 2].allSatisfy { ordinal in
                guard graph.nodes.indices.contains(ordinal),
                      graph.nodes[ordinal].effect == effect.key,
                      let passIndex = graph.nodes[ordinal].instancePassIndex else {
                    return false
                }
                let target = SceneDynamicTarget.effectConstant(
                    layerID: effect.key.layerID,
                    effectIndex: effect.key.effectIndex,
                    passIndex: passIndex,
                    name: "scale"
                )
                let targetDefinitions = timelineDefinitions.filter {
                    $0.target == target
                }
                let resolution = SceneAuthoredMaterialResolver.resolve(
                    node: graph.nodes[ordinal],
                    graph: graph,
                    descriptor: descriptor
                )
                guard resolution.isResolved,
                      let authored = resolution.node?.constants["scale"],
                      let components = authored.components,
                      targetDefinitions.count == 1,
                      let definition = targetDefinitions.first else {
                    return false
                }
                return timelineDefinition(
                    definition,
                    matches: components.map(\.bitPattern)
                )
            }
        case .staticExact, .staticScalarProjection:
            return true
        }
    }

    private nonisolated static func userPropertyScalarOwnerSource(
        propertyKey: String,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        ordinal: Int,
        producers: Set<SceneDynamicUserPropertyProducer>,
        definitions: [SceneDynamicTargetDefinition]
    ) -> UserPropertyScalarOwnerSource? {
        guard graph.nodes.indices.contains(ordinal),
              graph.nodes[ordinal].effect == effect.key,
              let passIndex = graph.nodes[ordinal].instancePassIndex else {
            return nil
        }
        let target = SceneDynamicTarget.effectConstant(
            layerID: effect.key.layerID,
            effectIndex: effect.key.effectIndex,
            passIndex: passIndex,
            name: "scale"
        )
        let expectedProducer = SceneDynamicUserPropertyProducer(
            propertyKey: propertyKey,
            target: target,
            valueType: .scalar
        )
        let targetProducers = producers.filter { $0.target == target }
        if targetProducers == [expectedProducer] {
            return .liveProducer
        }
        guard !producers.contains(where: {
            $0.propertyKey == propertyKey || $0.target == target
        }) else { return nil }

        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: graph.nodes[ordinal],
            graph: graph,
            descriptor: descriptor
        )
        guard resolution.isResolved,
              let authored = resolution.node?.constants["scale"],
              let components = authored.components else { return nil }
        return authoredScalarDefinition(
            target: target,
            matches: components.map(\.bitPattern),
            definitions: definitions
        ) ? .authoredFallback : nil
    }

    private nonisolated static func authoredScalarDefinition(
        target: SceneDynamicTarget,
        matches componentBitPatterns: [UInt64],
        definitions: [SceneDynamicTargetDefinition]
    ) -> Bool {
        guard componentBitPatterns.count == 1
                || componentBitPatterns.count == 2,
              let first = componentBitPatterns.first,
              componentBitPatterns.allSatisfy({ $0 == first }) else {
            return false
        }
        let matches = definitions.filter { $0.target == target }
        guard matches.count == 1,
              let definition = matches.first,
              definition.valueType == .scalar,
              case let .scalar(value) = definition.authoredValue,
              value.isFinite else { return false }
        return value.bitPattern == first
    }

    nonisolated static func timelineDefinition(
        _ definition: SceneDynamicTargetDefinition,
        matches componentBitPatterns: [UInt64]
    ) -> Bool {
        guard definition.valueType == .vector2,
              componentBitPatterns.count == 2,
              case let .vector2(x, y) = definition.authoredValue,
              x.isFinite, y.isFinite else { return false }
        return x.bitPattern == componentBitPatterns[0]
            && y.bitPattern == componentBitPatterns[1]
    }
}
