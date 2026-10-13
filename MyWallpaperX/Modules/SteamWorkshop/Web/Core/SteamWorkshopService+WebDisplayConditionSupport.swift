import Foundation

extension SteamWorkshopService {
    /// Immutable authored syntax. Current values remain owned by the existing
    /// input snapshot and are evaluated by the same parser on every update.
    struct WebDisplayConditionProgram {
        private let tokens: [WebDisplayConditionToken]?
        let referencedPropertyKeys: Set<String>

        nonisolated init(_ condition: String) {
            guard let tokens = SteamWorkshopService.webDisplayConditionTokens(condition) else {
                self.tokens = nil
                referencedPropertyKeys = []
                return
            }
            // Validate the same grammar without evaluating literal comparisons
            // against fabricated current values (or performing numeric casts).
            var syntax = WebDisplayConditionParser(
                tokens: tokens, values: [:], comboTextValues: [:],
                evaluatesComparisons: false
            )
            guard syntax.parse() != nil, syntax.isAtEnd else {
                self.tokens = nil
                referencedPropertyKeys = []
                return
            }
            self.tokens = tokens
            referencedPropertyKeys = Set(tokens.compactMap { token in
                guard case let .identifier(identifier) = token else { return nil }
                return WebDisplayConditionParser.propertyReference(identifier).key
            })
        }

        nonisolated func evaluate(inputs: WebDisplayConditionInputs) -> Bool {
            guard let tokens else { return true }
            return SteamWorkshopService.evaluateWebDisplayCondition(tokens: tokens, inputs: inputs)
        }
    }

    struct WebDisplayConditionInputs {
        let values: [String: SteamWorkshopWebPropertyValue]
        let comboTextValues: [String: String]

        nonisolated init(
            values: [String: SteamWorkshopWebPropertyValue],
            definitions: [SteamWorkshopWebPropertyDefinition]
        ) {
            self.values = values
            comboTextValues = definitions.reduce(into: [:]) { result, definition in
                guard definition.kind == .combo else { return }
                let value = values[definition.key] ?? definition.defaultValue
                if let option = definition.options.first(where: { $0.value == value }) {
                    result[definition.key] = option.label
                }
            }
        }
    }

    nonisolated static func evaluateWebDisplayCondition(
        _ condition: String,
        values: [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool {
        guard let tokens = webDisplayConditionTokens(condition) else { return true }
        return evaluateWebDisplayCondition(
            tokens: tokens,
            inputs: WebDisplayConditionInputs(values: values, definitions: definitions)
        )
    }

    nonisolated static func evaluateWebDisplayCondition(
        _ condition: String,
        inputs: WebDisplayConditionInputs
    ) -> Bool {
        guard let tokens = webDisplayConditionTokens(condition) else { return true }
        return evaluateWebDisplayCondition(tokens: tokens, inputs: inputs)
    }

    private nonisolated static func webDisplayConditionTokens(
        _ condition: String
    ) -> [WebDisplayConditionToken]? {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("?") == false,
              containsOnlySupportedConditionOperators(trimmed) else {
            return nil
        }
        return tokenizeWebDisplayCondition(trimmed)
    }

    private nonisolated static func evaluateWebDisplayCondition(
        tokens: [WebDisplayConditionToken],
        inputs: WebDisplayConditionInputs
    ) -> Bool {
        var parser = WebDisplayConditionParser(
            tokens: tokens,
            values: inputs.values,
            comboTextValues: inputs.comboTextValues
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
