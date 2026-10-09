import Foundation

extension SteamWorkshopService {
    nonisolated static func evaluateWebDisplayCondition(
        _ condition: String,
        values: [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard trimmed.contains("?") == false,
              containsOnlySupportedConditionOperators(trimmed) else {
            return true
        }

        guard let tokens = tokenizeWebDisplayCondition(trimmed) else {
            return true
        }

        let comboTextValues = definitions.reduce(into: [String: String]()) { result, definition in
            guard definition.kind == .combo else { return }
            let value = values[definition.key] ?? definition.defaultValue
            if let option = definition.options.first(where: { $0.value == value }) {
                result[definition.key] = option.label
            }
        }

        var parser = WebDisplayConditionParser(
            tokens: tokens,
            values: values,
            comboTextValues: comboTextValues
        )
        guard let result = parser.parse(),
              parser.isAtEnd else {
            return true
        }
        return result.boolValue
    }

    nonisolated static func webDisplayConditionUsesOnlySupportedOperators(_ condition: String) -> Bool {
        containsOnlySupportedConditionOperators(condition)
    }

    nonisolated static func canTokenizeWebDisplayCondition(_ condition: String) -> Bool {
        tokenizeWebDisplayCondition(condition) != nil
    }

    static func webDisplayConditionReferencesKey(_ condition: String, key: String) -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty,
              let tokens = tokenizeWebDisplayCondition(condition) else {
            return false
        }

        for token in tokens {
            guard case let .identifier(identifier) = token else { continue }
            let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedIdentifier == normalizedKey
                || normalizedIdentifier == "\(normalizedKey).value"
                || normalizedIdentifier == "\(normalizedKey).text" {
                return true
            }
        }
        return false
    }
}
