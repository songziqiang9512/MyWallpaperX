import Foundation

/// Built-in material identities shared by source classification and feature
/// preparation. Asset paths and source-backed shaders never acquire this role.
enum SceneBuiltinShaderIdentity {
    static func isImage(_ identity: String) -> Bool {
        ["genericimage2", "genericimage4"].contains(identity.lowercased())
    }
}
