import Foundation

nonisolated struct ScenePropertyLiveUpdateState {
    let program: ScenePropertyBindingProgram
    let activeConsumerTargets: Set<SceneDynamicTarget>
    private(set) var effectiveValues: [String: SceneUserPropertyValue]
    private(set) var userValues: [SceneDynamicTarget: SceneDynamicValue]

    nonisolated init(
        program: ScenePropertyBindingProgram,
        effectiveValues: [String: SceneUserPropertyValue],
        activeConsumerTargets: Set<SceneDynamicTarget>
    ) {
        self.program = program
        self.activeConsumerTargets = activeConsumerTargets
        self.effectiveValues = effectiveValues
        self.userValues = program.evaluate(effectiveValues: effectiveValues).userValues
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

        let rebuildRequiredKeys = Set(program.rebuildRequiredPropertyKeys)
        guard rebuildRequiredKeys.isDisjoint(with: changedPropertyKeys) else {
            return false
        }

        let instructionsByKey = Dictionary(grouping: program.instructions, by: \.propertyKey)
        var expectedTargets: Set<SceneDynamicTarget> = []
        for propertyKey in changedPropertyKeys {
            guard let instructions = instructionsByKey[propertyKey], !instructions.isEmpty,
                  instructions.allSatisfy({
                      activeConsumerTargets.contains($0.target)
                          && !unavailableConsumerTargets.contains($0.target)
                  }) else {
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

        let evaluation = program.evaluate(effectiveValues: candidateEffectiveValues)
        guard expectedTargets.allSatisfy({ evaluation.userValues[$0] != nil }) else {
            return false
        }

        effectiveValues = candidateEffectiveValues
        userValues = evaluation.userValues
        return true
    }
}
