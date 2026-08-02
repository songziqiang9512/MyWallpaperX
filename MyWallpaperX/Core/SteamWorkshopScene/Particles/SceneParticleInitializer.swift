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
    case inheritEventColor(SceneParticleEventColorDeclaration)
    case unsupported(String)
}

nonisolated struct SceneParticleEventColorDeclaration: Equatable, Sendable {
    let input: String?
    let hasMalformedInput: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        input = root["input"] as? String
        hasMalformedInput = root["input"] != nil && input == nil
        let supported = Set(["id", "name", "input"])
        unsupportedFieldNames = root.keys.filter { !supported.contains($0) }.sorted()
    }

    nonisolated var isBoundedSetColor: Bool {
        !hasMalformedInput && unsupportedFieldNames.isEmpty
            && (input == nil || input == "setcolor")
    }
}

nonisolated enum SceneParticleEventColorContext: Equatable, Sendable {
    case unavailable
    case snapshot(SIMD3<Double>)
    case follow(SIMD3<Double>)

    nonisolated var initializerColor: SIMD3<Double>? {
        switch self {
        case .unavailable: nil
        case let .snapshot(color), let .follow(color):
            color.x.isFinite && color.y.isFinite && color.z.isFinite ? color : nil
        }
    }

    nonisolated var operatorColor: SIMD3<Double>? {
        guard case let .follow(color) = self,
              color.x.isFinite, color.y.isFinite, color.z.isFinite else { return nil }
        return color
    }
}

nonisolated struct SceneParticleHSVColor: Equatable, Sendable {
    let hueMinimum: Double?
    let hueMaximum: Double?
    let hueSteps: Int?
    let saturationMinimum: Double?
    let saturationMaximum: Double?
    let valueMinimum: Double?
    let valueMaximum: Double?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        func number(_ key: String) -> Double? {
            guard let value = root[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value.doubleValue
        }
        func integer(_ key: String) -> Int? {
            guard let value = number(key), value.isFinite else { return nil }
            return Int(exactly: value)
        }
        hueMinimum = number("huemin")
        hueMaximum = number("huemax")
        hueSteps = integer("huesteps")
        saturationMinimum = number("saturationmin")
        saturationMaximum = number("saturationmax")
        valueMinimum = number("valuemin")
        valueMaximum = number("valuemax")

        let supported = Set([
            "id", "name", "huemin", "huemax", "huesteps",
            "saturationmin", "saturationmax", "valuemin", "valuemax",
        ])
        unsupportedFieldNames = root.keys.filter { !supported.contains($0) }.sorted()
        let parsed: [String: Any?] = [
            "huemin": hueMinimum, "huemax": hueMaximum, "huesteps": hueSteps,
            "saturationmin": saturationMinimum, "saturationmax": saturationMaximum,
            "valuemin": valueMinimum, "valuemax": valueMaximum,
        ]
        hasMalformedFields = parsed.contains { key, value in
            guard let raw = root[key] else { return false }
            guard let number = raw as? NSNumber else { return true }
            return CFGetTypeID(number) == CFBooleanGetTypeID() || value == nil
        }
    }
}

nonisolated struct SceneParticleHSVColorPlan: Equatable, Sendable {
    let hue: ClosedRange<Double>
    let hueSteps: Int
    let saturation: ClosedRange<Double>
    let value: ClosedRange<Double>
}

nonisolated struct SceneParticleTurbulentVelocity: Equatable, Sendable {
    let forward: SceneParticleNumericValue?
    let right: SceneParticleNumericValue?
    let up: SceneParticleNumericValue?
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
    let hsvColor: SceneParticleHSVColor?
    let turbulentVelocity: SceneParticleTurbulentVelocity?
    let positionOffset: SceneParticlePositionOffset?
    let colors: [SceneParticleNumericValue]?
    let hasMalformedColorList: Bool
}

extension SceneParticleInitializer {
    nonisolated var boundedHSVColor: SceneParticleHSVColorPlan? {
        guard case .hsvColor = kind, let value = hsvColor,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              let hueMinimum = value.hueMinimum, let hueMaximum = value.hueMaximum,
              let hueSteps = value.hueSteps,
              let saturationMinimum = value.saturationMinimum,
              let saturationMaximum = value.saturationMaximum,
              let valueMinimum = value.valueMinimum, let valueMaximum = value.valueMaximum,
              hueMinimum.isFinite, hueMaximum.isFinite,
              saturationMinimum.isFinite, saturationMaximum.isFinite,
              valueMinimum.isFinite, valueMaximum.isFinite,
              (0 ... 1).contains(hueMinimum), (hueMinimum ... 1).contains(hueMaximum),
              (1 ... 1_024).contains(hueSteps),
              (0 ... 1).contains(saturationMinimum),
              (saturationMinimum ... 1).contains(saturationMaximum),
              (0 ... 1).contains(valueMinimum),
              (valueMinimum ... 1).contains(valueMaximum) else { return nil }
        return .init(
            hue: hueMinimum ... hueMaximum, hueSteps: hueSteps,
            saturation: saturationMinimum ... saturationMaximum,
            value: valueMinimum ... valueMaximum
        )
    }

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
