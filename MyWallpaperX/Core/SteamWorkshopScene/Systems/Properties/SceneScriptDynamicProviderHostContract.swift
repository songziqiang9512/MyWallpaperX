import Foundation

/// Exact outer-wrapper shapes shared by property routing and the SceneScript
/// scalar/vector/text candidate catalogs. Boolean visibility may receive an
/// outer user property through the existing lower-priority typed input channel;
/// text content and ordinary Sound volume also accept a named outer input.
/// Sound volume retains its own Number contract instead of widening scalars.
nonisolated enum SceneScriptDynamicProviderHostContract {
    struct NamedSoundVolumeInput: Sendable {
        let source: String
        let userPropertyKey: String
        let volumeSeed: Double
    }

    enum HostKind: Equatable, Sendable {
        case objectScalar
        case soundVolume
        case objectVector
        case objectVisibility
        case objectText
        case particleValue
        case passConstant

        var acceptsNullOuterUser: Bool {
            switch self {
            case .objectVector, .objectText, .particleValue, .passConstant:
                return true
            case .objectScalar, .soundVolume, .objectVisibility:
                return false
            }
        }

        /// Hosts whose outer `user` key may carry a real user property key
        /// instead of being absent or null.
        var acceptsStringOuterUser: Bool {
            self == .objectVisibility || self == .objectText || self == .soundVolume
        }
    }

    static func supports(keys: [String], host: HostKind) -> Bool {
        (host == .objectVisibility
            && (keys == ["script", "user", "value"]
                || keys == ["script", "scriptproperties", "user", "value"]))
            || (host == .soundVolume
                && (keys == ["script", "user", "value"]
                    || keys == ["script", "scriptproperties", "user", "value"]))
            || (host == .objectText
                && (keys == ["script", "value"]
                    || keys == ["script", "user", "value"]))
            || (host == .particleValue && keys == ["script", "value"])
            || (host == .particleValue
                && keys == ["script", "user", "value"])
            || keys == ["script", "scriptproperties", "value"]
            || (host.acceptsNullOuterUser
                && keys == ["script", "scriptproperties", "user", "value"])
    }

    static func supports(_ wrapper: [String: Any], host: HostKind) -> Bool {
        let keys = wrapper.keys.sorted()
        guard supports(keys: keys, host: host) else { return false }
        if host == .soundVolume, keys.contains("user") {
            return namedSoundVolumeInput(wrapper) != nil
        }
        if host == .objectVisibility,
           let user = wrapper["user"].flatMap(SceneJSONValue.init(jsonObject:)),
           let value = wrapper["value"].flatMap(SceneJSONValue.init(jsonObject:)),
           value.boolValue != nil,
           conditionalReference(user) != nil {
            return true
        }
        return !keys.contains("user") || wrapper["user"] is NSNull
            || (host.acceptsStringOuterUser && wrapper["user"] is String)
    }

    /// This is structural admission only. The Sound Program proves the named
    /// Slider, resolved startup seed and admitted resource before owner creation.
    static func namedSoundVolumeInput(
        _ wrapper: [String: Any]
    ) -> NamedSoundVolumeInput? {
        namedSoundVolumeInput(
            source: wrapper["script"] as? String,
            wrapperKeys: wrapper.keys.sorted(),
            userPropertyKey: wrapper["user"] as? String,
            value: wrapper["value"].flatMap(SceneJSONValue.init(jsonObject:))
        )
    }

    static func namedSoundVolumeInput(
        source: String?, wrapperKeys: [String], userPropertyKey: String?,
        value: SceneJSONValue?
    ) -> NamedSoundVolumeInput? {
        guard wrapperKeys == ["script", "user", "value"]
                || wrapperKeys == ["script", "scriptproperties", "user", "value"],
              let source,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let userPropertyKey,
              SceneScriptUserPropertyInputContract.validName(userPropertyKey),
              userPropertyKey == userPropertyKey.trimmingCharacters(in: .whitespacesAndNewlines),
              !userPropertyKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let volumeSeed = value?.numberValue,
              volumeSeed.isFinite, (0 ... 1).contains(volumeSeed) else { return nil }
        return .init(
            source: source, userPropertyKey: userPropertyKey,
            volumeSeed: volumeSeed
        )
    }

    /// The same conditional reference shape is used by an outer visibility
    /// input and by a script property. Parsing it here keeps the format reader
    /// independent of the runtime property compiler.
    static func conditionalReference(
        _ value: SceneJSONValue
    ) -> (key: String, condition: SceneJSONValue)? {
        guard case let .object(reference) = value,
              reference.keys.sorted() == ["condition", "name"],
              case let .string(key)? = reference["name"],
              !key.isEmpty, key != "__proto__", key.utf8.count <= 256,
              let condition = reference["condition"] else { return nil }
        switch condition {
        case .bool, .string: return (key, condition)
        case let .number(number) where number.isFinite: return (key, condition)
        default: return nil
        }
    }
}
