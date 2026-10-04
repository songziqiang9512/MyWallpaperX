import Foundation

/// The two author versions share geometry, but retain separate field/flag admission.
nonisolated struct SceneParticleVortex: Equatable, Sendable {
    enum Version: String, Sendable {
        case classic = "vortex"
        case v2 = "vortex_v2"
    }

    let version: Version
    let axis: SceneParticleNumericValue?
    let distanceInner: Double?
    let distanceOuter: Double?
    let speedInner: Double?
    let speedOuter: Double?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]
}

nonisolated struct SceneParticleVortexPlan: Equatable, Sendable {
    let axis: SIMD3<Double>
    let distanceInner: Double
    let distanceOuter: Double
    let speedInner: Double
    let speedOuter: Double
    let maintainsRadius: Bool
    let usesInfiniteAxis: Bool
    let usesControlPointOrigin: Bool
}

nonisolated extension SceneParticleOperator {
    var vortexPlan: SceneParticleVortexPlan? {
        guard case let .vortex(value) = kind,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              (value.version == .classic
                ? rawFlags == 0 || rawFlags == 1
                : rawFlags == 0 || rawFlags == 2),
              blendInStart == nil, blendInEnd == nil,
              blendOutStart == nil, blendOutEnd == nil,
              controlPoint == nil || (value.version == .v2 && controlPoint == 0),
              value.version == .classic || value.axis == nil
                || value.axis == .vector([0, 0, 1]),
              value.version == .classic || !audioResponse.isEnabled,
              let distanceInner = value.distanceInner,
              let distanceOuter = value.distanceOuter,
              let speedInner = value.speedInner,
              let speedOuter = value.speedOuter,
              distanceInner.isFinite, distanceOuter.isFinite,
              speedInner.isFinite, speedOuter.isFinite,
              distanceInner >= 0, distanceOuter >= distanceInner,
              distanceOuter <= 1_000_000,
              abs(speedInner) <= 1_000_000, abs(speedOuter) <= 1_000_000,
              distanceOuter > distanceInner || speedInner == speedOuter,
              let axis = Self.vortexAxis(value.axis) else {
            return nil
        }
        // Bounded clean-room response from paired particle-clock observations.
        // This is a project approximation, not an official numerical formula.
        let accelerationScale = value.version == .v2 ? 0.72 : 1
        return .init(
            axis: axis,
            distanceInner: distanceInner,
            distanceOuter: distanceOuter,
            speedInner: speedInner * accelerationScale,
            speedOuter: speedOuter * accelerationScale,
            maintainsRadius: value.version == .v2 && rawFlags == 2,
            usesInfiniteAxis: value.version == .classic && rawFlags == 1,
            usesControlPointOrigin: value.version == .v2
        )
    }

    private static func vortexAxis(
        _ value: SceneParticleNumericValue?
    ) -> SIMD3<Double>? {
        let axis: SIMD3<Double>
        switch value {
        case let .vector(values) where values.count == 3:
            axis = SIMD3(values[0], values[1], values[2])
        case nil:
            axis = SIMD3(0, 0, 1)
        default:
            return nil
        }
        // Classic authoring accepts an exact zero direction as positive Z.
        // Keep nonzero admission and normalization in the existing profile.
        if axis == .zero { return SIMD3(0, 0, 1) }
        let length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        guard length.isFinite, length > 1e-12 else { return nil }
        return axis / length
    }
}
