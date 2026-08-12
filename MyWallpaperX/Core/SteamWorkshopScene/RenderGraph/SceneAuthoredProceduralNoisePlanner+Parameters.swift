import Foundation
import simd

extension SceneAuthoredProceduralNoisePlanner {
    nonisolated struct Parameters {
        let scale: SIMD2<Float>
        let offset: SIMD2<Float>
        let magnitude: SIMD2<Float>
        let thresholds: SIMD2<Float>
        let colorsMin: SIMD3<Float>
        let colorsMax: SIMD3<Float>
        let opacity: Float
        let exponent: Float
        let fractals: Int
        let fractalScale: Float
        let fractalInfluence: Float
        let gradient: Float
        let seed: Float
        let animationSpeed: Float
        let scrollDirection: Float
        let scrollSpeed: Float
        let thresholdOffset: Float
        let shiftAmount: Float
        let depthFade: Float
        let perspective01: SIMD4<Float>
        let perspective23: SIMD4<Float>
    }

    nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue],
        variant: SceneProceduralNoiseExecutionPlan.Variant
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        let isV1 = variant == .worleyColorV1
        var keys = isV1 ? v1Keys : commonKeys
        if variant == .colorPerlinRGB { keys.formUnion(["colors min", "colors max"]) }
        if variant == .uvWorleyMix { keys.insert("sample shift amount") }
        guard values.count == keys.count, values.keys.allSatisfy(keys.contains),
              let scale = vector2(values["scale"], range: 0...3),
              scale.x > 0, scale.y > 0,
              let offset = vector2(values["offset"], range: -1...1),
              let magnitude = isV1
                ? scalar(values["magnitude"], range: 0...1).map(SIMD2.init(repeating:))
                : vector2(values["magnitude"], range: 0...1),
              let thresholds = vector2(values["thresholds"], range: -1...2),
              thresholds.y > thresholds.x,
              let opacity = scalar(values["opacity"], range: 0...1),
              let exponent = scalar(values["exponent"], range: 0...5),
              let fractalsValue = scalar(
                  values["fractals"], range: isV1 ? 1...10 : 1...5
              ),
              fractalsValue.rounded() == fractalsValue,
              let fractalScale = scalar(values["fractal scaling"], range: 1...4),
              let fractalInfluence = scalar(values["fractal influence"], range: 0...1),
              let gradient = scalar(values["gradient"], range: 0...1),
              let seed = scalar(values["seed"], range: -1...1),
              let animationSpeed = scalar(values["animationspeed"], range: 0...3),
              let scrollDirection = scalar(values["scrollirection"], range: -7...7),
              let scrollSpeed = scalar(values["scrollspeed"], range: 0...2),
              let thresholdOffset = scalar(values["thresholds offset"], range: -1...1) else {
            return nil
        }
        let colorsMin = vector3(
            values[isV1 ? "color low" : "colors min"], range: 0...1
        ) ?? .zero
        let colorsMax = vector3(
            values[isV1 ? "color high" : "colors max"], range: 0...1
        ) ?? SIMD3(repeating: 1)
        let shiftAmount = scalar(values["sample shift amount"], range: 0...1) ?? 1
        let depthFade = scalar(values["depth fade"], range: 0...1) ?? 1
        let p0 = vector2(values["point0"], range: -2...2) ?? SIMD2(0, 0)
        let p1 = vector2(values["point1"], range: -2...2) ?? SIMD2(1, 0)
        let p2 = vector2(values["point2"], range: -2...2) ?? SIMD2(1, 1)
        let p3 = vector2(values["point3"], range: -2...2) ?? SIMD2(0, 1)
        guard !isV1 || (
            simd_length_squared(p1 - p0) > 0.01
                && simd_length_squared(p2 - p3) > 0.01
                && simd_length_squared(p3 - p0) > 0.01
        ) else { return nil }
        return .init(
            scale: scale, offset: offset, magnitude: magnitude, thresholds: thresholds,
            colorsMin: colorsMin, colorsMax: colorsMax, opacity: opacity,
            exponent: exponent, fractals: Int(fractalsValue), fractalScale: fractalScale,
            fractalInfluence: fractalInfluence, gradient: gradient, seed: seed,
            animationSpeed: animationSpeed, scrollDirection: scrollDirection,
            scrollSpeed: scrollSpeed, thresholdOffset: thresholdOffset,
            shiftAmount: shiftAmount, depthFade: depthFade,
            perspective01: SIMD4(p0.x, p0.y, p1.x, p1.y),
            perspective23: SIMD4(p2.x, p2.y, p3.x, p3.y)
        )
    }

    nonisolated static func equal(_ lhs: Parameters, _ rhs: Parameters) -> Bool {
        lhs.scale == rhs.scale && lhs.offset == rhs.offset && lhs.magnitude == rhs.magnitude
            && lhs.thresholds == rhs.thresholds && lhs.colorsMin == rhs.colorsMin
            && lhs.colorsMax == rhs.colorsMax && lhs.opacity == rhs.opacity
            && lhs.exponent == rhs.exponent && lhs.fractals == rhs.fractals
            && lhs.fractalScale == rhs.fractalScale
            && lhs.fractalInfluence == rhs.fractalInfluence && lhs.gradient == rhs.gradient
            && lhs.seed == rhs.seed && lhs.animationSpeed == rhs.animationSpeed
            && lhs.scrollDirection == rhs.scrollDirection && lhs.scrollSpeed == rhs.scrollSpeed
            && lhs.thresholdOffset == rhs.thresholdOffset && lhs.shiftAmount == rhs.shiftAmount
            && lhs.depthFade == rhs.depthFade && lhs.perspective01 == rhs.perspective01
            && lhs.perspective23 == rhs.perspective23
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> Float? {
        guard let value, value.valueKind.lowercased() == "number", value.userBinding == nil,
              value.components?.count == 1, let component = value.components?.first,
              component.isFinite, range.contains(component) else { return nil }
        return Float(component)
    }

    private nonisolated static func vector2(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let components = vector(value, count: 2, range: range) else { return nil }
        return SIMD2(Float(components[0]), Float(components[1]))
    }

    private nonisolated static func vector3(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> SIMD3<Float>? {
        guard let components = vector(value, count: 3, range: range) else { return nil }
        return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?, count: Int, range: ClosedRange<Double>
    ) -> [Double]? {
        guard let value, value.valueKind.lowercased() == "vector", value.userBinding == nil,
              let components = value.components, components.count == count,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else { return nil }
        return components
    }

    private nonisolated static let commonKeys = Set([
        "exponent", "fractal influence", "fractal scaling", "fractals", "gradient",
        "magnitude", "offset", "opacity", "scale", "seed", "thresholds",
        "thresholds offset", "animationspeed", "scrollirection", "scrollspeed",
    ])

    private nonisolated static let v1Keys = Set([
        "animationspeed", "color high", "color low", "depth fade", "exponent",
        "fractal influence", "fractal scaling", "fractals", "gradient", "magnitude",
        "offset", "opacity", "point0", "point1", "point2", "point3", "scale",
        "scrollirection", "scrollspeed", "seed", "thresholds", "thresholds offset",
    ])
}
