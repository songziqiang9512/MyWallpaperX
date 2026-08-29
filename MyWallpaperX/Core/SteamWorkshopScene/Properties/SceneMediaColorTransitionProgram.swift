import Foundation

/// Data-only form of one bounded media-thumbnail color transition profile.
/// It carries no JavaScript execution authority.
nonisolated struct SceneMediaColorTransitionProgram: Equatable, Sendable {
    let bindings: [SceneMediaColorTransitionBinding]

    nonisolated static let empty = SceneMediaColorTransitionProgram(bindings: [])

    nonisolated var targets: Set<SceneDynamicTarget> {
        Set(bindings.map(\.definition.target))
    }

    private nonisolated init(bindings: [SceneMediaColorTransitionBinding]) {
        self.bindings = bindings
    }

    nonisolated static func validated(
        bindings: [SceneMediaColorTransitionBinding]
    ) -> Self? {
        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count else { return nil }
        return Self(bindings: bindings)
    }
}

nonisolated struct SceneMediaColorTransitionBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let plan: SceneMediaColorTransitionPlan
}

/// Exact `MediaThumbnailEvent` palette member consumed by one admitted script.
/// Other event colors remain unsupported until their own bounded profiles exist.
nonisolated enum SceneMediaThumbnailColorChannel: Equatable, Sendable {
    case primary
    case secondary
}

/// Exact author inputs retained by the admitted transition profile.
nonisolated struct SceneMediaColorTransitionPlan: Equatable, Sendable {
    let userPropertyKey: String
    let authoredTopColor: SIMD3<Double>
    let duration: TimeInterval
    let thumbnailColorChannel: SceneMediaThumbnailColorChannel
}
