import Foundation

/// Family matching is intentionally weaker than exact planner admission: it
/// identifies which dedicated compiler owns a declined stage, while the
/// planner continues to enforce the complete fail-closed profile.
private nonisolated enum SceneEffectStageDedicatedCandidateMatcher {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func matches(
        graph: Graph,
        definitionPath: String
    ) -> Bool {
        let expected = normalized(definitionPath)
        return graph.effects.contains {
            normalized($0.definitionPath) == expected
        }
    }

    nonisolated static func matchesDefinition(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        predicate: (SceneEffectDefinition) -> Bool
    ) -> Bool {
        let authoredPaths = Set(graph.effects.map {
            normalized($0.definitionPath)
        })
        return descriptor.effectDefinitions.contains {
            authoredPaths.contains(normalized($0.relativePath)) && predicate($0)
        }
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

extension SceneAuthoredLocalContrastPlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/localcontrast/effect.json"
        )
    }
}

extension SceneAuthoredCursorRipplePlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/cursorripple/effect.json"
        )
    }
}

extension SceneAuthoredWaterRipplePlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/waterripple/effect.json"
        )
    }
}

extension SceneAuthoredDepthParallaxPlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/depthparallax/effect.json"
        )
    }
}

extension SceneAuthoredXRayPlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/xray/effect.json"
        )
    }
}

extension SceneAuthoredColorGradingPlanner {
    nonisolated static func containsCandidate(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matchesDefinition(
            graph: graph,
            descriptor: descriptor
        ) { definition in
            definition.replacementKey?.lowercased() == "color_grading"
                || (
                    definition.name == "Color Grading"
                        && definition.description == nil
                        && definition.group?.lowercased() == "localeffects"
                )
        }
    }
}
