import Foundation

struct SceneRuntimeInput: Codable {
    let renderDescriptor: SceneRenderDescriptor
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let propertyBindingProgram: ScenePropertyBindingProgram
    let directBoolEffectVisibilityTargets: Set<SceneDynamicTarget>
    let scriptOwnedEffectVisibilityTargets: Set<SceneDynamicTarget>
    let startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget>
    let effectivePropertyValues: [String: SceneUserPropertyValue]
    let shaderContracts: [SceneShaderContract]

    init(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract],
        scriptOwnedEffectVisibilityTargets: Set<SceneDynamicTarget> = []
    ) {
        self.renderDescriptor = renderDescriptor
        directBoolEffectVisibilityTargets =
            propertyBindingProgram.directBoolEffectVisibilityTargets
        self.scriptOwnedEffectVisibilityTargets =
            scriptOwnedEffectVisibilityTargets
        // Script-owned effect visibility (the batch-B producer channel)
        // joins the user-property direct-bool targets as startup-inactive
        // candidates for the admission and admission catalog only (the raw
        // union keeps the admission catalog's subset validation sound).
        // The planner receives BOTH sets after the route admission's
        // structural filter, matching the pre-batch baseline where the
        // user-property set was route-filtered before planning: the
        // planner's property-inactive candidate path has no structural
        // prechecks, so an unfiltered candidate on a dependency-consumer,
        // dependency-provider, or passthrough-blocked layer would enter
        // the plan there and later lose the layer's resolved execution.
        // The planner's script-gated path keeps its authored prechecks as
        // defense in depth, not as a route-admission equivalent.
        startupInactiveEffectVisibilityTargets =
            propertyBindingProgram
                .effectLocalDirectBoolEffectVisibilityTargets
                .union(scriptOwnedEffectVisibilityTargets)
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor,
            startupInactiveEffectVisibilityTargets:
                SceneDirectBoolEffectVisibilityRouteAdmission
                .startupInactiveTargets(
                    in: renderDescriptor,
                    candidates: propertyBindingProgram
                        .effectLocalDirectBoolEffectVisibilityTargets
                ),
            scriptOwnedEffectVisibilityTargets:
                SceneDirectBoolEffectVisibilityRouteAdmission
                .startupInactiveTargets(
                    in: renderDescriptor,
                    candidates: scriptOwnedEffectVisibilityTargets
                )
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
