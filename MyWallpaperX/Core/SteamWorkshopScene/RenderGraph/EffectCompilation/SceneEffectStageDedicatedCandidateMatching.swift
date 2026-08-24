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

extension SceneAuthoredXRayPlanner {
    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        SceneEffectStageDedicatedCandidateMatcher.matches(
            graph: graph,
            definitionPath: "effects/xray/effect.json"
        )
    }
}
