import Foundation

nonisolated enum SceneParticleInitializerKind: Equatable, Sendable {
    case lifetime
    case size
    case velocity
    case color
    case colorList
    case alpha
    case rotation
    case angularVelocity
    case turbulentVelocity
    case positionOffset
    case unsupported(String)
}

nonisolated struct SceneParticleTurbulentVelocity: Equatable, Sendable {
    let forward: SceneParticleNumericValue?
    let right: SceneParticleNumericValue?
    let up: SceneParticleNumericValue?
    let offset: Double?
    let phaseMinimum: Double?
    let phaseMaximum: Double?
    let scale: Double?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let timeScale: Double?
    let audioResponse: SceneParticleAudioResponse
}

nonisolated struct SceneParticlePositionOffset: Equatable, Sendable {
    let directions: SceneParticleNumericValue?
    let distance: Double?
    let octaves: Int?
    let scale: Double?
    let timeScale: Double?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]
}

nonisolated struct SceneParticlePositionOffsetPlan: Equatable, Sendable {
    let directions: SIMD3<Double>
    let distance: Double
    let octaves: Int
    let scale: Double
    let timeScale: Double
}

nonisolated struct SceneParticleInitializer: Equatable, Sendable {
    let id: Int?
    let kind: SceneParticleInitializerKind
    let minimum: SceneParticleNumericValue?
    let maximum: SceneParticleNumericValue?
    let exponent: Double?
    let turbulentVelocity: SceneParticleTurbulentVelocity?
    let positionOffset: SceneParticlePositionOffset?
    let colors: [SceneParticleNumericValue]?
    let hasMalformedColorList: Bool
}

extension SceneParticleInitializer {
    nonisolated var boundedPositionOffset: SceneParticlePositionOffsetPlan? {
        guard case .positionOffset = kind, let value = positionOffset,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              let distance = value.distance, distance.isFinite,
              (0 ... 1_000_000).contains(distance) else { return nil }

        let directions: SIMD3<Double>
        switch value.directions {
        case let .scalar(number):
            directions = SIMD3(repeating: number)
        case let .vector(values) where values.count == 3:
            directions = SIMD3(values[0], values[1], values[2])
        case .vector:
            return nil
        case nil:
            directions = SIMD3(1, 1, 0)
        }
        guard directions.x.isFinite, directions.y.isFinite, directions.z.isFinite,
              abs(directions.x) <= 1, abs(directions.y) <= 1,
              abs(directions.z) <= 1 else { return nil }

        let octaves = value.octaves ?? 3
        let scale = value.scale ?? 1
        let timeScale = value.timeScale ?? 1
        guard (1 ... 8).contains(octaves), scale.isFinite,
              (0 ... 1_000_000).contains(scale), timeScale.isFinite,
              abs(timeScale) <= 1_000_000 else { return nil }
        return .init(
            directions: directions, distance: distance, octaves: octaves,
            scale: scale, timeScale: timeScale
        )
    }
}
