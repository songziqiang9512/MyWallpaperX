import Foundation

nonisolated enum ScenePropertyVectorScriptRuntime {
    nonisolated static func values(
        program: ScenePropertyVectorScriptProgram,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { result, binding in
            guard case let .vector3(x, y, z) = binding.definition.authoredValue else {
                return
            }
            var value = SIMD3(x, y, z)
            switch binding.operation {
            case let .scalarSplat(input):
                guard let scalar = resolve(
                    input, effectivePropertyValues: effectivePropertyValues
                ) else { return }
                value = SIMD3(repeating: scalar)
            case let .components(components):
                for component in components {
                    guard let scalar = resolve(
                        component.input,
                        effectivePropertyValues: effectivePropertyValues
                    ) else { return }
                    value[component.component] = scalar
                }
            }
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return }
            result[binding.definition.target] = .vector3(value.x, value.y, value.z)
        }
    }

    private static func resolve(
        _ input: ScenePropertyVectorScriptScalarInput,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> Double? {
        let value: Double
        if let key = input.userPropertyKey,
           let live = effectivePropertyValues[key] {
            guard case let .number(number) = live else { return nil }
            value = number
        } else {
            value = input.fallback
        }
        return value.isFinite ? value : nil
    }
}
