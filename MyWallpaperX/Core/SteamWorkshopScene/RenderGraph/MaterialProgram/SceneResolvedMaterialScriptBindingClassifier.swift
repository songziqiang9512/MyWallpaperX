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
        if let raw = authored?.userBinding {
            guard let value = normalizedProviderValue(raw) else { return nil }
            sources.append(.userProperty(value))
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
            case let .value(source): sources.append(source)
            case let .scriptAttachment(attachment): attachments.append(attachment)
            }
        }
        if let raw = userValue {
            guard let value = normalizedProviderValue(raw) else { return nil }
            sources.append(.userProperty(value))
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
           authored.userBinding == nil,
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
        case ["script", "user", "value"]:
            authored.userValueKind == .null && authored.timeline == nil
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
