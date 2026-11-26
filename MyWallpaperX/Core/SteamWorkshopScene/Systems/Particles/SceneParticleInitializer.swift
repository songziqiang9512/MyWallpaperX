import Foundation

nonisolated enum SceneParticleInitializerKind: Equatable, Sendable {
    case lifetime
    case size
    case velocity
    case color
    case hsvColor
    case colorList
    case alpha
    case rotation
    case angularVelocity
    case turbulentVelocity
    case positionOffset
    case positionAroundControlPoint(SceneParticlePositionAroundControlPoint)
    case positionBetweenControlPoints(SceneParticlePositionBetweenControlPoints)
    case inheritEventValue(SceneParticleEventValueOperation?)
    case unsupported(String)

}

nonisolated enum SceneParticleEventValueOperation: String, Equatable, Sendable {
    case setColor = "setcolor"
    case multiplySize = "multiplysize"
    case setOpacity = "setopacity"

    nonisolated init?(root: [String: Any]) {
        let input: String
        if let raw = root["input"] {
            guard let value = raw as? String else { return nil }
            input = value
        } else {
            input = "setcolor"
        }
        self.init(rawValue: input)
    }

    nonisolated func canConsume(_ values: SceneParticleEventValues) -> Bool {
        switch self {
        case .setColor:
            values.color.x.isFinite && values.color.y.isFinite && values.color.z.isFinite
        case .multiplySize:
            values.size.isFinite
        case .setOpacity:
            values.alpha.isFinite
        }
    }
}

nonisolated struct SceneParticleEventValues: Equatable, Sendable {
    let color: SIMD3<Double>
    let size: Double
    let alpha: Double
}

nonisolated enum SceneParticleEventValueContext: Equatable, Sendable {
    case unavailable
    case snapshot(SceneParticleEventValues)
    case follow(SceneParticleEventValues)

    nonisolated var initializerValues: SceneParticleEventValues? {
        switch self {
        case .unavailable: nil
        case let .snapshot(values), let .follow(values): values
        }
    }

    nonisolated var operatorValues: SceneParticleEventValues? {
        guard case let .follow(values) = self else { return nil }
        return values
    }
}

nonisolated struct SceneParticleHSVColorPlan: Equatable, Sendable {
    private(set) var hueStart: Double
    let hueStride: Double
    let huePickCount: Double
    private(set) var saturation: ClosedRange<Double>
    private(set) var value: ClosedRange<Double>
    private let authoredSpan: SIMD3<Double>

    var colorReference: SIMD3<Double> {
        SIMD3(hueStart + authoredSpan.x / 2,
              (saturation.lowerBound + saturation.upperBound) / 2,
              (value.lowerBound + value.upperBound) / 2)
    }

    init?(root: [String: Any]) {
        func number(_ key: String, default fallback: Double) -> Double? {
            guard let raw = root[key] else { return fallback }
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.floatValue.isFinite else { return nil }
            return value.doubleValue
        }

        guard let hueMinimum = number("huemin", default: 0),
              let hueMaximum = number("huemax", default: 1),
              let rawSteps = number("huesteps", default: 6), let hueSteps = Int(exactly: rawSteps),
              let saturationMinimum = number("saturationmin", default: 0.5),
              let saturationMaximum = number("saturationmax", default: 1),
              let valueMinimum = number("valuemin", default: 0.5),
              let valueMaximum = number("valuemax", default: 1) else { return nil }
        let steps = Double(max(1, hueSteps))
        let span = hueMaximum - hueMinimum
        hueStart = hueMinimum
        if steps == 1 {
            hueStride = 0
        } else if span == 0 {
            hueStride = 1 / steps
        } else {
            hueStride = span / (abs(span) == 1 ? steps : steps - 1)
        }
        huePickCount = steps + 1
        saturation = min(saturationMinimum, saturationMaximum) ... max(saturationMinimum, saturationMaximum)
        value = min(valueMinimum, valueMaximum) ... max(valueMinimum, valueMaximum)
        authoredSpan = SIMD3(span, saturationMaximum - saturationMinimum, valueMaximum - valueMinimum)
    }

    func tinted(to hsv: SIMD3<Double>) -> Self {
        func centeredRange(_ center: Double, span: Double) -> ClosedRange<Double> {
            let start = min(max(center - span / 2, 0), 1)
            let end = min(max(start + span, 0), 1)
            return min(start, end) ... max(start, end)
        }
        var plan = self
        let span = authoredSpan.x == 0 ? 1 : authoredSpan.x
        plan.hueStart = hueStride == 0 ? hsv.x : hsv.x - span / 2
        plan.saturation = centeredRange(hsv.y, span: authoredSpan.y)
        plan.value = centeredRange(hsv.z, span: authoredSpan.z)
        return plan
    }
}

nonisolated struct SceneParticleTurbulentVelocity: Equatable, Sendable {
    let forward: SceneParticleNumericValue?
    let right: SceneParticleNumericValue?
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
    let hsvColor: SceneParticleHSVColorPlan?
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
