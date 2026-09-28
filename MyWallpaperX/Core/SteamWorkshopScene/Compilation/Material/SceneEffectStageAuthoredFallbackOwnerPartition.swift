import Foundation

/// Publishes loss-preserving authored definitions to the shared Program owner.
nonisolated enum SceneEffectStageAuthoredFallbackOwnerPartition {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    static func executableTargets(
        definitions: [SceneDynamicTargetDefinition]
    ) -> Set<SceneDynamicTarget> {
        Set(definitions.map(\.target))
    }
}
