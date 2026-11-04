import Foundation

nonisolated struct SceneParticlePositionBetweenControlPoints: Equatable, Sendable {
    let bounds: SceneParticleNumericValue?
    let count: Double?
    let limitBehavior: String?
    let controlPointStart: Int?
    let controlPointEnd: Int?
    let rawFlags: Int?
    let sizeReductionAmount: Double?
    let hasMalformedFields: Bool
    let hasMalformedSizeReductionAmount: Bool

    nonisolated init(root: [String: Any]) {
        func malformed(_ key: String, _ value: Any?) -> Bool {
            root[key] != nil && !(root[key] is NSNull) && value == nil
        }
        bounds = SceneParticleDefinitionParser.numericValue(root["bounds"])
        count = SceneParticleDefinitionParser.number(root["count"])
        limitBehavior = (root["limitbehavior"] as? String).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        controlPointStart = SceneParticleDefinitionParser.integer(root["controlpointstart"])
        controlPointEnd = SceneParticleDefinitionParser.integer(root["controlpointend"])
        rawFlags = SceneParticleDefinitionParser.integer(root["flags"])
        sizeReductionAmount = SceneParticleDefinitionParser.number(root["sizereductionamount"])
        hasMalformedFields = malformed("bounds", bounds) || malformed("count", count)
            || malformed("limitbehavior", limitBehavior)
            || malformed("controlpointstart", controlPointStart)
            || malformed("controlpointend", controlPointEnd) || malformed("flags", rawFlags)
        hasMalformedSizeReductionAmount = malformed("sizereductionamount", sizeReductionAmount)
    }
}

nonisolated struct SceneParticlePositionBetweenControlPointsPlan: Equatable, Sendable {
    enum LimitBehavior: String, Equatable, Sendable { case `repeat`, mirror }

    let bounds: SIMD2<Double>
    let count: Double
    let limitBehavior: LimitBehavior
    let controlPointStart: Int
    let controlPointEnd: Int
    let rawFlags: Int
    let sizeReductionAmount: Double?

    var hasUnconsumedOptions: Bool {
        rawFlags & ~(1 | 2 | 4 | 16) != 0
            || (rawFlags & 4 != 0 && sizeReductionAmount == nil)
    }

    nonisolated func sequence(particleID: UInt64, countScale: Double) -> Double {
        let samples = count * (rawFlags & 16 != 0 ? countScale : 1)
        guard samples > 1 else { return 0 }
        let span = samples - 1
        switch limitBehavior {
        case .repeat:
            return sceneParticleSequenceRemainder(
                particleID, divisor: samples, integerDivisor: UInt64(exactly: samples)
            ) / span
        case .mirror:
            let period = span * 2
            let phase = sceneParticleSequenceRemainder(
                particleID, divisor: period, integerDivisor: UInt64(exactly: period)
            )
            return (phase <= span ? phase : period - phase) / span
        }
    }
}

extension SceneParticleInitializer {
    nonisolated var positionBetweenControlPointsPlan:
        SceneParticlePositionBetweenControlPointsPlan? {
        guard case let .positionBetweenControlPoints(value) = kind,
              !value.hasMalformedFields,
              case let .vector(bounds) = value.bounds ?? .vector([0, 1]),
              bounds.count == 2, bounds[0].isFinite, bounds[1].isFinite,
              let behavior = SceneParticlePositionBetweenControlPointsPlan.LimitBehavior(
                  rawValue: value.limitBehavior ?? "repeat"
              ) else { return nil }
        let count = value.count ?? 32
        let start = value.controlPointStart ?? 0
        let end = value.controlPointEnd ?? 1
        guard count.isFinite, count > 0,
              (0 ... 7).contains(start), (0 ... 7).contains(end) else { return nil }
        let amount = value.sizeReductionAmount ?? 0.9
        return .init(
            bounds: SIMD2(bounds[0], bounds[1]), count: count,
            limitBehavior: behavior, controlPointStart: start, controlPointEnd: end,
            rawFlags: value.rawFlags ?? 0,
            sizeReductionAmount: !value.hasMalformedSizeReductionAmount && amount.isFinite
                ? amount : nil
        )
    }
}
