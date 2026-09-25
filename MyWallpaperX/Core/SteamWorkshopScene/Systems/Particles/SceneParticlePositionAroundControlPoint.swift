import Foundation

nonisolated struct SceneParticlePositionAroundControlPoint: Equatable, Sendable {
    let bounds: SceneParticleNumericValue?
    let count: Int?
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
        count = SceneParticleDefinitionParser.integer(root["count"])
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
        hasMalformedFields = parsed.contains { key, value in
            root[key] != nil && !(root[key] is NSNull) && value == nil
        }
    }
}

nonisolated struct SceneParticlePositionAroundControlPointPlan: Equatable, Sendable {
    let bounds: ClosedRange<Double>
    let count: Int
    let speedMinimum: SIMD3<Double>
    let speedMaximum: SIMD3<Double>
    let axis: SIMD3<Double>
    let controlPoint: Int
}

extension SceneParticleInitializer {
    nonisolated var positionAroundControlPointPlan:
        SceneParticlePositionAroundControlPointPlan? {
        guard case let .positionAroundControlPoint(value) = kind,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              value.rawFlags ?? 0 == 0,
              value.limitBehavior == "repeat",
              let bounds = Self.vector(value.bounds, count: 2),
              let count = value.count, (1 ... 1_024).contains(count),
              let speedMinimum = Self.vector(value.speedMinimum, count: 3),
              let speedMaximum = Self.vector(value.speedMaximum, count: 3),
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
        return .init(
            bounds: bounds[0] ... bounds[1], count: count,
            speedMinimum: minimumSpeed, speedMaximum: maximumSpeed,
            axis: authoredAxis / length, controlPoint: value.controlPoint ?? 0
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
    nonisolated var hasBoundedPositionAroundPointerInput: Bool {
        guard rawFlags == 1, let id, (0 ... 7).contains(id), angles == nil,
              parentControlPoint == nil else { return false }
        switch offset {
        case nil:
            return true
        case let .vector(values):
            return values.count == 3 && values.allSatisfy { $0 == 0 }
        default:
            return false
        }
    }

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
        guard !flags.isWorldSpace, !flags.usesPerspective,
              !operators.contains(where: \.isWorldSpaceMovement),
              emitters.count == 1,
              let plan = initializer.positionAroundControlPointPlan,
              hasUniquePositionAroundControlPointIdentities,
              let point = controlPoints.first(where: { $0.id == plan.controlPoint }),
              point.hasBoundedPositionAroundPointerInput
                || point.hasBoundedPositionAroundStaticInput(identity: plan.controlPoint)
        else { return false }
        let emitter = emitters[0]
        if emitter.controlPoint == plan.controlPoint { return true }
        guard emitter.controlPoint == nil else { return false }
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
                      $0.id == identity && $0.hasBoundedPositionAroundPointerInput
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
