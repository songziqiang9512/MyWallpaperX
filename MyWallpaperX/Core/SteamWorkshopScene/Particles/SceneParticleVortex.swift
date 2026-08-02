import Foundation

/// Classic `vortex` wire. The newer ring-shaped `vortex_v2` remains a distinct,
/// unsupported operator because it has different fields and control-point semantics.
nonisolated struct SceneParticleVortex: Equatable, Sendable {
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
    let usesInfiniteAxis: Bool
}

nonisolated extension SceneParticleOperator {
    var vortexPlan: SceneParticleVortexPlan? {
        guard case let .vortex(value) = kind,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              rawFlags == 0 || rawFlags == 1,
              blendInStart == nil, blendInEnd == nil,
              blendOutStart == nil, blendOutEnd == nil,
              controlPoint == nil,
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
        return .init(
            axis: axis,
            distanceInner: distanceInner,
            distanceOuter: distanceOuter,
            speedInner: speedInner,
            speedOuter: speedOuter,
            usesInfiniteAxis: rawFlags == 1
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
        let length = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        guard length.isFinite, length > 1e-12 else { return nil }
        return axis / length
    }
}
