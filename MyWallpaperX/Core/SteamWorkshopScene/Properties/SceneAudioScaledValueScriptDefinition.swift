import Foundation

/// Lossless authored wrapper for the stock 16-band audio-scaled value family.
/// The same property script is authored on scalar particle fields and Vec3
/// layer scale fields. Parsing preserves identity only; the compiler admits a
/// bounded target/type combination or the projection fails that owner closed.
nonisolated struct SceneAudioScaledValueScriptDefinition:
    Codable, Equatable, Sendable
{
    let source: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let wrapperKeys: [String]

    nonisolated static func parse(
        authoredWrapper: Any?,
        resolvedWrapper: Any?
    ) -> Self? {
        guard let authored = authoredWrapper as? [String: Any],
              let source = authored["script"] as? String,
              let resolved = resolvedWrapper as? [String: Any],
              let properties = properties(resolved["scriptproperties"]) else {
            return nil
        }
        return Self(
            source: source,
            properties: properties,
            authoredValue: authored["value"].flatMap(
                SceneJSONValue.init(jsonObject:)
            ),
            wrapperKeys: authored.keys.sorted()
        )
    }

    private nonisolated static func properties(
        _ rawValue: Any?
    ) -> [String: SceneJSONValue]? {
        guard let object = rawValue as? [String: Any] else { return nil }
        var result: [String: SceneJSONValue] = [:]
        for (key, rawValue) in object {
            guard let value = resolvedPropertyValue(rawValue) else { return nil }
            result[key] = value
        }
        return result
    }

    /// The document resolver preserves the wrapper identity but replaces its
    /// `value` with the effective property value. The script observes that
    /// scalar, never the wrapper object itself.
    private nonisolated static func resolvedPropertyValue(
        _ rawValue: Any
    ) -> SceneJSONValue? {
        if let wrapper = rawValue as? [String: Any],
           wrapper.keys.contains("user") {
            guard let value = wrapper["value"] else { return nil }
            return SceneJSONValue(jsonObject: value)
        }
        return SceneJSONValue(jsonObject: rawValue)
    }
}
