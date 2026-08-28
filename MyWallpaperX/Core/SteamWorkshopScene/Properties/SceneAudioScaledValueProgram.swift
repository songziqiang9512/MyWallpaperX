import Foundation

nonisolated struct SceneAudioScaledValueBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let frequency: Int
    let smoothing: Double
    let minimumScale: Double
    let maximumScale: Double
}

nonisolated struct SceneAudioScaledValueProgram: Equatable, Sendable {
    let bindings: [SceneAudioScaledValueBinding]
    let rejectedParticleLayerIDs: [Int]
    let rejectedScaleLayerIDs: [Int]

    static let empty = Self(
        bindings: [], rejectedParticleLayerIDs: [], rejectedScaleLayerIDs: []
    )

    nonisolated var definitions: [SceneDynamicTargetDefinition] {
        bindings.map(\.definition)
    }

    nonisolated var admittedParticleLayerIDs: Set<Int> {
        Set(bindings.compactMap { binding in
            guard case let .particle(layerID, .rate) = binding.definition.target else {
                return nil
            }
            return layerID
        })
    }

    nonisolated var admittedScaleLayerIDs: Set<Int> {
        Set(bindings.compactMap { binding in
            guard case let .layer(layerID, .scale) = binding.definition.target else {
                return nil
            }
            return layerID
        })
    }

    nonisolated func excluding(
        _ targets: Set<SceneDynamicTarget>
    ) -> SceneAudioScaledValueProgram {
        .init(
            bindings: bindings.filter { !targets.contains($0.definition.target) },
            rejectedParticleLayerIDs: rejectedParticleLayerIDs,
            rejectedScaleLayerIDs: rejectedScaleLayerIDs
        )
    }
}
