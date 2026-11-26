import Foundation

/// Narrows validated Boolean effect visibility to ordinary, prepared hierarchy
/// layers and standalone utility captures. Cross-layer providers and
/// hierarchy-owned output keep their existing preparation route.
nonisolated enum SceneDirectBoolEffectVisibilityRouteAdmission {
    static func startupInactiveTargets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        dynamicLayerVisibilityOwnerTargets: Set<SceneDynamicTarget> = [],
        scriptOwnedCandidates: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
            .union(SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
                in: descriptor,
                candidates: dynamicLayerVisibilityOwnerTargets.union(
                    scriptOwnedCandidates.compactMap { target in
                        guard case let .effectVisibility(layerID, _) = target else { return nil }
                        return SceneDynamicTarget.layer(layerID: layerID, field: .visibility)
                    }
                )
            ))
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
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        // The graph compiler owns a layer's primary pair input. Only the
        // remaining dependencies can require a separate utility owner.
        let dependencyConsumerLayerIDs = Set(dependencyPlan.references.compactMap { reference in
            reference.consumerLayerID == reference.providerLayerID && reference.variant == .primary
                ? nil : reference.consumerLayerID
        })
            .union(dependencyPlan.requiredEffectConsumerLayerIDs)
            .union(dependencyPlan.bindingsByConsumerLayerID.keys)
        let dependencyProviderLayerIDs = dependencyPlan.requiredProviderLayerIDs
            .union(dependencyPlan.requiredGraphOutputProviderLayerIDs)
        return Set(candidates.union(scriptOwnedCandidates).compactMap { target in
            guard case let .effectVisibility(layerID, effectIndex) = target,
                  let layer = layersByID[layerID],
                  layer.effects.indices.contains(effectIndex),
                  layer.effects[effectIndex].visible == false,
                  visibleLayerIDs.contains(layerID) else { return nil }
            let layerTarget = SceneDynamicTarget.layer(layerID: layerID, field: .visibility)
            let ordinaryHierarchy = SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor, candidates: [layerTarget]
            ).contains(layerTarget)
            // Hierarchy admission already resolves the utility source and members.
            let standaloneUtility = layer.utilityLayer != nil
                && layer.parentID == nil
                && ordinaryHierarchy
            guard standaloneUtility
                || (["image", "solid", "text"].contains(layer.contentKind)
                    && layer.utilityLayer == nil && ordinaryHierarchy) else { return nil }
            if standaloneUtility {
                guard layer.dependencyLayerIDs.isEmpty,
                      layer.authoredDependencies.isEmpty,
                      !dependencyConsumerLayerIDs.contains(layerID),
                      !dependencyPlan.staticLayerSourcePassthroughBlockedLayerIDs
                        .contains(layerID)
                else { return nil }
            }
            guard !dependencyProviderLayerIDs.contains(layerID) else {
                return nil
            }
            return target
        })
    }
}
