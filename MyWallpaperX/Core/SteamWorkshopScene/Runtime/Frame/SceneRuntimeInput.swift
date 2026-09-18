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
        // candidates: the authored value is only the seed a visibility script
        // may override per frame. Route-admit the script-owned targets
        // separately first so only structurally valid ones enter the union.
        let admittedScriptOwned =
            SceneDirectBoolEffectVisibilityRouteAdmission.startupInactiveTargets(
                in: renderDescriptor,
                candidates: scriptOwnedEffectVisibilityTargets
            )
        startupInactiveEffectVisibilityTargets =
            SceneDirectBoolEffectVisibilityRouteAdmission.startupInactiveTargets(
                in: renderDescriptor,
                candidates: propertyBindingProgram
                    .effectLocalDirectBoolEffectVisibilityTargets
                    .union(admittedScriptOwned)
            )
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor,
            startupInactiveEffectVisibilityTargets:
                startupInactiveEffectVisibilityTargets,
            scriptOwnedEffectVisibilityTargets: admittedScriptOwned
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
