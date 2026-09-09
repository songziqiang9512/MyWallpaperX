import Foundation

/// Separates proven value producers from SceneScript attachments. An attachment
/// is only called a control when its exact behavior is already modeled; every
/// other script remains unproven because it may still produce a value.
nonisolated enum SceneResolvedMaterialScriptBindingClassifier {
    typealias Template = SceneResolvedMaterialTemplate

    struct Binding {
        let valueContributors: [Template.DynamicUniformSource]
        let scriptAttachments: [Template.DynamicUniformScriptAttachment]
    }

    enum Projection {
        case value(Template.DynamicUniformSource)
        case scriptAttachment(Template.DynamicUniformScriptAttachment)
    }

    static func binding(
        authored: SceneDocument.ShaderValue?,
        userValue: String?,
        target: SceneDynamicTarget?,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget>
    ) -> Binding? {
        var sources: [Template.DynamicUniformSource] = []
        var attachments: [Template.DynamicUniformScriptAttachment] = []
        let authoredUserProperty: String?
        if let raw = authored?.userBinding {
            guard let normalized = normalizedProviderValue(raw) else { return nil }
            authoredUserProperty = normalized
        } else {
            authoredUserProperty = nil
        }
        let projection = authored.flatMap {
            classify(
                authored: $0,
                target: target,
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            )
        }
        if case .value = projection {
            // The VM consumes Timeline as callback input and publishes the
            // single SceneScript result channel for this target.
        } else if authored?.timeline != nil {
            sources.append(.timeline)
        }
        if let projection {
            switch projection {
            case let .value(source):
                // A proven property-bound SceneScript owns the value channel;
                // `user` is its typed input and must not be treated as a
                // competing producer for the same material uniform.
                sources.append(source)
            case let .scriptAttachment(attachment):
                if let authoredUserProperty {
                    sources.append(.userProperty(authoredUserProperty))
                }
                attachments.append(attachment)
            }
        } else if let authoredUserProperty {
            sources.append(.userProperty(authoredUserProperty))
        }
        if let raw = userValue {
            guard let value = normalizedProviderValue(raw) else { return nil }
            // Runtime user input is consumed by the proven SceneScript
            // projection as its parameter; it is not a second material writer.
            if case .value(.sceneScript)? = projection {
                // keep the typed input in the SceneScript frame channel
            } else {
                sources.append(.userProperty(value))
            }
        }
        return Binding(valueContributors: sources, scriptAttachments: attachments)
    }

    static func classify(
        authored: SceneDocument.ShaderValue,
        target: SceneDynamicTarget?,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget>
    ) -> Projection? {
        guard let source = authored.scriptSource, !source.isEmpty else {
            return nil
        }
        if let target,
           authored.valueKind.localizedLowercase == "binding",
           authored.timelineDiagnostics.isEmpty,
           isProvenValueWrapper(authored),
           provenSceneScriptValueTargets.contains(target) {
            return .value(.sceneScript)
        }
        return .scriptAttachment(.unproven)
    }

    private static func isProvenValueWrapper(
        _ authored: SceneDocument.ShaderValue
    ) -> Bool {
        switch authored.bindingKeys {
        case ["script", "value"],
             ["script", "scriptproperties", "value"]:
            authored.userValueKind == nil && authored.timeline == nil
        case ["script", "user", "value"],
             ["script", "scriptproperties", "user", "value"]:
            authored.timeline == nil && (
                (authored.userValueKind == .null && authored.userBinding == nil)
                    || (authored.userValueKind == .string
                        && authored.userBinding.flatMap(normalizedProviderValue) != nil
                        && authored.components?.count == 3
                        && authored.components?.allSatisfy(\.isFinite) == true)
            )
        case ["animation", "script", "value"]:
            authored.userValueKind == nil && authored.timeline != nil
        default:
            false
        }
    }

    private static func normalizedProviderValue(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !value.unicodeScalars.contains(where: { $0.value < 32 })
            ? value : nil
    }
}
