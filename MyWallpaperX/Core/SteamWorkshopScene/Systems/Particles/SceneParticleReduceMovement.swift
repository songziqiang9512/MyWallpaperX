import Foundation

/// Loss-preserving declaration for the authored Reduce Movement Near Control Point
/// operator. Execution is intentionally narrower than parsing so unsupported
/// lifecycle and coordinate-space shapes remain local component no-ops.
nonisolated struct SceneParticleReduceMovement: Equatable, Sendable {
    let controlPoint: Int?
    let distanceInner: Double?
    let distanceOuter: Double?
    let reductionInner: Double?
    let reductionOuter: Double?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        let supportedFields = Set([
            "id", "name", "flags", "controlpoint", "distanceinner",
            "distanceouter", "reductioninner", "reductionouter",
        ])
        let point = SceneParticleDefinitionParser.integer(root["controlpoint"])
        let innerDistance = SceneParticleDefinitionParser.number(root["distanceinner"])
        let outerDistance = SceneParticleDefinitionParser.number(root["distanceouter"])
        let innerReduction = SceneParticleDefinitionParser.number(root["reductioninner"])
        let outerReduction = SceneParticleDefinitionParser.number(root["reductionouter"])

        controlPoint = point
        distanceInner = innerDistance
        distanceOuter = outerDistance
        reductionInner = innerReduction
        reductionOuter = outerReduction
        hasMalformedFields = [
            ("controlpoint", point != nil),
            ("distanceinner", innerDistance != nil),
            ("distanceouter", outerDistance != nil),
            ("reductioninner", innerReduction != nil),
            ("reductionouter", outerReduction != nil),
            ("flags", SceneParticleDefinitionParser.integer(root["flags"]) != nil),
        ].contains { key, parsed in
            root[key] != nil && !(root[key] is NSNull) && !parsed
        }
        unsupportedFieldNames = root.keys.filter { !supportedFields.contains($0) }.sorted()
    }
}

nonisolated struct SceneParticleReduceMovementPlan: Equatable, Sendable {
    let controlPoint: Int
    let distanceInner: Double
    let distanceOuter: Double
    let reductionInner: Double
    let reductionOuter: Double
}

nonisolated extension SceneParticleOperator {
    var reduceMovementPlan: SceneParticleReduceMovementPlan? {
        guard rawFlags == 0, case let .reduceMovement(value) = kind,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              blendInStart == nil, blendInEnd == nil,
              blendOutStart == nil, blendOutEnd == nil,
              !audioResponse.isEnabled,
              let distanceInner = value.distanceInner,
              let distanceOuter = value.distanceOuter,
              let reductionInner = value.reductionInner else { return nil }
        let reductionOuter = value.reductionOuter ?? 0
        guard distanceInner.isFinite, distanceOuter.isFinite,
              reductionInner.isFinite, reductionOuter.isFinite,
              distanceInner >= 0, distanceInner <= distanceOuter,
              distanceOuter <= 1_000_000,
              abs(reductionInner) <= 1_000_000,
              abs(reductionOuter) <= 1_000_000,
              (0 ... 7).contains(value.controlPoint ?? 0) else { return nil }
        return .init(
            controlPoint: value.controlPoint ?? 0,
            distanceInner: distanceInner,
            distanceOuter: distanceOuter,
            reductionInner: reductionInner,
            reductionOuter: reductionOuter
        )
    }
}

nonisolated extension SceneParticleControlPoint {
    func hasBoundedReduceMovementInput(identity: Int) -> Bool {
        guard id == identity, !hasMalformedFields,
              rawFlags == 0 || rawFlags == 2,
              angles == nil, parentControlPoint == nil || parentControlPoint == 0 else {
            return false
        }
        switch offset {
        case nil:
            return true
        case let .vector(values) where values.count == 3:
            return values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
        default:
            return false
        }
    }
}

nonisolated extension SceneParticleDefinition {
    func supportsBoundedReduceMovement(_ value: SceneParticleOperator) -> Bool {
        guard !flags.isWorldSpace, !flags.usesPerspective,
              !operators.contains(where: \.isWorldSpaceMovement),
              let plan = value.reduceMovementPlan,
              supportsReduceMovementControlPoint(plan.controlPoint) else { return false }
        guard let point = controlPoints.first(where: { $0.id == plan.controlPoint }) else {
            return plan.controlPoint == 0
        }
        return point.hasBoundedReduceMovementInput(identity: plan.controlPoint)
    }

    private func supportsReduceMovementControlPoint(_ source: Int) -> Bool {
        guard (0 ... 7).contains(source) else { return false }
        var identities: Set<Int> = []
        for point in controlPoints {
            guard let id = point.id, (0 ... 7).contains(id),
                  identities.insert(id).inserted else { return false }
        }
        return true
    }
}
