import Foundation

/// Exact outer-wrapper shapes shared by property routing and the SceneScript
/// scalar/vector candidate catalogs. Boolean visibility may receive an outer
/// user property through the existing lower-priority typed input channel.
nonisolated enum SceneScriptDynamicProviderHostContract {
    enum HostKind: Equatable, Sendable {
        case objectScalar
        case objectVector
        case objectVisibility
        case particleRate
        case passConstant

        var acceptsNullOuterUser: Bool {
            switch self {
            case .objectVector, .particleRate, .passConstant:
                return true
            case .objectScalar, .objectVisibility:
                return false
            }
        }
    }

    static func supports(keys: [String], host: HostKind) -> Bool {
        (host == .objectVisibility
            && (keys == ["script", "user", "value"]
                || keys == ["script", "scriptproperties", "user", "value"]))
            || (host == .particleRate && keys == ["script", "value"])
            || (host == .particleRate
                && keys == ["script", "user", "value"])
            || keys == ["script", "scriptproperties", "value"]
            || (host.acceptsNullOuterUser
                && keys == ["script", "scriptproperties", "user", "value"])
    }

    static func supports(_ wrapper: [String: Any], host: HostKind) -> Bool {
        let keys = wrapper.keys.sorted()
        guard supports(keys: keys, host: host) else { return false }
        return !keys.contains("user") || wrapper["user"] is NSNull
            || (host == .objectVisibility && wrapper["user"] is String)
    }
}
