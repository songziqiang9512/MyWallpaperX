import Foundation

nonisolated enum SceneParticleControlPointForceAdmission {
    case supported(SceneParticleControlPointForcePlan)
    case unsupported
}

nonisolated struct SceneParticleControlPointForcePlan {
    let controlPoint: Int
    let origin: SIMD3<Double>
    let acceleration: Double
    let maximumDistance: Double
}

nonisolated extension SceneParticleControlPoint {
    var hasBoundedPointerInput: Bool {
        guard rawFlags == 1, let id, (1 ... 7).contains(id), angles == nil,
              parentControlPoint == nil else { return false }
        return hasExactZeroOffset
    }

    func hasBoundedStaticInput(identity: Int) -> Bool {
        guard id == identity, rawFlags == 0, angles == nil,
              parentControlPoint == nil else { return false }
        let value: SIMD3<Double>
        switch offset {
        case nil: value = .zero
        case let .vector(values) where values.count == 3:
            value = SIMD3(values[0], values[1], values[2])
        default: return false
        }
        return value.x.isFinite && value.y.isFinite && value.z.isFinite
            && abs(value.x) <= 1_000_000 && abs(value.y) <= 1_000_000
            && abs(value.z) <= 1_000_000
    }

    private var hasExactZeroOffset: Bool {
        switch offset {
        case nil: return true
        case let .vector(values): return values.count == 3 && values.allSatisfy { $0 == 0 }
        default: return false
        }
    }
}

nonisolated extension SceneParticleOperator {
    var controlPointForceAdmission: SceneParticleControlPointForceAdmission {
        guard kind == .controlPointAttract, rawFlags == 0,
              blendInStart == nil, blendInEnd == nil,
              blendOutStart == nil, blendOutEnd == nil,
              !audioResponse.isEnabled,
              let acceleration = scale?.scalarValue, acceleration.isFinite,
              abs(acceleration) <= 1_000_000,
              let maximumDistance = threshold, maximumDistance.isFinite,
              (0 ... 1_000_000).contains(maximumDistance),
              let origin = Self.boundedVector(origin),
              (0 ... 7).contains(controlPoint ?? 0) else { return .unsupported }
        return .supported(.init(
            controlPoint: controlPoint ?? 0,
            origin: origin,
            acceleration: acceleration,
            maximumDistance: maximumDistance
        ))
    }

    private static func boundedVector(
        _ value: SceneParticleNumericValue?
    ) -> SIMD3<Double>? {
        let result: SIMD3<Double>
        switch value {
        case let .vector(values) where values.count == 3:
            result = SIMD3(values[0], values[1], values[2])
        case .scalar: return nil
        case .vector: return nil
        case nil: result = .zero
        }
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite,
              abs(result.x) <= 1_000_000, abs(result.y) <= 1_000_000,
              abs(result.z) <= 1_000_000 else { return nil }
        return result
    }
}

nonisolated extension SceneParticleDefinition {
    func supportsBoundedControlPointForce(
        _ value: SceneParticleOperator
    ) -> Bool {
        guard !flags.isWorldSpace, !flags.usesPerspective,
              !operators.contains(where: \.isWorldSpaceMovement),
              case let .supported(plan) = value.controlPointForceAdmission,
              SceneParticleSimulationMath.supportsControlPointSource(
                  plan.controlPoint, in: self
              ) else { return false }
        guard let point = controlPoints.first(where: { $0.id == plan.controlPoint }) else {
            return true
        }
        return point.hasBoundedPointerInput
            || point.hasBoundedStaticInput(identity: plan.controlPoint)
    }

    func pointerControlPointValues(
        at position: SIMD3<Double>?
    ) -> [Int: SIMD3<Double>] {
        let identities = Set(operators.compactMap { value -> Int? in
            guard supportsBoundedControlPointForce(value),
                  case let .supported(plan) = value.controlPointForceAdmission,
                  controlPoints.contains(where: {
                      $0.id == plan.controlPoint && $0.hasBoundedPointerInput
                  }) else { return nil }
            return plan.controlPoint
        })
        guard !identities.isEmpty else { return [:] }
        let value: SIMD3<Double>
        if let position, position.x.isFinite, position.y.isFinite,
           position.z.isFinite {
            value = position
        } else {
            value = .init(repeating: .nan)
        }
        return Dictionary(uniqueKeysWithValues: identities.map { ($0, value) })
    }
}
