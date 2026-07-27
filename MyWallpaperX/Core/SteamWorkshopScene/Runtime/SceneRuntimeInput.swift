import Foundation

struct SceneRuntimeInput: Codable {
    let renderDescriptor: SceneRenderDescriptor
    let authoredEffectRenderPlans: [SceneAuthoredEffectRenderPlan]
    let propertyBindingProgram: ScenePropertyBindingProgram
    let effectivePropertyValues: [String: SceneUserPropertyValue]
    let shaderContracts: [SceneShaderContract]

    init(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract]
    ) {
        self.renderDescriptor = renderDescriptor
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
