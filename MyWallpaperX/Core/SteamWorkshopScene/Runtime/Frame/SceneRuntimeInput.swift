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

    var scriptEffectVisibilityDefinitions: [SceneDynamicTargetDefinition] {
        renderDescriptor.layers.flatMap { layer in
            layer.effects.enumerated().compactMap { index, effect in
                let target = SceneDynamicTarget.effectVisibility(layerID: layer.id, effectIndex: index)
                guard scriptOwnedEffectVisibilityTargets.contains(target) else { return nil }
                return .init(target: target, valueType: .bool, authoredValue: .bool(effect.visible ?? true))
            }
        }
    }

    init(
        renderDescriptor: SceneRenderDescriptor,
        propertyBindingProgram: ScenePropertyBindingProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        shaderContracts: [SceneShaderContract],
        scriptOwnedEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        hasScriptLayerAccess: Bool = false
    ) {
        self.renderDescriptor = renderDescriptor
        // Cross-layer handles accept computed names and indices. Their writes
        // use the same typed effect visibility channel as an inline owner.
        let scriptOwnedEffectVisibilityTargets = scriptOwnedEffectVisibilityTargets
            .union(hasScriptLayerAccess ? Set(renderDescriptor.layers.flatMap { layer in
                layer.effects.indices.map {
                    SceneDynamicTarget.effectVisibility(layerID: layer.id, effectIndex: $0)
                }
            }) : [])
        directBoolEffectVisibilityTargets =
            propertyBindingProgram.directBoolEffectVisibilityTargets
        self.scriptOwnedEffectVisibilityTargets =
            scriptOwnedEffectVisibilityTargets
        // Visibility producers share one preparation path; only the frame value
        // decides whether a prepared stage executes.
        startupInactiveEffectVisibilityTargets =
            propertyBindingProgram
                .liveEffectVisibilityTargets
                .union(scriptOwnedEffectVisibilityTargets)
        authoredEffectRenderPlans = SceneAuthoredEffectRenderPlanner.plans(
            for: renderDescriptor,
            startupInactiveEffectVisibilityTargets:
                SceneDirectBoolEffectVisibilityRouteAdmission
                .startupInactiveTargets(
                    in: renderDescriptor,
                    candidates: startupInactiveEffectVisibilityTargets,
                    dynamicLayerVisibilityOwnerTargets:
                        propertyBindingProgram.liveLayerVisibilityTargets,
                    scriptOwnedCandidates: scriptOwnedEffectVisibilityTargets
                ),
            shaderContracts: shaderContracts
        )
        self.propertyBindingProgram = propertyBindingProgram
        self.effectivePropertyValues = effectivePropertyValues
        self.shaderContracts = shaderContracts
    }
}
