import Foundation

/// Built-in material identities shared by source classification and feature
/// preparation. Asset paths and source-backed shaders never acquire this role.
nonisolated enum SceneBuiltinShaderIdentity {
    /// This role also requires an unoverridden stock source graph at its caller.
    static func isNeutralSolid(_ identity: String) -> Bool {
        identity.lowercased() == "flat"
    }

    static func isImage(_ identity: String) -> Bool {
        ["genericimage2", "genericimage4"].contains(identity.lowercased())
    }
}
