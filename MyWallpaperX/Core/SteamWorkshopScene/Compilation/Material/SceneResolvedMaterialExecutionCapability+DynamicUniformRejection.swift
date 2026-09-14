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
            let hasProducer: (Template.DynamicUniformSource) -> Bool = { contributor in
                switch contributor {
                case let .userProperty(propertyKey):
                    return soleUserPropertyProducerMatches(
                        propertyKey, dynamic: dynamic, producers: producers
                    )
                case .timeline:
                    return timelineDefinitionMatches(
                        dynamic,
                        producers: producers
                    )
                case .sceneScript:
                    return producers.sceneScriptTargets.contains(dynamic.target)
                }
            }
            let hasMismatchedProducerIdentity: (
                Template.DynamicUniformSource
            ) -> Bool = { contributor in
                switch contributor {
                case let .userProperty(propertyKey):
                    return producers.userProperties.contains {
                        $0.propertyKey == propertyKey && $0.target != dynamic.target
                    }
                case .timeline, .sceneScript:
                    return false
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
                guard dynamic.scriptAttachments.isEmpty,
                      !dynamic.valueContributors.contains(
                          where: hasMismatchedProducerIdentity
                      ) else {
                    return rejection("dynamic-uniform-unavailable")
                }
                guard dynamic.valueContributors.allSatisfy(hasProducer) else {
                    return rejection(
                        "material-dynamic-uniform-contributor-producer-unavailable"
                    )
                }
                return rejection("material-dynamic-uniform-contributor-policy")
            }
            guard let contributor = dynamic.valueContributors.first else {
                return rejection("dynamic-uniform-unavailable")
            }
            if !hasProducer(contributor) {
                if hasAuthoredUserPropertyFallback(
                    contributor, dynamic: dynamic, producers: producers
                ) {
                    guard dynamic.scriptAttachments.isEmpty else {
                        return rejection("dynamic-uniform-unavailable")
                    }
                    continue
                }
                guard dynamic.scriptAttachments.isEmpty,
                      !hasMismatchedProducerIdentity(contributor) else {
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
