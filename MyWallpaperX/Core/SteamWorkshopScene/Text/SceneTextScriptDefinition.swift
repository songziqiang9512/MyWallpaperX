import Foundation

/// Lossless authored input for a script-backed text field.
///
/// Keeping this separate from `SceneTextDescriptor` prevents unsupported scripts from
/// silently changing the authored fallback text. Execution is decided later by the
/// exact-profile or bounded-subset compiler.
nonisolated struct SceneTextScriptDefinition: Codable, Equatable, Sendable {
    let source: String
    let properties: [String: SceneJSONValue]

    nonisolated static func parse(_ value: Any?) -> SceneTextScriptDefinition? {
        guard let object = value as? [String: Any],
              let source = object["script"] as? String else {
            return nil
        }
        let rawProperties: [String: Any]
        if let authoredProperties = object["scriptproperties"] {
            guard let parsed = authoredProperties as? [String: Any] else { return nil }
            rawProperties = parsed
        } else {
            rawProperties = [:]
        }
        var properties: [String: SceneJSONValue] = [:]
        for (key, value) in rawProperties {
            guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
            properties[key] = parsed
        }
        return SceneTextScriptDefinition(source: source, properties: properties)
    }
}
