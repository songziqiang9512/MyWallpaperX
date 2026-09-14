import Foundation

extension SceneEffectAdmissionCatalog {
    nonisolated static func validResolvedMaterialKeys(
        descriptor: SceneRenderDescriptor,
        authoredPlansByLayerID: [Int: [SceneAuthoredEffectRenderPlan]],
        subjects: [SceneEffectExactRuntimeSubject],
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget>
    ) -> [Int: Set<SceneAuthoredEffectRenderPlan.EffectKey>] {
        let grouped = Dictionary(grouping: subjects, by: \.key.layerID)
        var result: [Int: Set<SceneAuthoredEffectRenderPlan.EffectKey>] = [:]
        for (layerID, layerSubjects) in grouped {
            guard layerSubjects.allSatisfy({
                      !$0.family.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                  }),
                  Set(layerSubjects.map(\.key)).count == layerSubjects.count,
                  descriptor.layers.filter({ $0.id == layerID }).count == 1,
                  let layer = descriptor.layers.first(where: { $0.id == layerID }),
                  let graphs = authoredPlansByLayerID[layerID], graphs.count == 1,
                  let graph = graphs.first else { continue }
            let activeKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = Set(
                layer.effects.enumerated().compactMap {
                    effectIndex, effect
                        -> SceneAuthoredEffectRenderPlan.EffectKey? in
                    guard effect.visible != false else { return nil }
                    return SceneAuthoredEffectRenderPlan.EffectKey(
                        layerID: layerID,
                        effectIndex: effectIndex,
                        descriptorID: effect.id
                    )
                }
            )
            let graphKeys = Set(graph.effects.map(\.key))
            let propertyInactiveGraphKeys = graphKeys.subtracting(activeKeys)
            let propertyInactiveDescriptorKeys: Set<
                SceneAuthoredEffectRenderPlan.EffectKey
            > = Set(
                layer.effects.enumerated().compactMap {
                    effectIndex, effect
                        -> SceneAuthoredEffectRenderPlan.EffectKey? in
                    guard effect.visible == false,
                          startupInactiveEffectVisibilityTargets.contains(
                              .effectVisibility(
                                  layerID: layerID,
                                  effectIndex: effectIndex
                              )
                          ) else { return nil }
                    return SceneAuthoredEffectRenderPlan.EffectKey(
                        layerID: layerID,
                        effectIndex: effectIndex,
                        descriptorID: effect.id
                    )
                }
            )
            let subjectKeys = Set(layerSubjects.map(\.key))
            guard !graphKeys.isEmpty,
                  activeKeys.isSubset(of: graphKeys),
                  propertyInactiveGraphKeys.isSubset(
                      of: propertyInactiveDescriptorKeys
                  ),
                  subjectKeys == graphKeys else { continue }
            result[layerID] = graphKeys
        }
        return result
    }
}
