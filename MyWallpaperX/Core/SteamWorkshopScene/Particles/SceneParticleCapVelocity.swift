import Foundation

nonisolated struct SceneParticleCapVelocityPlan: Equatable, Sendable {
    let maximumSpeed: Double
}

nonisolated extension SceneParticleOperator {
    var capVelocityPlan: SceneParticleCapVelocityPlan? {
        guard case let .capVelocity(value) = kind,
              !value.hasMalformedFields,
              value.unsupportedFieldNames.isEmpty,
              rawFlags == 0,
              !audioResponse.isEnabled,
              let maximumSpeed = value.maximumSpeed,
              maximumSpeed.isFinite,
              maximumSpeed >= 0,
              maximumSpeed <= 1_000_000,
              Self.validBlendPair(start: blendInStart, end: blendInEnd),
              Self.validBlendPair(start: blendOutStart, end: blendOutEnd),
              Self.validBlendOrder(
                blendInEnd: blendInEnd,
                blendOutStart: blendOutStart
              ) else {
            return nil
        }
        return .init(maximumSpeed: maximumSpeed)
    }

    private static func validBlendPair(start: Double?, end: Double?) -> Bool {
        guard start != nil || end != nil else { return true }
        guard let start, let end,
              start.isFinite, end.isFinite,
              (0 ... 1).contains(start), (0 ... 1).contains(end) else {
            return false
        }
        return start <= end
    }

    private static func validBlendOrder(
        blendInEnd: Double?,
        blendOutStart: Double?
    ) -> Bool {
        guard let blendInEnd, let blendOutStart else { return true }
        return blendInEnd <= blendOutStart
    }
}
