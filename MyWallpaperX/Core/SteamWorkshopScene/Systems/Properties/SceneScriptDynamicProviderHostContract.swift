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
        case particleRate
        case passConstant

        var acceptsNullOuterUser: Bool {
            switch self {
            case .objectVector, .objectText, .particleRate, .passConstant:
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
            || (host.acceptsStringOuterUser && wrapper["user"] is String)
    }
}
