import Foundation

nonisolated enum SceneTextScriptRuntime {
    nonisolated static func values(
        program: SceneTextScriptProgram,
        wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        mediaProperties: SceneTextMediaPropertiesSnapshot = .empty
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { values, binding in
            guard let content = content(
                binding: binding,
                wallDate: wallDate,
                timeZone: timeZone,
                mediaProperties: mediaProperties
            ) else { return }
            values[binding.target] = .string(content)
        }
    }

    private nonisolated static func content(
        binding: SceneTextScriptProgram.Binding,
        wallDate: Date,
        timeZone: TimeZone,
        mediaProperties: SceneTextMediaPropertiesSnapshot
    ) -> String? {
        switch binding.configuration {
        case let .scriptSubset(program, properties):
            guard case let .string(authoredValue) = binding.definition.authoredValue else {
                return nil
            }
            return SceneTextScriptSubsetRuntime.evaluate(
                program: program,
                authoredValue: authoredValue,
                properties: properties,
                wallDate: wallDate,
                timeZone: timeZone
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
