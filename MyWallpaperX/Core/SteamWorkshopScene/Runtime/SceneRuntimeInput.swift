import Foundation

struct SceneRuntimeInput: Codable {
    let renderDescriptor: SceneRenderDescriptor
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let propertyBindingProgram: ScenePropertyBindingProgram
    let directBoolEffectVisibilityTargets: Set<SceneDynamicTarget>
    let startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget>
    let effectivePropertyValues: [String: SceneUserPropertyValue]
    let shaderContracts: [SceneShaderContract]

    init(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract]
    ) {
        self.renderDescriptor = renderDescriptor
        directBoolEffectVisibilityTargets =
            propertyBindingProgram.directBoolEffectVisibilityTargets
        startupInactiveEffectVisibilityTargets =
            SceneDirectBoolEffectVisibilityRouteAdmission.startupInactiveTargets(
                in: renderDescriptor,
                candidates: directBoolEffectVisibilityTargets
            )
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor,
            startupInactiveEffectVisibilityTargets:
                startupInactiveEffectVisibilityTargets
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
