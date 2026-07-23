import Foundation

nonisolated struct SceneUserPropertyDefinitionParser {
    nonisolated func parse(projectRoot: [String: Any]) -> SceneUserPropertyCatalog {
        let general = projectRoot["general"] as? [String: Any]
        let properties = general?["properties"] as? [String: Any] ?? [:]
        return parse(properties: properties)
    }

    nonisolated func parse(properties: [String: Any]) -> SceneUserPropertyCatalog {
        let definitions = properties.compactMap { key, rawValue -> SceneUserPropertyDefinition? in
            guard let property = rawValue as? [String: Any] else { return nil }
            return definition(key: key, property: property)
        }
        .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.index != $1.index { return ($0.index ?? Int.max) < ($1.index ?? Int.max) }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
        return SceneUserPropertyCatalog(definitions: definitions)
    }

    private nonisolated func definition(
        key: String,
        property: [String: Any]
    ) -> SceneUserPropertyDefinition {
        let runtimeType = Self.trimmedString(property["type"] as? String)?.lowercased() ?? ""
        let kind: SceneUserPropertyKind = switch runtimeType {
        case "texture", "scenetexture": .sceneTexture
        default: SceneUserPropertyKind(rawValue: runtimeType) ?? .unsupported
        }
        let rawTitle = Self.trimmedString(property["text"] as? String)
        return SceneUserPropertyDefinition(
            key: key,
            title: rawTitle ?? key.replacingOccurrences(of: "_", with: " "),
            kind: kind,
            runtimeType: runtimeType,
            order: Self.integer(property["order"]) ?? Self.integer(property["index"]) ?? 0,
            index: Self.integer(property["index"]),
            minimumValue: Self.number(property["min"]),
            maximumValue: Self.number(property["max"]),
            stepValue: Self.number(property["step"]),
            allowsFractionalValues: Self.boolean(property["fraction"]) ?? true,
            fractionalPrecision: Self.integer(property["precision"]),
            displayCondition: Self.trimmedString(property["condition"] as? String),
            defaultValue: SceneUserPropertyValue.parse(property["value"]),
            options: Self.options(property["options"] ?? property["values"])
        )
    }

    private nonisolated static func options(_ rawValue: Any?) -> [SceneUserPropertyOption] {
        if let array = rawValue as? [[String: Any]] {
            return array.compactMap { option in
                guard let value = SceneUserPropertyValue.parse(option["value"]) else { return nil }
                let label = trimmedString((option["label"] as? String) ?? (option["text"] as? String))
                    ?? String(describing: value.foundationValue)
                return SceneUserPropertyOption(
                    label: label,
                    value: value,
                    displayCondition: trimmedString(option["condition"] as? String)
                )
            }
        }
        if let dictionary = rawValue as? [String: Any] {
            return dictionary.compactMap { label, rawOption in
                guard let value = SceneUserPropertyValue.parse(rawOption) else { return nil }
                return SceneUserPropertyOption(label: label, value: value, displayCondition: nil)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        return []
    }

    private nonisolated static func number(_ rawValue: Any?) -> Double? {
        switch SceneUserPropertyValue.parse(rawValue) {
        case let .number(value): value
        case let .string(value): Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool, .none: nil
        }
    }

    private nonisolated static func integer(_ rawValue: Any?) -> Int? {
        guard let value = number(rawValue), value.isFinite else { return nil }
        return Int(value)
    }

    private nonisolated static func boolean(_ rawValue: Any?) -> Bool? {
        SceneUserPropertyValue.parse(rawValue)?.boolValue
    }

    private nonisolated static func trimmedString(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
