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

    /// Proves one definition-only scalar without collapsing the authored
    /// definition array. Duplicate definitions, type drift, non-finite values,
    /// and signed-zero mismatches must remain visible at the owner boundary.
    static func hasExactScalarDefinition(
        target: SceneDynamicTarget,
        componentBitPatterns: [UInt64],
        definitions: [SceneDynamicTargetDefinition]
    ) -> Bool {
        guard componentBitPatterns.count == 1,
              let first = componentBitPatterns.first else {
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
}
