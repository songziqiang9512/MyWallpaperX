import Foundation

nonisolated enum SceneTextScriptRuntime {
    nonisolated static func values(
        program: SceneTextScriptProgram,
        wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        mediaProperties: SceneTextMediaPropertiesSnapshot = .empty
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        // Build calendar components only if a date-script binding needs them,
        // and at most once for every binding evaluated in this host frame.
        var wallDateContext: SceneTextScriptSubsetRuntime.FrameContext?
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        values.reserveCapacity(program.bindings.count)
        for binding in program.bindings {
            guard let content = content(
                binding: binding,
                wallDate: wallDate,
                timeZone: timeZone,
                mediaProperties: mediaProperties,
                wallDateContext: &wallDateContext
            ) else { continue }
            values[binding.target] = .string(content)
        }
        return values
    }

    private nonisolated static func content(
        binding: SceneTextScriptProgram.Binding,
        wallDate: Date,
        timeZone: TimeZone,
        mediaProperties: SceneTextMediaPropertiesSnapshot,
        wallDateContext:
            inout SceneTextScriptSubsetRuntime.FrameContext?
    ) -> String? {
        switch binding.configuration {
        case let .scriptSubset(program, properties):
            guard case let .string(authoredValue) = binding.definition.authoredValue else {
                return nil
            }
            if wallDateContext == nil {
                wallDateContext = .init(
                    wallDate: wallDate,
                    timeZone: timeZone
                )
            }
            guard let wallDateContext else { return nil }
            return SceneTextScriptSubsetRuntime.evaluate(
                program: program,
                authoredValue: authoredValue,
                properties: properties,
                frameContext: wallDateContext
            )
        case let .mediaProperties(field):
            guard mediaProperties.generation > 0 else { return nil }
            switch field {
            case .title: return mediaProperties.title
            case .artist: return mediaProperties.artist
            }
        }
    }
}
