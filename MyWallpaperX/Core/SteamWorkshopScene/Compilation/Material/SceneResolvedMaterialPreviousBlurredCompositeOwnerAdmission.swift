import Foundation

/// Whole-stage owner gate for the shared blurred/current composite cohort.
/// The shared graph contract is independent of the incumbent planner; source,
/// typed-input, and lifecycle checks remain narrower so unproven shapes keep
/// the existing product fallback.
nonisolated enum SceneResolvedMaterialPreviousBlurredCompositeOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum ScaleCohort: Equatable {
        case staticExact
        case staticScalarProjection
        case userPropertyScalarSplat(String)
        case timelineExactVector2
    }

    private enum SourceCohort: Equatable {
        case ordinary
        case capturedMain
        case copyOnlyCapturedMain
        case passthroughOnlyCapturedMain
        case copyPassthroughCapturedMain
    }

    static func accepts(
        key: SceneResolvedMaterialRuntimeCatalog.Key,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        propertyDefinitions: [SceneDynamicTargetDefinition] = [],
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
        inputRole requiredInputRole: SceneAuthoredEffectInputRole? = nil
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.effects[0].key == key.effect,
              graph.effects[0].nodeIndices.last == key.nodeIndex,
              let layer = descriptor.layers.first(where: {
                  $0.id == graph.layerID
              }), sourceCohort(layer) != nil,
              let inputRole = SceneAuthoredEffectInputValidator.role(
                  for: graph.effects[0].input,
                  layerID: graph.layerID
              ), requiredInputRole == nil || requiredInputRole == inputRole,
              SceneResolvedMaterialPreviousBlurredCompositeGraphAdmission
                  .accepts(
                      graph: graph,
                      descriptor: descriptor,
                      inputRole: inputRole
                  ),
              let scale = wholeStageScaleCohort(
                  graph: graph,
                  descriptor: descriptor
              ), scaleProducerCohortIsProven(
                  scale: scale,
                  effect: graph.effects[0],
                  graph: graph,
                  descriptor: descriptor,
                  userPropertyProducers: userPropertyProducers,
                  propertyDefinitions: propertyDefinitions,
                  timelineDefinitions: timelineDefinitions
              ) else { return false }
        return true
    }

    /// Utility sources use the shared captured-texture graph ingress. A
    /// composition with copybackground=false prepares a transparent group
    /// texture, while background captures use their enclosing pass. Flag
    /// pairs remain distinct cohorts; dependency and child lifecycles stay outside.
    private static func sourceCohort(
        _ layer: SceneRenderDescriptor.Layer
    ) -> SourceCohort? {
        guard let utility = layer.utilityLayer else { return .ordinary }
        let kindMatchesContent = switch (layer.contentKind, utility.kind) {
        case ("composition", .composition), ("project", .project),
             ("fullscreen", .fullscreen):
            true
        default:
            false
        }
        guard kindMatchesContent,
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty else { return nil }
        return switch (utility.copyBackground, utility.passthrough) {
        case (false, false): .capturedMain
        case (true, true): .copyPassthroughCapturedMain
        case (true, false): .copyOnlyCapturedMain
        case (false, true): .passthroughOnlyCapturedMain
        }
    }

    private static func wholeStageScaleCohort(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> ScaleCohort? {
        let cohorts = [1, 2].compactMap { ordinal -> ScaleCohort? in
            guard graph.nodes.indices.contains(ordinal),
                  graph.nodes[ordinal].effect == graph.effects.first?.key else {
                return nil
            }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal], graph: graph, descriptor: descriptor
            )
            guard resolution.isResolved,
                  let material = resolution.node,
                  material.constants.count == 1,
                  let scale = material.constants.first?.value else { return nil }
            return scaleCohort(scale)
        }
        guard cohorts.count == 2, cohorts[0] == cohorts[1] else { return nil }
        return cohorts[0]
    }

    private static func scaleCohort(
        _ scale: SceneDocument.ShaderValue
    ) -> ScaleCohort? {
        guard scale.timelineDiagnostics.isEmpty,
              scale.scriptSource == nil,
              let components = scale.components,
              components.count == 1 || components.count == 2,
              components.allSatisfy(\.isFinite) else { return nil }
        if scale.timeline != nil {
            guard scale.valueKind.localizedLowercase == "binding",
                  scale.userBinding == nil,
                  scale.userValueKind == nil,
                  scale.bindingKeys == ["animation", "value"],
                  components.count == 2 else { return nil }
            return .timelineExactVector2
        }
        guard scale.valueKind.localizedLowercase == "binding" else {
            guard scale.userBinding == nil else { return nil }
            return components.count == 1
                ? .staticScalarProjection
                : .staticExact
        }
        guard let key = scale.userBinding,
              !key.isEmpty,
              key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              scale.userValueKind == .string,
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  scale.bindingKeys
              ),
              components.count == 1 || components[0] == components[1] else {
            return nil
        }
        return .userPropertyScalarSplat(key)
    }
}
