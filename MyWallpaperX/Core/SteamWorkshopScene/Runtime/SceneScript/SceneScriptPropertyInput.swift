import Foundation

nonisolated enum SceneScriptHostValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case vector3(Double, Double, Double)

    var jsonObject: Any {
        switch self {
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .vector3(x, y, z): ["x": x, "y": y, "z": z]
        }
    }
}

/// Immutable authored binding metadata. Live values continue to come from the
/// surface-scoped property snapshot on every callback.
nonisolated struct SceneScriptPropertyInput: Equatable, Sendable {
    let fallback: SceneScriptHostValue
    let userPropertyKey: String?

    func resolve(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> SceneScriptHostValue? {
        guard let userPropertyKey,
              let live = effectiveValues[userPropertyKey] else { return fallback }
        switch (fallback, live) {
        case (_, .number(let value)) where !value.isFinite:
            return nil
        case (.number, .number(let value)):
            return .number(value)
        case (.bool, .bool(let value)):
            return .bool(value)
        case (.string, .string(let value)):
            return .string(value)
        default:
            return nil
        }
    }
}

nonisolated enum SceneScriptPropertyInputCodec {
    static func inputs(
        _ properties: [String: SceneJSONValue]
    ) -> [String: SceneScriptPropertyInput]? {
        var inputs: [String: SceneScriptPropertyInput] = [:]
        for (key, value) in properties {
            guard validName(key), let input = propertyInput(value) else {
                return nil
            }
            inputs[key] = input
        }
        return inputs
    }

    static func propertyInput(
        _ value: SceneJSONValue
    ) -> SceneScriptPropertyInput? {
        if let fallback = hostValue(value) {
            return .init(fallback: fallback, userPropertyKey: nil)
        }
        guard let definition =
                SceneScriptUserPropertyInputContract.dynamicInput(value),
              let fallback = hostValue(definition.fallback) else { return nil }
        return .init(
            fallback: fallback,
            userPropertyKey: definition.userPropertyKey
        )
    }

    static func validName(_ value: String) -> Bool {
        SceneScriptUserPropertyInputContract.validName(value)
    }

    static func scriptPropertiesJSON(
        _ inputs: [String: SceneScriptPropertyInput],
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String? {
        if inputs.isEmpty { return "" }
        var object: [String: Any] = [:]
        for (key, input) in inputs {
            guard let value = input.resolve(effectiveValues: effectiveValues) else {
                return nil
            }
            object[key] = value.jsonObject
        }
        return json(object)
    }

    static func liveConsumerTargets(
        binding: SceneScriptBindingIR,
        inputs: [String: SceneScriptPropertyInput]
    ) -> Set<SceneDynamicTarget> {
        guard let layerID = binding.owner.objectID else { return [] }
        let targetPath = binding.targetPath.map { component in
            switch component {
            case let .key(key):
                SceneScriptPropertyTargetPath.keyComponent(key)
            case let .index(index):
                SceneScriptPropertyTargetPath.indexComponent(index)
            }
        }
        return Set(inputs.compactMap { name, input -> SceneDynamicTarget? in
            guard input.userPropertyKey != nil else { return nil }
            return .scriptInstanceProperty(
                layerID: layerID,
                path: targetPath + [
                    SceneScriptPropertyTargetPath.keyComponent("scriptproperties"),
                    SceneScriptPropertyTargetPath.keyComponent(name),
                ]
            )
        })
    }

    static func userPropertiesJSON(
        values: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind]
    ) -> String {
        let object = values.reduce(into: [String: Any]()) { result, entry in
            guard validName(entry.key) else { return }
            switch (kinds[entry.key], entry.value) {
            case (.color, .string(let value)):
                if let color = vector3(value) {
                    result[entry.key] = SceneScriptHostValue.vector3(
                        color.x, color.y, color.z
                    ).jsonObject
                }
            case (_, .number(let value)) where value.isFinite:
                result[entry.key] = value
            case (_, .bool(let value)):
                result[entry.key] = value
            case (_, .string(let value)):
                result[entry.key] = value
            default:
                break
            }
        }
        return json(object) ?? "{}"
    }

    static func changedUserPropertiesJSON(
        previous: [String: SceneUserPropertyValue]?,
        current: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind]
    ) -> String? {
        guard let previous else {
            return userPropertiesJSON(values: current, kinds: kinds)
        }
        let changedKeys = Set(previous.keys).union(current.keys).filter {
            previous[$0] != current[$0]
        }
        guard !changedKeys.isEmpty else { return nil }
        var object: [String: Any] = [:]
        for key in changedKeys where validName(key) {
            guard let value = current[key] else {
                object[key] = NSNull()
                continue
            }
            let encoded = userPropertiesJSON(
                values: [key: value],
                kinds: kinds
            )
            guard let data = encoded.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = item as? [String: Any],
                  let encodedValue = dictionary[key] else { continue }
            object[key] = encodedValue
        }
        return object.isEmpty ? nil : json(object)
    }

    static func vector3(_ value: String) -> SIMD3<Double>? {
        let parts = value.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 3, numbers.allSatisfy(\.isFinite) else { return nil }
        return .init(numbers[0], numbers[1], numbers[2])
    }

    static func vector2(_ value: String) -> SIMD2<Double>? {
        let parts = value.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 2 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 2, numbers.allSatisfy(\.isFinite) else { return nil }
        return .init(numbers[0], numbers[1])
    }

    private static func hostValue(
        _ value: SceneJSONValue
    ) -> SceneScriptHostValue? {
        switch value {
        case let .number(number) where number.isFinite: .number(number)
        case let .bool(value): .bool(value)
        case let .string(value): .string(value)
        default: nil
        }
    }

    private static func json(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
