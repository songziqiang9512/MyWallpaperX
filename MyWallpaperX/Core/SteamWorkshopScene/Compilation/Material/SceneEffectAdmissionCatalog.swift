import Foundation

nonisolated struct SceneEffectAdmissionCatalog {
    let stageAdmissions: [SceneEffectStageAdmission]
    let unifiedExecutionStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>
    let verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>
    let descriptorEffectStageCount: Int
    let descriptorEffectStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>

    init(
        descriptor: SceneRenderDescriptor,
        authoredPlans: [SceneAuthoredEffectRenderPlan],
        resolvedMaterialSubjects: [SceneEffectExactRuntimeSubject] = [],
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        verifiedXRayStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = []
    ) {
        let visible = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        descriptorEffectStageCount = descriptor.layers.reduce(0) {
            $0 + $1.effects.count
        }
        descriptorEffectStageKeys = Set(descriptor.layers.flatMap { layer in
            layer.effects.enumerated().map { effectIndex, effect in
                SceneAuthoredEffectRenderPlan.EffectKey(
                    layerID: layer.id,
                    effectIndex: effectIndex,
                    descriptorID: effect.id
                )
            }
        })
        self.verifiedXRayStageKeys = verifiedXRayStageKeys.intersection(
            descriptorEffectStageKeys
        )
        let grouped = Dictionary(grouping: authoredPlans, by: \.layerID)
        let resolvedKeysByLayerID = Self.validResolvedMaterialKeys(
            descriptor: descriptor,
            authoredPlansByLayerID: grouped,
            subjects: resolvedMaterialSubjects,
            startupInactiveEffectVisibilityTargets:
                startupInactiveEffectVisibilityTargets
        )
        let unifiedSubjects = resolvedMaterialSubjects.filter {
            resolvedKeysByLayerID[$0.key.layerID]?.contains($0.key) == true
        }
        let unifiedSubjectsByLayerID = Dictionary(
            grouping: unifiedSubjects, by: \.key.layerID
        )
        let executableLayerIDs = visible.union(resolvedKeysByLayerID.keys)
        unifiedExecutionStageKeys = Set(unifiedSubjects.map(\.key))
        stageAdmissions = descriptor.layers.flatMap { layer in
            SceneEffectStageAdmissionBuilder.make(
                layer: layer,
                graphCandidates: grouped[layer.id] ?? [],
                layerIsExecutable: executableLayerIDs.contains(layer.id),
                startupInactiveEffectVisibilityTargets:
                    startupInactiveEffectVisibilityTargets,
                unifiedExecutionSubjects: unifiedSubjectsByLayerID[layer.id] ?? []
            )
        }.sorted {
            if $0.key.layerID != $1.key.layerID {
                return $0.key.layerID < $1.key.layerID
            }
            if $0.key.effectIndex != $1.key.effectIndex {
                return $0.key.effectIndex < $1.key.effectIndex
            }
            return $0.key.descriptorID < $1.key.descriptorID
        }
    }
}
