import Foundation

struct SceneUtilityLayer: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case composition
        case project
        case fullscreen
    }

    let kind: Kind
    let copyBackground: Bool
    let passthrough: Bool

    nonisolated static func parse(
        imagePath: String?,
        object: [String: Any]
    ) -> SceneUtilityLayer? {
        guard let kind = kind(for: imagePath) else { return nil }
        let config = object["config"] as? [String: Any]
        return SceneUtilityLayer(
            kind: kind,
            copyBackground: boolValue(object["copybackground"]) ?? false,
            passthrough: boolValue(config?["passthrough"]) ?? false
        )
    }

    nonisolated static func kind(for imagePath: String?) -> Kind? {
        let normalized = imagePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
        switch normalized {
        case "models/util/composelayer.json": return .composition
        case "models/util/projectlayer.json": return .project
        case "models/util/fullscreenlayer.json": return .fullscreen
        default: return nil
        }
    }

    nonisolated private static func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let wrapped = raw as? [String: Any] {
            return wrapped["value"] as? Bool
        }
        return nil
    }
}
