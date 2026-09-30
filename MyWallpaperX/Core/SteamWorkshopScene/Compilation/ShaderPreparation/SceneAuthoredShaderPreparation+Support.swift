import Foundation

extension SceneAuthoredShaderPreparation {
    nonisolated static func failure(
        phase: SceneAuthoredShaderPreparationFailure.Phase,
        code: SceneAuthoredShaderPreparationFailure.Code,
        details: [String] = []
    ) -> SceneAuthoredShaderPreparationFailure {
        .init(phase: phase, code: code, details: details)
    }

    /// Environment override root for the persistent preparation tier,
    /// mirroring the Material persistent tiers' isolation contract: when
    /// `MWX_SCENE_GENERIC_SHADER_CACHE` is set it is authoritative and the
    /// real user cache is never touched — an empty value disables the tier
    /// for the process. This lives here rather than in
    /// `ScenePersistentCacheSupport` because every harness subset that
    /// compiles the preparation family compiles this file; the Material
    /// support home is not part of that subset. Deliberately unlike the
    /// Material resolver it creates the scoped root on demand instead of
    /// requiring a pre-validated directory: the variable is operator-set
    /// (probe isolation), not an input from authored content.
    nonisolated static var persistentCacheEnvironmentOverridePresent: Bool {
        ProcessInfo.processInfo
            .environment["MWX_SCENE_GENERIC_SHADER_CACHE"] != nil
    }

    nonisolated static func persistentCacheEnvironmentOverrideURL(
        versionedName: String,
        createIfNeeded: Bool
    ) -> URL? {
        guard let raw = ProcessInfo.processInfo
            .environment["MWX_SCENE_GENERIC_SHADER_CACHE"],
              !raw.isEmpty else {
            return nil
        }
        let scoped = URL(
            fileURLWithPath: raw,
            isDirectory: true
        )
        .standardizedFileURL
        .appendingPathComponent(versionedName, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: scoped, withIntermediateDirectories: true
            )
        }
        return scoped
    }
}
