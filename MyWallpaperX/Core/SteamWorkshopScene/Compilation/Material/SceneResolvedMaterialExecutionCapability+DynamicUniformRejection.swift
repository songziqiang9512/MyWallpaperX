import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    static func dynamicUniformExecutionRejection(
        _ template: Template,
        node: Graph.Node,
        producers: DynamicProducerCatalog
    ) -> Rejection? {
        for declaration in template.uniformDeclarations {
            guard case let .dynamic(dynamic) = declaration.value else { continue }
            guard case let .effectConstant(
                layerID, effectIndex, passIndex, name
            ) = dynamic.target,
                layerID == node.effect.layerID,
                effectIndex == node.effect.effectIndex,
                passIndex == node.instancePassIndex,
                name == declaration.name else {
                return rejection("dynamic-uniform-unavailable")
            }
            let hasValueSource: (Template.DynamicUniformSource) -> Bool = { contributor in
                switch contributor {
                case let .userProperty(propertyKey):
                    let targetProducers = producers.userProperties.filter {
                        $0.target == dynamic.target
                    }
                    if targetProducers.isEmpty {
                        return hasAuthoredUserPropertyFallback(
                            dynamic: dynamic,
                            authoredFallbackTargets: producers.authoredFallbackTargets
                        )
                    }
                    guard targetProducers.count == 1,
                          let producer = targetProducers.first else { return false }
                    return producer.propertyKey == propertyKey
                        && userPropertyValueTypeMatches(producer.valueType, dynamic: dynamic)
                case .timeline:
                    return timelineDefinitionMatches(
                        dynamic,
                        producers: producers
                    )
                case .sceneScript:
                    return producers.sceneScriptTargets.contains(dynamic.target)
                }
            }
            if dynamic.valueContributors.isEmpty {
                guard dynamic.authoredFallback != nil,
                      dynamic.scriptAttachments == [.unproven] else {
                    return rejection("dynamic-uniform-unavailable")
                }
                return rejection("material-dynamic-uniform-script-attachment-unproven")
            }
            guard dynamic.valueContributors.count == 1 else {
                guard dynamic.scriptAttachments.isEmpty else {
                    return rejection("dynamic-uniform-unavailable")
                }
                guard dynamic.valueContributors.allSatisfy(hasValueSource) else {
                    return rejection(
                        "material-dynamic-uniform-contributor-producer-unavailable"
                    )
                }
                return rejection("material-dynamic-uniform-contributor-policy")
            }
            if !hasValueSource(dynamic.valueContributors[0]) {
                guard dynamic.scriptAttachments.isEmpty else {
                    return rejection("dynamic-uniform-unavailable")
                }
                return rejection("material-dynamic-uniform-producer-unavailable")
            }
            if dynamic.scriptAttachments == [.unproven] {
                return rejection("material-dynamic-uniform-script-attachment-unproven")
            }
            guard dynamic.scriptAttachments.isEmpty else {
                return rejection("dynamic-uniform-unavailable")
            }
        }
        return nil
    }

    static func rejection(
        _ code: String,
        programFailureAttribution: Rejection.ProgramFailureAttribution? = nil
    ) -> Rejection {
        .init(
            code: code,
            programFailureAttribution: programFailureAttribution
        )
    }
}
