import Foundation

nonisolated struct SceneParticleBoidsPlan: Equatable, Sendable {
    let neighborThreshold: Double
    let alignmentFactor: Double
    let cohesionFactor: Double
}

nonisolated extension SceneParticleDefinition {
    func boidsPlan(for value: SceneParticleOperator) -> SceneParticleBoidsPlan? {
        guard case let .boids(configuration) = value.kind,
              value.rawFlags == 0,
              !value.audioResponse.isEnabled,
              !configuration.hasMalformedFields,
              configuration.unsupportedFieldNames.isEmpty,
              configuration.separationFactor == 0,
              let neighborThreshold = configuration.neighborThreshold,
              neighborThreshold.isFinite, (0 ... 1_000_000).contains(neighborThreshold),
              neighborThreshold > 0,
              let alignmentFactor = configuration.alignmentFactor,
              alignmentFactor.isFinite, (0 ... 10_000).contains(alignmentFactor),
              let cohesionFactor = configuration.cohesionFactor,
              cohesionFactor.isFinite, (0 ... 10_000).contains(cohesionFactor),
              let maximumCount, (0 ... 64).contains(maximumCount)
        else { return nil }
        return .init(
            neighborThreshold: neighborThreshold,
            alignmentFactor: alignmentFactor,
            cohesionFactor: cohesionFactor
        )
    }
}
