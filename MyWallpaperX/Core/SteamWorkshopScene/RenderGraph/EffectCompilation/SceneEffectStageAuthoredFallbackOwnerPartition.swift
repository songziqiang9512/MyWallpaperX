import Foundation

/// Filters definition-only property fallbacks at the product-owner boundary.
/// A retained dedicated stage must remain executable until its own compiler
/// has explicitly revoked that owner with the same launch-scoped facts.
nonisolated enum SceneEffectStageAuthoredFallbackOwnerPartition {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    static func executableTargets(
        definitions: [SceneDynamicTargetDefinition],
        liveTargets: Set<SceneDynamicTarget>,
        retainedDedicatedEffects: Set<EffectKey>
    ) -> Set<SceneDynamicTarget> {
        Set(definitions.compactMap { definition in
            let target = definition.target
            if liveTargets.contains(target) {
                return target
            }
            let identity: (layerID: Int, effectIndex: Int)?
            switch target {
            case let .effectVisibility(layerID, effectIndex),
                 let .effectConstant(layerID, effectIndex, _, _):
                identity = (layerID, effectIndex)
            case .scene, .camera, .layer, .text, .particle,
                 .scriptInstanceProperty:
                identity = nil
            }
            guard let identity else { return target }
            let hasRetainedOwner = retainedDedicatedEffects.contains {
                $0.layerID == identity.layerID
                    && $0.effectIndex == identity.effectIndex
            }
            return hasRetainedOwner ? nil : target
        })
    }
}
