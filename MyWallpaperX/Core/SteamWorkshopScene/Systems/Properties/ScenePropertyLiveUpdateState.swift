import Foundation

nonisolated struct ScenePropertyLiveUpdateState {
    let program: ScenePropertyBindingProgram
    let activeConsumerTargets: Set<SceneDynamicTarget>
    let scriptUserPropertyConsumerTargetsByKey:
        [String: Set<SceneDynamicTarget>]
    private let validation: ScenePropertyBindingProgramValidation
    private let instructionsByPropertyKey:
        [String: [ScenePropertyBindingInstruction]]
    private let rebuildRequiredKeys: Set<String>
    private let unboundBooleanPropertyKeys: Set<String>
    private(set) var effectiveValues: [String: SceneUserPropertyValue]
    private(set) var userValues: [SceneDynamicTarget: SceneDynamicValue]
    /// Monotonic content revision. Bumped only when `effectiveValues` is
    /// replaced by a successful apply; consumers may key prepared encodings
    /// (for example the per-frame user-properties JSON) on this value.
    private(set) var revision: UInt64 = 0

    nonisolated init(
        program: ScenePropertyBindingProgram,
        effectiveValues: [String: SceneUserPropertyValue],
        activeConsumerTargets: Set<SceneDynamicTarget>,
        scriptUserPropertyConsumerTargetsByKey:
            [String: Set<SceneDynamicTarget>] = [:],
        propertyDefinitions: [SceneUserPropertyDefinition] = []
    ) {
        self.program = program
        self.activeConsumerTargets = activeConsumerTargets
        self.scriptUserPropertyConsumerTargetsByKey =
            scriptUserPropertyConsumerTargetsByKey
        let validation = ScenePropertyBindingProgramValidator().validate(program)
        self.validation = validation
        self.instructionsByPropertyKey = Dictionary(
            grouping: validation.instructions,
            by: \.propertyKey
        )
        self.rebuildRequiredKeys = Set(program.rebuildRequiredPropertyKeys)
        // An unbound value may still control panel conditions. Keep catalog
        // type evidence here; effective values alone cannot distinguish a
        // resource key or an unknown/malformed definition.
        let definitionsByKey = Dictionary(grouping: propertyDefinitions, by: \.key)
        self.unboundBooleanPropertyKeys = Set(definitionsByKey.compactMap { key, definitions -> String? in
            guard definitions.count == 1, let definition = definitions.first,
                  definition.kind == .bool, case .bool? = definition.defaultValue else { return nil }
            return key
        }).subtracting(program.instructions.map(\.propertyKey))
        self.effectiveValues = effectiveValues
        self.userValues = program.evaluate(
            effectiveValues: effectiveValues,
            validation: validation
        ).userValues
    }

    @discardableResult
    nonisolated mutating func apply(
        _ value: SceneUserPropertyValue,
        forPropertyKey propertyKey: String,
        unavailableConsumerTargets: Set<SceneDynamicTarget> = [],
        retiredScriptCallbackTargets: Set<SceneDynamicTarget> = []
    ) -> Bool {
        apply(
            replacements: [propertyKey: value],
            changedPropertyKeys: [propertyKey],
            unavailableConsumerTargets: unavailableConsumerTargets,
            retiredScriptCallbackTargets: retiredScriptCallbackTargets
        )
    }

    @discardableResult
    nonisolated mutating func apply(
        replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>,
        unavailableConsumerTargets: Set<SceneDynamicTarget> = [],
        retiredScriptCallbackTargets: Set<SceneDynamicTarget> = [],
        preparedTexturePropertyKeys: Set<String> = []
    ) -> Bool {
        guard !changedPropertyKeys.isEmpty else { return true }

        // A known ordinary value resend needs no consumer or structural change.
        // Resource requests retain their original validation and retry path.
        if preparedTexturePropertyKeys.isDisjoint(with: changedPropertyKeys),
           changedPropertyKeys.allSatisfy({ key in
               guard let current = effectiveValues[key], let replacement = replacements[key] else { return false }
               let known = instructionsByPropertyKey[key]?.isEmpty == false
                   || scriptUserPropertyConsumerTargetsByKey[key]?.isEmpty == false
                   || rebuildRequiredKeys.contains(key)
               if !known {
                   guard unboundBooleanPropertyKeys.contains(key),
                         case .bool = current, case .bool = replacement else { return false }
               }
               return replacement == current
           }) { return true }

        guard rebuildRequiredKeys.isDisjoint(with: changedPropertyKeys) else {
            return false
        }

        var expectedTargets: Set<SceneDynamicTarget> = []
        for propertyKey in changedPropertyKeys {
            let instructions = instructionsByPropertyKey[propertyKey] ?? []
            // A committed layer deletion ends its event subscriptions. Keep
            // explicit value producers below: a live clone may still consume
            // a prepared input whose identity belongs to its source template.
            let registeredScriptTargets = scriptUserPropertyConsumerTargetsByKey[propertyKey] ?? []
            let scriptTargets = registeredScriptTargets.subtracting(retiredScriptCallbackTargets)
            let consumerTargets = Set(instructions.map(\.target))
                .union(scriptTargets)
            let preparedTexture = preparedTexturePropertyKeys.contains(propertyKey)
                && replacements[propertyKey]?.stringValue != nil
                && effectiveValues[propertyKey]?.stringValue != nil
            let valueOnlyBoolean: Bool
            if unboundBooleanPropertyKeys.contains(propertyKey),
               instructions.isEmpty, registeredScriptTargets.isEmpty,
               !preparedTexturePropertyKeys.contains(propertyKey),
               case .bool? = replacements[propertyKey],
               case .bool? = effectiveValues[propertyKey] {
                valueOnlyBoolean = true
            } else { valueOnlyBoolean = false }
            guard !consumerTargets.isEmpty || preparedTexture || valueOnlyBoolean,
                  consumerTargets.allSatisfy({
                      activeConsumerTargets.contains($0)
                          && !unavailableConsumerTargets.contains($0)
                  }),
                  instructions.isEmpty == false
                    || Self.sameRuntimeValueKind(
                        replacements[propertyKey], effectiveValues[propertyKey]
                    ) else {
                return false
            }
            expectedTargets.formUnion(instructions.map(\.target))
        }

        var candidateEffectiveValues = effectiveValues
        for propertyKey in changedPropertyKeys {
            if let replacement = replacements[propertyKey] {
                candidateEffectiveValues[propertyKey] = replacement
            } else {
                candidateEffectiveValues.removeValue(forKey: propertyKey)
            }
        }

        // A UI resend of the current value is a successful no-op.  Keep the
        // typed payload and revision stable so downstream JSON/VM/provider
        // consumers do not observe a false invalidation.
        guard candidateEffectiveValues != effectiveValues else { return true }

        let evaluation = program.evaluate(
            effectiveValues: candidateEffectiveValues,
            validation: validation
        )
        guard expectedTargets.allSatisfy({ evaluation.userValues[$0] != nil }) else {
            return false
        }

        effectiveValues = candidateEffectiveValues
        userValues = evaluation.userValues
        revision &+= 1
        return true
    }

    private nonisolated static func sameRuntimeValueKind(
        _ replacement: SceneUserPropertyValue?,
        _ current: SceneUserPropertyValue?
    ) -> Bool {
        guard let current else { return false }
        guard let replacement else { return true }
        switch (replacement, current) {
        case (.string, .string), (.number, .number), (.bool, .bool):
            return true
        default:
            return false
        }
    }
}
