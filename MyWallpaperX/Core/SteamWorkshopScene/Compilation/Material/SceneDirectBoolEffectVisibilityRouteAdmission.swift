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
        targets(
            in: descriptor,
            candidates: candidates,
            visibleLayerIDs: visibleLayerIDs,
            dependencyPlan: dependencyPlan,
            requiresInitiallyInactiveEffect: true,
            scriptOwnedCandidates: scriptOwnedCandidates
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
                  visibleLayerIDs.contains(layerID) else { return nil }
            let standaloneFullscreen = layer.contentKind == "fullscreen"
                && layer.parentID == nil && layer.childLayerIDs.isEmpty
                && layer.utilityLayer?.kind == .fullscreen
                && (try? SceneUtilityLayerSourceRoute.resolve(
                    layer: layer, descriptor: descriptor
                ).get()) != nil
            let layerTarget = SceneDynamicTarget.layer(layerID: layerID, field: .visibility)
            let ordinaryHierarchy = SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor, candidates: [layerTarget]
            ).contains(layerTarget)
            // These compositions already capture through the same prepared
            // source route when enabled at launch. Retain their inactive
            // stages so a typed toggle can activate the existing graph later.
            let compositionSource = layer.contentKind == "composition"
                ? try? SceneUtilityLayerSourceRoute.resolve(
                    layer: layer, descriptor: descriptor
                ).get() : nil
            let standaloneComposition = layer.contentKind == "composition"
                && layer.utilityLayer?.kind == .composition
                && layer.parentID == nil
                && compositionSource != nil
                && (layer.utilityLayer?.passthrough == false
                    || compositionSource?.usesAuthoredLocalSource == true)
                && ordinaryHierarchy
            let standaloneUtility = standaloneFullscreen || standaloneComposition
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
