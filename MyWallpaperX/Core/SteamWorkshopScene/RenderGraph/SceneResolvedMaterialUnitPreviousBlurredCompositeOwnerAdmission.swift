import Foundation

/// Temporary whole-stage owner gate for the first generic Standard Blur
/// cohort. The source-local composite fact remains reusable, but it cannot
/// authorize product output until the surrounding graph and authored scale
/// shape are inside the independently verified cohort.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func accepts(
        key: SceneResolvedMaterialRuntimeCatalog.Key,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.effects[0].key == key.effect,
              graph.effects[0].nodeIndices.last == key.nodeIndex,
              let stage = SceneAuthoredStandardBlurPlanner.plan(
                  graph: graph,
                  descriptor: descriptor
              ), let blur = stage.standardBlur,
              blur.maskTexturePath == nil else { return false }
        return [1, 2].allSatisfy { ordinal in
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal], graph: graph, descriptor: descriptor
            )
            guard resolution.isResolved,
                  let material = resolution.node,
                  material.constants.count == 1,
                  let scale = material.constants.first?.value else { return false }
            return scale.valueKind.localizedLowercase != "binding"
                && scale.userBinding == nil
                && scale.timeline == nil
                && scale.timelineDiagnostics.isEmpty
                && scale.scriptSource == nil
        }
    }
}
