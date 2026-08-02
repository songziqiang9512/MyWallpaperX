import Foundation

nonisolated extension SceneParticleSimulationMath {
    static func supportsControlPointSource(
        _ source: Int,
        in definition: SceneParticleDefinition
    ) -> Bool {
        guard (0 ... 7).contains(source) else { return false }
        var identities: Set<Int> = []
        for point in definition.controlPoints {
            guard let id = point.id, (0 ... 7).contains(id),
                  identities.insert(id).inserted else { return false }
        }
        return true
    }

    static func rotateXYZ(
        _ value: SIMD3<Double>, by angles: SIMD3<Double>
    ) -> SIMD3<Double> {
        // Project-owned bounded convention: authored radians apply X, then Y, then Z.
        // This does not assert numerical parity with the official client.
        let sine = SIMD3(sin(angles.x), sin(angles.y), sin(angles.z))
        let cosine = SIMD3(cos(angles.x), cos(angles.y), cos(angles.z))
        let aroundX = SIMD3(
            value.x,
            value.y * cosine.x - value.z * sine.x,
            value.y * sine.x + value.z * cosine.x
        )
        let aroundY = SIMD3(
            aroundX.x * cosine.y + aroundX.z * sine.y,
            aroundX.y,
            -aroundX.x * sine.y + aroundX.z * cosine.y
        )
        return SIMD3(
            aroundY.x * cosine.z - aroundY.y * sine.z,
            aroundY.x * sine.z + aroundY.y * cosine.z,
            aroundY.z
        )
    }
}

nonisolated struct SceneParticleEmitterControlPointFrame {
    let origin: SIMD3<Double>
    let angles: SIMD3<Double>

    func position(for relative: SIMD3<Double>) -> SIMD3<Double> {
        origin + SceneParticleSimulationMath.rotateXYZ(relative, by: angles)
    }

    func direction(for value: SIMD3<Double>) -> SIMD3<Double> {
        SceneParticleSimulationMath.rotateXYZ(value, by: angles)
    }
}

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

    func boundedEmitterAngle(identity: Int) -> SIMD3<Double>? {
        guard id == identity, !hasMalformedFields, rawFlags == 0 || rawFlags == 16,
              parentControlPoint == nil else { return nil }
        return Self.boundedVector(angles, fallback: .zero)?.normalizedAngles
    }

    var boundedEmitterOffset: SIMD3<Double>? {
        Self.boundedVector(offset, fallback: .zero)
    }

    private static func boundedVector(
        _ value: SceneParticleNumericValue?, fallback: SIMD3<Double>
    ) -> SIMD3<Double>? {
        let result: SIMD3<Double>
        switch value {
        case let .vector(values) where values.count == 3:
            result = SIMD3(values[0], values[1], values[2])
        case nil:
            result = fallback
        default:
            return nil
        }
        return result.isBounded ? result : nil
    }

    private var hasExactZeroOffset: Bool {
        switch offset {
        case nil: return true
        case let .vector(values): return values.count == 3 && values.allSatisfy { $0 == 0 }
        default: return false
        }
    }
}

private nonisolated extension SIMD3 where Scalar == Double {
    var isBounded: Bool {
        x.isFinite && y.isFinite && z.isFinite
            && abs(x) <= 1_000_000 && abs(y) <= 1_000_000 && abs(z) <= 1_000_000
    }

    var normalizedAngles: Self {
        let turn = 2 * Double.pi
        return .init(
            x.remainder(dividingBy: turn),
            y.remainder(dividingBy: turn),
            z.remainder(dividingBy: turn)
        )
    }
}

private nonisolated extension SceneParticleBoundValue {
    var boundedStaticVector: SIMD3<Double>? {
        guard userPropertyKey == nil, !hasScript, !hasAnimation,
              case let .vector(values) = value, values.count == 3 else { return nil }
        let result = SIMD3(values[0], values[1], values[2])
        return result.isBounded ? result : nil
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
    func hasAuthoredEmitterAngles(
        _ emitter: SceneParticleEmitter,
        instanceOverride: SceneParticleInstanceOverride?
    ) -> Bool {
        guard let source = emitter.controlPoint else { return false }
        return controlPoints.first(where: { $0.id == source })?.hasAuthoredAngles == true
            || instanceOverride?.controlPointAngles[source] != nil
    }

    func emitterControlPointFrame(
        for emitter: SceneParticleEmitter,
        instanceOverride: SceneParticleInstanceOverride?,
        dynamicControlPoints: [Int: SIMD3<Double>]
    ) -> SceneParticleEmitterControlPointFrame? {
        let localOrigin = SceneParticleSimulationMath.vector(emitter.origin, fallback: .zero)
        guard let source = emitter.controlPoint else {
            return .init(origin: localOrigin, angles: .zero)
        }
        guard SceneParticleSimulationMath.supportsControlPointSource(source, in: self) else {
            return nil
        }
        let point = controlPoints.first(where: { $0.id == source })
        let angleOverride = instanceOverride?.controlPointAngles[source]
        let usesAngles = point?.hasAuthoredAngles == true || angleOverride != nil
        var translation = SceneParticleSimulationMath.vector(point?.offset, fallback: .zero)
        var angles = SIMD3<Double>.zero
        if usesAngles {
            guard emitter.kind == .sphereRandom || emitter.kind == .boxRandom,
                  localOrigin.isBounded else { return nil }
            if let point {
                guard let offset = point.boundedEmitterOffset,
                      let defaultAngles = point.boundedEmitterAngle(identity: source)
                else { return nil }
                translation = offset
                angles = defaultAngles
            }
            if let angleOverride {
                guard let value = angleOverride.boundedStaticVector else { return nil }
                angles = value.normalizedAngles
            }
        }
        if let dynamic = dynamicControlPoints[source] {
            guard dynamic.isBounded else { return nil }
            translation += dynamic
        } else if let position = instanceOverride?.controlPoints[source] {
            if usesAngles {
                guard let value = position.boundedStaticVector else { return nil }
                translation += value
            } else {
                translation += SceneParticleSimulationMath.vector(position.value, fallback: .zero)
            }
        }
        let rotatedOrigin = SceneParticleSimulationMath.rotateXYZ(localOrigin, by: angles)
        return .init(origin: translation + rotatedOrigin, angles: angles)
    }

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
