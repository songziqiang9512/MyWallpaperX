import Foundation

nonisolated struct SceneEffectTextureInput: Codable, Hashable {
    enum Kind: String, Codable {
        case path
        case system
        case property
        case userShortcut
        case unknown
    }

    let kind: Kind
    let value: String

    /// Project declarations disambiguate bare keys before typed preparation;
    /// path syntax, RT vocabulary and explicit objects retain their identity.
    nonisolated static func parse(
        _ raw: Any,
        declaredTexturePropertyKeys: Set<String> = []
    ) -> SceneEffectTextureInput? {
        if raw is NSNull { return nil }
        if let string = raw as? String {
            let value = normalized(string)
            guard !value.isEmpty else { return nil }
            let hasPathSyntax = value.contains("/") || value.contains(".")
            let declaredProperty = declaredTexturePropertyKeys.contains(value)
                && !hasPathSyntax
                && !value.hasPrefix(SceneRenderTargetVocabulary.internalTargetPrefix)
                && SceneRenderTargetVocabulary.dispatch(authoredName: value) == .unadmitted(value)
            let isPath = !declaredProperty && (hasPathSyntax || value.hasPrefix("_"))
            return SceneEffectTextureInput(kind: isPath ? .path : .property, value: value)
        }
        guard let dictionary = raw as? [String: Any] else {
            return SceneEffectTextureInput(kind: .unknown, value: String(describing: raw))
        }
        let type = (dictionary["type"] as? String)?.localizedLowercase
        let name = (dictionary["name"] as? String).map(normalized) ?? ""
        if type == "usershortcut" {
            guard !name.isEmpty, Set(dictionary.keys) == Set(["type", "name"]) else {
                return SceneEffectTextureInput(kind: .unknown, value: name)
            }
            return SceneEffectTextureInput(kind: .userShortcut, value: name)
        }
        if type == "system", !name.isEmpty {
            guard Set(dictionary.keys) == Set(["type", "name"]) else {
                return SceneEffectTextureInput(kind: .unknown, value: name)
            }
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
