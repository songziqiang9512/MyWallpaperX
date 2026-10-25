import Foundation

nonisolated struct SceneParticlePositionAroundControlPoint: Equatable, Sendable {
    let bounds: SceneParticleNumericValue?
    let count: Double?
    let limitBehavior: String?
    let speedMinimum: SceneParticleNumericValue?
    let speedMaximum: SceneParticleNumericValue?
    let axis: SceneParticleNumericValue?
    let controlPoint: Int?
    let rawFlags: Int?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        bounds = SceneParticleDefinitionParser.numericValue(root["bounds"])
        count = SceneParticleDefinitionParser.number(root["count"])
        if let rawBehavior = root["limitbehavior"] as? String {
            let trimmed = rawBehavior.trimmingCharacters(in: .whitespacesAndNewlines)
            limitBehavior = trimmed.isEmpty ? nil : trimmed.lowercased()
        } else {
            limitBehavior = nil
        }
        speedMinimum = SceneParticleDefinitionParser.numericValue(root["speedmin"])
        speedMaximum = SceneParticleDefinitionParser.numericValue(root["speedmax"])
        axis = SceneParticleDefinitionParser.numericValue(root["axis"])
        controlPoint = SceneParticleDefinitionParser.integer(root["controlpoint"])
        rawFlags = SceneParticleDefinitionParser.integer(root["flags"])

        let supported = Set([
            "id", "name", "bounds", "count", "limitbehavior", "speedmin",
            "speedmax", "axis", "controlpoint", "flags",
        ])
        unsupportedFieldNames = root.keys.filter { !supported.contains($0) }.sorted()
        let parsed: [String: Any?] = [
            "bounds": bounds, "count": count, "limitbehavior": limitBehavior,
            "speedmin": speedMinimum, "speedmax": speedMaximum, "axis": axis,
            "controlpoint": controlPoint, "flags": rawFlags,
        ]
        let defaultedFields = ["bounds", "limitbehavior", "speedmin", "speedmax"]
        hasMalformedFields = parsed.contains { key, value in
            root[key] != nil && value == nil
                && (defaultedFields.contains(key) || !(root[key] is NSNull))
        }
    }
}

nonisolated struct SceneParticlePositionAroundControlPointPlan: Equatable, Sendable {
    let bounds: ClosedRange<Double>
    let count: Double
    let integerCount: UInt64?
    let speedMinimum: SIMD3<Double>
    let speedMaximum: SIMD3<Double>
    let axis: SIMD3<Double>
    /// Derived only from the authored axis. The control point stays frame-local.
    let circleBasisU: SIMD3<Double>
    let circleBasisV: SIMD3<Double>
    let controlPoint: Int

    nonisolated func sequence(particleID: UInt64) -> Double {
        if let integerCount {
            return Double(particleID % integerCount) / count
        }
        // Reduce exact 32-bit limbs before combining them. Converting the
        // whole identity to Double first loses births above 2^53.
        let highRemainder = (Double(particleID >> 32) * 4_294_967_296)
            .truncatingRemainder(dividingBy: count)
        let lowRemainder = Double(UInt32(truncatingIfNeeded: particleID))
            .truncatingRemainder(dividingBy: count)
        return (highRemainder + lowRemainder)
            .truncatingRemainder(dividingBy: count) / count
    }
}

extension SceneParticleInitializer {
    nonisolated var positionAroundControlPointPlan:
        SceneParticlePositionAroundControlPointPlan? {
        guard case let .positionAroundControlPoint(value) = kind,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              value.rawFlags ?? 0 == 0,
              (value.limitBehavior ?? "repeat") == "repeat",
              let bounds = Self.vector(value.bounds ?? .vector([0, 1]), count: 2),
              let count = value.count, count.isFinite, (1 ... 1_024).contains(count),
              let speedMinimum = Self.vector(value.speedMinimum ?? .vector([0, 0, 0]), count: 3),
              let speedMaximum = Self.vector(value.speedMaximum ?? .vector([0, 0, 0]), count: 3),
              (0 ... 7).contains(value.controlPoint ?? 0) else { return nil }
        guard bounds.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }),
              bounds[0] <= bounds[1],
              speedMinimum.indices.allSatisfy({ index in
                  speedMinimum[index].isFinite && speedMaximum[index].isFinite
                      && abs(speedMinimum[index]) <= 1_000_000
                      && abs(speedMaximum[index]) <= 1_000_000
                      && speedMinimum[index] <= speedMaximum[index]
              }) else { return nil }

        let minimumSpeed = SIMD3(
            speedMinimum[0], speedMinimum[1], speedMinimum[2]
        )
        let maximumSpeed = SIMD3(
            speedMaximum[0], speedMaximum[1], speedMaximum[2]
        )
        let authoredAxis: SIMD3<Double>
        if value.axis == nil {
            authoredAxis = SIMD3(0, 0, 1)
        } else if let values = Self.vector(value.axis, count: 3) {
            authoredAxis = SIMD3(values[0], values[1], values[2])
        } else {
            return nil
        }
        let length = sqrt(
            authoredAxis.x * authoredAxis.x + authoredAxis.y * authoredAxis.y
                + authoredAxis.z * authoredAxis.z
        )
        guard authoredAxis.x.isFinite, authoredAxis.y.isFinite,
              authoredAxis.z.isFinite, length.isFinite, length > 1e-12,
              abs(authoredAxis.x) <= 1_000_000,
              abs(authoredAxis.y) <= 1_000_000,
              abs(authoredAxis.z) <= 1_000_000 else { return nil }
        let axis = authoredAxis / length
        let reference = abs(axis.z) > 0.9 ? SIMD3<Double>(0, 1, 0) : .init(0, 0, 1)
        let first = SIMD3(
            reference.y * axis.z - reference.z * axis.y,
            reference.z * axis.x - reference.x * axis.z,
            reference.x * axis.y - reference.y * axis.x
        )
        let basisLength = sqrt(first.x * first.x + first.y * first.y + first.z * first.z)
        guard basisLength.isFinite, basisLength > 1e-12 else { return nil }
        let basisU = first / basisLength
        let basisV = SIMD3(
            axis.y * basisU.z - axis.z * basisU.y,
            axis.z * basisU.x - axis.x * basisU.z,
            axis.x * basisU.y - axis.y * basisU.x
        )
        return .init(
            bounds: bounds[0] ... bounds[1], count: count,
            integerCount: UInt64(exactly: count),
            speedMinimum: minimumSpeed, speedMaximum: maximumSpeed,
            axis: axis, circleBasisU: basisU, circleBasisV: basisV,
            controlPoint: value.controlPoint ?? 0
        )
    }

    private nonisolated static func vector(
        _ value: SceneParticleNumericValue?, count: Int
    ) -> [Double]? {
        guard case let .vector(values) = value, values.count == count else { return nil }
        return values
    }
}

extension SceneParticleControlPoint {
    nonisolated func hasBoundedPositionAroundStaticInput(identity: Int) -> Bool {
        guard id == identity, rawFlags == 0, angles == nil,
              parentControlPoint == nil else { return false }
        let values: [Double]
        switch offset {
        case nil:
            values = [0, 0, 0]
        case let .vector(authored) where authored.count == 3:
            values = authored
        default:
            return false
        }
        return values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
    }
}

extension SceneParticleDefinition {
    nonisolated func supportsBoundedPositionAroundControlPoint(
        _ initializer: SceneParticleInitializer
    ) -> Bool {
        // The pointer value is the layer-local unprojection and births
        // compose positions in local space; world-space and perspective
        // systems share the demand with local ones.
        guard emitters.count == 1,
              let plan = initializer.positionAroundControlPointPlan,
              hasUniquePositionAroundControlPointIdentities,
              let point = controlPoints.first(where: { $0.id == plan.controlPoint }),
              point.hasBoundedPointerInput
                || point.hasBoundedPositionAroundStaticInput(identity: plan.controlPoint)
        else { return false }
        let emitter = emitters[0]
        if let source = emitterControlPointSource(for: emitter) {
            return source == plan.controlPoint
        }
        switch emitter.origin {
        case nil:
            return true
        case let .vector(values):
            return values.count == 3 && values.allSatisfy { $0 == 0 }
        default:
            return false
        }
    }

    nonisolated var positionAroundPointerControlPointIdentities: Set<Int> {
        Set(initializers.compactMap { initializer in
            guard supportsBoundedPositionAroundControlPoint(initializer),
                  let identity = initializer.positionAroundControlPointPlan?.controlPoint,
                  controlPoints.contains(where: {
                      $0.id == identity && $0.hasBoundedPointerInput
                  }) else { return nil }
            return identity
        })
    }

    private nonisolated var hasUniquePositionAroundControlPointIdentities: Bool {
        var identities: Set<Int> = []
        for point in controlPoints {
            guard let identity = point.id, (0 ... 7).contains(identity),
                  identities.insert(identity).inserted else { return false }
        }
        return true
    }
}
