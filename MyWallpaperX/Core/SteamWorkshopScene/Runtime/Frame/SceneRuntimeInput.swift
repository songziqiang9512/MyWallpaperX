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
        // candidates. These targets bypass the route admission: the
        // visibility script explicitly controls the effect, and the
        // activation policy gates per-frame execution by the published
        // value. The route admission's root-layer check would block child
        // layers (like the album-cover toggle on a nested layer), which is
        // exactly the family this channel serves.
        startupInactiveEffectVisibilityTargets =
            propertyBindingProgram
                .effectLocalDirectBoolEffectVisibilityTargets
                .union(scriptOwnedEffectVisibilityTargets)
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor,
            startupInactiveEffectVisibilityTargets:
                startupInactiveEffectVisibilityTargets,
            scriptOwnedEffectVisibilityTargets: scriptOwnedEffectVisibilityTargets
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
