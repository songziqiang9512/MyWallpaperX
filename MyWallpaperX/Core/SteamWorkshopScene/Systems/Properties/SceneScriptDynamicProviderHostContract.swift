import Foundation

/// Exact outer-wrapper shapes shared by property routing and the SceneScript
/// scalar/vector/text candidate catalogs. Boolean visibility may receive an
/// outer user property through the existing lower-priority typed input channel;
/// text content is the only other host whose outer `user` key may name a real
/// user property alongside the script's own declared script properties.
nonisolated enum SceneScriptDynamicProviderHostContract {
    enum HostKind: Equatable, Sendable {
        case objectScalar
        case objectVector
        case objectVisibility
        case objectText
        case particleScalar
        case passConstant

        var acceptsNullOuterUser: Bool {
            switch self {
            case .objectVector, .objectText, .particleScalar, .passConstant:
                return true
            case .objectScalar, .objectVisibility:
                return false
            }
        }

        /// Hosts whose outer `user` key may carry a real user property key
        /// instead of being absent or null.
        var acceptsStringOuterUser: Bool {
            self == .objectVisibility || self == .objectText
        }
    }

    static func supports(keys: [String], host: HostKind) -> Bool {
        (host == .objectVisibility
            && (keys == ["script", "user", "value"]
                || keys == ["script", "scriptproperties", "user", "value"]))
            || (host == .objectText
                && (keys == ["script", "value"]
                    || keys == ["script", "user", "value"]))
            || (host == .particleScalar && keys == ["script", "value"])
            || (host == .particleScalar
                && keys == ["script", "user", "value"])
            || keys == ["script", "scriptproperties", "value"]
            || (host.acceptsNullOuterUser
                && keys == ["script", "scriptproperties", "user", "value"])
    }

    static func supports(_ wrapper: [String: Any], host: HostKind) -> Bool {
        let keys = wrapper.keys.sorted()
        guard supports(keys: keys, host: host) else { return false }
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
