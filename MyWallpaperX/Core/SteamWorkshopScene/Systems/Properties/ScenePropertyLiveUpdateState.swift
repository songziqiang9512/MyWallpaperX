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
            [String: Set<SceneDynamicTarget>] = [:]
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
        unavailableConsumerTargets: Set<SceneDynamicTarget> = []
    ) -> Bool {
        apply(
            replacements: [propertyKey: value],
            changedPropertyKeys: [propertyKey],
            unavailableConsumerTargets: unavailableConsumerTargets
        )
    }

    @discardableResult
    nonisolated mutating func apply(
        replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>,
        unavailableConsumerTargets: Set<SceneDynamicTarget> = []
    ) -> Bool {
        guard !changedPropertyKeys.isEmpty else { return true }

        guard rebuildRequiredKeys.isDisjoint(with: changedPropertyKeys) else {
            return false
        }

        var expectedTargets: Set<SceneDynamicTarget> = []
        for propertyKey in changedPropertyKeys {
            let instructions = instructionsByPropertyKey[propertyKey] ?? []
            let scriptTargets =
                scriptUserPropertyConsumerTargetsByKey[propertyKey] ?? []
            let consumerTargets = Set(instructions.map(\.target))
                .union(scriptTargets)
            guard !consumerTargets.isEmpty,
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
