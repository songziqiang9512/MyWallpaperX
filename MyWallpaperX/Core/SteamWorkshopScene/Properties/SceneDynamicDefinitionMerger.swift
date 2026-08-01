import Foundation

nonisolated enum SceneDynamicDefinitionMerger {
    nonisolated static func merge(
        propertyDefinitions: [SceneDynamicTargetDefinition],
        timelineProgram: SceneTimelineProgram,
        textScriptProgram: SceneTextScriptProgram,
        additionalDefinitions: [SceneDynamicTargetDefinition] = []
    ) -> [SceneDynamicTargetDefinition] {
        var definitions = propertyDefinitions
        var existing = Set(definitions.map(\.target))
        for definition in timelineProgram.bindings.map(\.definition)
            + textScriptProgram.bindings.map(\.definition) + additionalDefinitions {
            guard existing.insert(definition.target).inserted else { continue }
            definitions.append(definition)
        }
        return definitions
    }
}
