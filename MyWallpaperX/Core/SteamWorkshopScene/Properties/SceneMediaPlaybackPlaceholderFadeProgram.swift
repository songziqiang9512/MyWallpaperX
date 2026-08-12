import Foundation

/// Data-only form of the stock scalar placeholder fade. It is not a generic
/// SceneScript program and carries no JavaScript execution authority.
nonisolated struct SceneMediaPlaybackPlaceholderFadeProgram: Equatable, Sendable {
    let bindings: [SceneMediaPlaybackPlaceholderFadeBinding]

    nonisolated static let empty = SceneMediaPlaybackPlaceholderFadeProgram(bindings: [])

    private nonisolated init(bindings: [SceneMediaPlaybackPlaceholderFadeBinding]) {
        self.bindings = bindings
    }

    nonisolated static func validated(
        bindings: [SceneMediaPlaybackPlaceholderFadeBinding]
    ) -> Self? {
        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count else { return nil }
        return Self(bindings: bindings)
    }
}

nonisolated struct SceneMediaPlaybackPlaceholderFadeBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let plan: SceneMediaPlaybackPlaceholderFadePlan
}

/// Exact constants and asymmetric post-update guards authored by the admitted
/// positive-polarity stock profile. The counter is intentionally not UNorm-clamped.
nonisolated struct SceneMediaPlaybackPlaceholderFadePlan: Equatable, Sendable {
    let initialCounter: Double
    let frameTimeScale: Double
    let outputScale: Double
    let stoppedLowerReset: Double
    let activeUpperReset: Double

    private nonisolated init(
        initialCounter: Double,
        frameTimeScale: Double,
        outputScale: Double,
        stoppedLowerReset: Double,
        activeUpperReset: Double
    ) {
        self.initialCounter = initialCounter
        self.frameTimeScale = frameTimeScale
        self.outputScale = outputScale
        self.stoppedLowerReset = stoppedLowerReset
        self.activeUpperReset = activeUpperReset
    }

    nonisolated static let positivePlaceholder = Self(
        initialCounter: 0,
        frameTimeScale: 2,
        outputScale: 1,
        stoppedLowerReset: 0,
        activeUpperReset: 1
    )
}
