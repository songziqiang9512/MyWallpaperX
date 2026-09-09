import Foundation

extension SceneResolvedMaterialGenericShaderArtifactCache {
    static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .prefix(96)
            .lowercased()
    }

}
