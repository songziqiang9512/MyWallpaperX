import Foundation

/// Shared model alias identity. This preserves the authored-model matching
/// contract; safe VFS path admission and resource resolution remain separate.
nonisolated struct SceneModelResourceIdentity: Hashable, Sendable {
    let value: String

    init(_ path: String) {
        value = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
