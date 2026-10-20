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
    let condition: SceneUserPropertyValue?
    /// The declared producer domain is independent of the VM builder's seed.
    let userPropertyKind: SceneUserPropertyKind?

    init(fallback: SceneScriptHostValue, userPropertyKey: String?,
         condition: SceneUserPropertyValue?, userPropertyKind: SceneUserPropertyKind? = nil) {
        self.fallback = fallback
        self.userPropertyKey = userPropertyKey
        self.condition = condition
        self.userPropertyKind = userPropertyKind
    }

    func resolve(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> SceneScriptHostValue? {
        guard let userPropertyKey,
              let live = effectiveValues[userPropertyKey] else { return fallback }
        if let condition {
            guard case .bool = fallback else { return nil }
            return .bool(live.matches(condition))
        }
        switch (fallback, live) {
        case (.bool, .number(let value)):
            // A live user property passes JS assignment semantics under an
            // authored Boolean fallback (corpus: 3662790108 binds a slider to
            // a Boolean fallback): ToBoolean truthiness applies (NaN -> false,
            // infinities -> true).
            return .bool(!value.isNaN && value != 0)
        case (_, .number(let value)) where !value.isFinite:
            return nil
        case (.number, .number(let value)):
            return .number(value)
        case (.bool, .bool(let value)):
            return .bool(value)
        case (.string, .string(let value)):
            return .string(value)
        case (.number, .string(let value)) where userPropertyKind == .color:
            guard SceneScriptPropertyInputCodec.vector3(value) != nil else { return nil }
            // Color remains a String in a numeric builder slot. QuickJS owns
            // the slot's assignment semantics; do not coerce or broadcast it.
            return .string(value)
        default:
            return nil
        }
    }
}

nonisolated enum SceneScriptPropertyInputCodec {
    static func preparing(
        _ inputs: [String: SceneScriptPropertyInput],
        kinds: [String: SceneUserPropertyKind]
    ) -> [String: SceneScriptPropertyInput] {
        inputs.mapValues { input in
            .init(fallback: input.fallback, userPropertyKey: input.userPropertyKey,
                  condition: input.condition,
                  userPropertyKind: input.userPropertyKey.flatMap { kinds[$0] })
        }
    }

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
            return .init(
                fallback: fallback, userPropertyKey: nil, condition: nil
            )
        }
        guard let definition =
                SceneScriptUserPropertyInputContract.dynamicInput(value),
              let fallback = hostValue(definition.fallback) else { return nil }
        return .init(
            fallback: fallback,
            userPropertyKey: definition.userPropertyKey,
            condition: definition.condition
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
        return liveConsumerTargets(layerID: layerID, targetPath: targetPath, inputs: inputs)
    }

    static func liveConsumerTargets(
        layerID: Int, targetPath: [String], inputs: [String: SceneScriptPropertyInput]
    ) -> Set<SceneDynamicTarget> {
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
            // Shortcut assignments are native control-plane resources. This
            // slice does not expose the public structured shortcut object.
            guard validName(entry.key), kinds[entry.key] != .userShortcut else { return }
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
        kinds: [String: SceneUserPropertyKind],
        previousAttempt: [String: SceneUserPropertyValue]? = nil,
        pendingKeys: Set<String> = []
    ) -> String? {
        guard let previous else {
            return userPropertiesJSON(values: current, kinds: kinds)
        }
        var changedKeys = Set(previous.keys).union(current.keys).filter {
            previous[$0] != current[$0]
        }
        if let previousAttempt {
            changedKeys.formUnion(Set(previousAttempt.keys).union(current.keys).filter {
                previousAttempt[$0] != current[$0]
            })
        }
        changedKeys.formUnion(pendingKeys)
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

/// Per-owner derived input cache.  The live property values remain owned by
/// `ScenePropertyLiveUpdateState`; this cache stores only the encoded JSON
/// projection and is invalidated by that state's monotonic revision.  Calls
/// without a revision deliberately stay uncached for compatibility with
/// standalone evaluators and tests that do not have a live-state owner.
nonisolated struct SceneScriptPropertyInputJSONCache {
    private var revision: UInt64?
    private var encodedByTarget: [SceneDynamicTarget: String] = [:]

    mutating func remove(targets: Set<SceneDynamicTarget>) {
        for target in targets { encodedByTarget.removeValue(forKey: target) }
    }

    mutating func value(
        for target: SceneDynamicTarget,
        inputs: [String: SceneScriptPropertyInput],
        effectiveValues: [String: SceneUserPropertyValue],
        revision: UInt64?
    ) -> String? {
        guard let revision else {
            return SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                inputs,
                effectiveValues: effectiveValues
            )
        }
        if self.revision != revision {
            self.revision = revision
            encodedByTarget.removeAll(keepingCapacity: true)
        }
        if let encoded = encodedByTarget[target] {
            return encoded
        }
        guard let encoded = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
            inputs,
            effectiveValues: effectiveValues
        ) else {
            return nil
        }
        encodedByTarget[target] = encoded
        return encoded
    }
}

/// Per-owner acknowledgement of the live user-property snapshot. The live
/// values and revision remain owned by `ScenePropertyLiveUpdateState`; this
/// state only prevents unchanged frames from diffing the complete property
/// dictionary once per SceneScript owner. It is part of the existing frame
/// rollback snapshot so a rejected surface retries the same property event.
nonisolated struct SceneScriptAppliedUserPropertyState: Sendable {
    private var valuesByTarget:
        [SceneDynamicTarget: [String: SceneUserPropertyValue]] = [:]
    private var revisionsByTarget: [SceneDynamicTarget: UInt64] = [:]

    mutating func remove(targets: Set<SceneDynamicTarget>) {
        for target in targets {
            valuesByTarget.removeValue(forKey: target)
            revisionsByTarget.removeValue(forKey: target)
        }
    }

    mutating func retain(targets: Set<SceneDynamicTarget>) {
        valuesByTarget = valuesByTarget.filter { targets.contains($0.key) }
        revisionsByTarget = revisionsByTarget.filter { targets.contains($0.key) }
    }

    func changedJSON(
        for target: SceneDynamicTarget,
        current: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind],
        revision: UInt64?,
        preparedCurrentJSON: String? = nil,
        previousAttempt: [String: SceneUserPropertyValue]? = nil,
        pendingKeys: Set<String> = []
    ) -> String? {
        let previous = valuesByTarget[target]
        if let revision,
           revisionsByTarget[target] == revision,
           previous != nil {
            return nil
        }
        // The frame input owner already encoded this same current snapshot.
        // Reuse its bytes without acknowledging delivery: a failed owner must
        // still receive the full event again until record succeeds.
        if previous == nil, let preparedCurrentJSON {
            return preparedCurrentJSON
        }
        return SceneScriptPropertyInputCodec.changedUserPropertiesJSON(
            previous: previous, current: current, kinds: kinds,
            previousAttempt: previousAttempt, pendingKeys: pendingKeys
        )
    }

    mutating func restore(
        _ state: Self,
        for targets: Set<SceneDynamicTarget>
    ) {
        for target in targets {
            valuesByTarget[target] = state.valuesByTarget[target]
            revisionsByTarget[target] = state.revisionsByTarget[target]
        }
    }

    mutating func record(
        _ values: [String: SceneUserPropertyValue],
        revision: UInt64?,
        for target: SceneDynamicTarget
    ) {
        valuesByTarget[target] = values
        if let revision {
            revisionsByTarget[target] = revision
        } else {
            revisionsByTarget.removeValue(forKey: target)
        }
    }
}
