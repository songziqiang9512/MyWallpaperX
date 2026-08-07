import Foundation

extension SceneAuthoredEffectExecutionCatalog {
    nonisolated static func validResolvedMaterialKeys(
        descriptor: SceneRenderDescriptor,
        authoredPlansByLayerID: [Int: [SceneAuthoredEffectRenderPlan]],
        subjects: [SceneEffectExactRuntimeSubject],
        visibleLayerIDs: Set<Int>
    ) -> [Int: Set<SceneAuthoredEffectRenderPlan.EffectKey>] {
        let grouped = Dictionary(grouping: subjects, by: \.key.layerID)
        var result: [Int: Set<SceneAuthoredEffectRenderPlan.EffectKey>] = [:]
        for (layerID, layerSubjects) in grouped {
            guard visibleLayerIDs.contains(layerID),
                  layerSubjects.allSatisfy({ $0.family == "resolved-material" }),
                  Set(layerSubjects.map(\.key)).count == layerSubjects.count,
                  descriptor.layers.filter({ $0.id == layerID }).count == 1,
                  let layer = descriptor.layers.first(where: { $0.id == layerID }),
                  let graphs = authoredPlansByLayerID[layerID], graphs.count == 1,
                  let graph = graphs.first else { continue }
            let activeKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey> = Set(
                layer.effects.enumerated().compactMap {
                    effectIndex, effect in
                    guard effect.visible != false else { return nil }
                    return SceneAuthoredEffectRenderPlan.EffectKey(
                        layerID: layerID,
                        effectIndex: effectIndex,
                        descriptorID: effect.id
                    )
                }
            )
            let subjectKeys = Set(layerSubjects.map(\.key))
            guard !activeKeys.isEmpty, subjectKeys == activeKeys,
                  Set(graph.effects.map(\.key)) == activeKeys else { continue }
            result[layerID] = activeKeys
        }
        return result
    }
}
