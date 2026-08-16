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
        if authored?.timeline != nil { sources.append(.timeline) }
        if let authored,
           let projection = classify(
               authored: authored,
               target: target,
               provenSceneScriptValueTargets: provenSceneScriptValueTargets
           ) {
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
           authored.timeline == nil,
           authored.timelineDiagnostics.isEmpty,
           isProvenValueWrapper(authored.bindingKeys),
           provenSceneScriptValueTargets.contains(target) {
            return .value(.sceneScript)
        }
        return .scriptAttachment(
            isKnownMediaRestartControl(source)
                ? .mediaThumbnailAnimationRestart
                : .unproven
        )
    }

    private static func isProvenValueWrapper(_ keys: [String]) -> Bool {
        keys == ["script", "value"]
            || keys == ["script", "scriptproperties", "value"]
    }

    /// The existing control-only profile remains deliberately limited to the
    /// modeled stop/play restart shape.
    private static func isKnownMediaRestartControl(_ source: String) -> Bool {
        let compact = source
            .replacingOccurrences(
                of: #"/\*[\s\S]*?\*/"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"//[^\n\r]*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let pattern = #"^exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{if\(\1\.hasThumbnail\)\{(?:var|let|const)([A-Za-z_$][A-Za-z0-9_$]*)=thisObject\.getAnimation\(\);\2\.stop\(\);\2\.play\(\);?\}\}$"#
        return compact.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizedProviderValue(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !value.unicodeScalars.contains(where: { $0.value < 32 })
            ? value : nil
    }
}
