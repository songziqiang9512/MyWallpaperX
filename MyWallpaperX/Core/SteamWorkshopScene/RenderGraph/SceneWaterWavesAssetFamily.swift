import Foundation

/// A stock or relocated Water Waves asset family whose definition, material, and
/// shader paths share one namespace. Content and semantic fingerprints are still
/// validated independently by the planner and shader profile.
nonisolated struct SceneWaterWavesAssetFamily {
    let definitionPath: String
    let materialPath: String
    let materialPassID: String
    let shaderIdentity: String
    let vertexPath: String
    let fragmentPath: String
    let dependencies: [String]

    init?(definitionPath rawPath: String) {
        let path = Self.normalized(rawPath)
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components.joined(separator: "/") == path,
              components.first == "effects",
              components[components.count - 2] == "waterwaves",
              components.last == "effect.json",
              components.dropFirst().dropLast(2).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            return nil
        }
        let namespace = components.dropFirst().dropLast(2).joined(separator: "/")
        let prefix = namespace.isEmpty ? "" : "\(namespace)/"
        let materialPath = "materials/\(prefix)effects/waterwaves.json"
        let shaderIdentity = "\(prefix)effects/waterwaves"
        self.definitionPath = path
        self.materialPath = materialPath
        materialPassID = "\(materialPath)#0"
        self.shaderIdentity = shaderIdentity
        vertexPath = "shaders/\(shaderIdentity).vert"
        fragmentPath = "shaders/\(shaderIdentity).frag"
        dependencies = [materialPath, fragmentPath, vertexPath]
    }

    /// Sorted material JSON with only the pass-local shader identity replaced by `$shader`.
    /// Unknown keys and every other authored value remain part of the digest.
    static let materialSemanticSHA256 =
        "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121"

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
