import Foundation

/// Narrows validated direct-bool effect visibility to ordinary, visible root
/// layers. Cross-layer providers/consumers and utility or hierarchy-owned
/// output keep their existing route for both active and startup-inactive work.
nonisolated enum SceneDirectBoolEffectVisibilityRouteAdmission {
    static func startupInactiveTargets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        scriptOwnedCandidates: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let structuralUtilityConsumerLayerIDs =
            SceneResolvedMaterialDependencyOwnershipCompiler
                .structuralUtilityConsumerLayerIDs(in: descriptor)
        let productReferences = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
        )
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs:
                structuralUtilityConsumerLayerIDs,
            admittedResolvedMaterialReferences: productReferences
        )
        return startupInactiveTargets(
            in: descriptor,
            candidates: candidates,
            visibleLayerIDs: visibleLayerIDs,
            dependencyPlan: dependencyPlan,
            scriptOwnedCandidates: scriptOwnedCandidates
        )
    }

    static func startupInactiveTargets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        visibleLayerIDs: Set<Int>,
        dependencyPlan: SceneDependencyRenderPlan,
        scriptOwnedCandidates: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        targets(
            in: descriptor,
            candidates: candidates,
            visibleLayerIDs: visibleLayerIDs,
            dependencyPlan: dependencyPlan,
            requiresInitiallyInactiveEffect: true,
            scriptOwnedCandidates: scriptOwnedCandidates
        )
    }

    static func activeOrdinaryRootTargets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>
    ) -> Set<SceneDynamicTarget> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let structuralUtilityConsumerLayerIDs =
            SceneResolvedMaterialDependencyOwnershipCompiler
                .structuralUtilityConsumerLayerIDs(in: descriptor)
        let productReferences = Set(
            SceneDependencyGraphAnalysis.references(in: descriptor.layers)
        )
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs:
                structuralUtilityConsumerLayerIDs,
            admittedResolvedMaterialReferences: productReferences
        )
        return targets(
            in: descriptor,
            candidates: candidates,
            visibleLayerIDs: visibleLayerIDs,
            dependencyPlan: dependencyPlan,
            requiresInitiallyInactiveEffect: false
        )
    }

    private static func targets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        visibleLayerIDs: Set<Int>,
        dependencyPlan: SceneDependencyRenderPlan,
        requiresInitiallyInactiveEffect: Bool,
        scriptOwnedCandidates: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        let dependencyConsumerLayerIDs = Set(
            dependencyPlan.references.map(\.consumerLayerID)
        )
            .union(dependencyPlan.namedReferenceConsumerLayerIDs)
            .union(dependencyPlan.requiredEffectConsumerLayerIDs)
            .union(dependencyPlan.bindingsByConsumerLayerID.keys)
        let dependencyProviderLayerIDs = dependencyPlan.requiredProviderLayerIDs
            .union(dependencyPlan.requiredGraphOutputProviderLayerIDs)
        return Set(candidates.union(scriptOwnedCandidates).compactMap { target in
            guard case let .effectVisibility(layerID, effectIndex) = target,
                  let layer = layersByID[layerID],
                  layer.effects.indices.contains(effectIndex),
                  (layer.effects[effectIndex].visible == false)
                    == requiresInitiallyInactiveEffect,
                  visibleLayerIDs.contains(layerID),
                  layer.parentID == nil,
                  layer.childLayerIDs.isEmpty else { return nil }
            // D2b script lane: the dependency checks are waived for
            // script-owned candidates only - the media toggle family lives
            // on externalPrimary consumers whose dependency closure is
            // captured unconditionally. The passthrough-blocked flag blocks
            // the degraded layer-SOURCE route; an activation-gated
            // script-gated stage does not use that route. Provider layers
            // stay rejected.
            let scriptOwned = scriptOwnedCandidates.contains(target)
            if !scriptOwned {
                guard layer.dependencyLayerIDs.isEmpty,
                      layer.authoredDependencies.isEmpty,
                      ["image", "solid", "text"].contains(layer.contentKind),
                      !dependencyConsumerLayerIDs.contains(layerID),
                      !dependencyPlan.staticLayerSourcePassthroughBlockedLayerIDs
                        .contains(layerID)
                else { return nil }
            } else {
                guard ["image", "solid", "text"]
                    .contains(layer.contentKind) else { return nil }
            }
            guard !dependencyProviderLayerIDs.contains(layerID) else {
                return nil
            }
            guard case nil = layer.utilityLayer else { return nil }
            return target
        })
    }
}
