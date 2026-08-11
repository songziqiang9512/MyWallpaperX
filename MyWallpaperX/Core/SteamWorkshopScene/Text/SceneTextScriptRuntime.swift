import Foundation

nonisolated enum SceneTextScriptRuntime {
    nonisolated static func values(
        program: SceneTextScriptProgram,
        wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { values, binding in
            guard let content = content(
                binding: binding,
                wallDate: wallDate,
                timeZone: timeZone
            ) else { return }
            values[binding.target] = .string(content)
        }
    }

    private nonisolated static func content(
        binding: SceneTextScriptProgram.Binding,
        wallDate: Date,
        timeZone: TimeZone
    ) -> String? {
        guard case let .scriptSubset(program, properties) = binding.configuration,
              case let .string(authoredValue) = binding.definition.authoredValue else {
            return nil
        }
        return SceneTextScriptSubsetRuntime.evaluate(
            program: program,
            authoredValue: authoredValue,
            properties: properties,
            wallDate: wallDate,
            timeZone: timeZone
        )
    }
}
