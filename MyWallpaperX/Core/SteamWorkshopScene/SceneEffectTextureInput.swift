import Foundation

nonisolated struct SceneEffectTextureInput: Codable, Hashable {
    enum Kind: String, Codable {
        case path
        case system
        case property
        case unknown
    }

    let kind: Kind
    let value: String

    nonisolated static func parse(_ raw: Any) -> SceneEffectTextureInput? {
        if raw is NSNull { return nil }
        if let string = raw as? String {
            let value = normalized(string)
            guard !value.isEmpty else { return nil }
            let isPath = value.contains("/") || value.contains(".") || value.hasPrefix("_")
            return SceneEffectTextureInput(kind: isPath ? .path : .property, value: value)
        }
        guard let dictionary = raw as? [String: Any] else {
            return SceneEffectTextureInput(kind: .unknown, value: String(describing: raw))
        }
        let type = (dictionary["type"] as? String)?.localizedLowercase
        let name = (dictionary["name"] as? String).map(normalized) ?? ""
        if type == "system", !name.isEmpty {
            return SceneEffectTextureInput(kind: .system, value: name)
        }
        if let user = dictionary["user"] as? String {
            return SceneEffectTextureInput(kind: .property, value: normalized(user))
        }
        return SceneEffectTextureInput(
            kind: .unknown,
            value: name.isEmpty ? String(describing: dictionary) : name
        )
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
    }
}
