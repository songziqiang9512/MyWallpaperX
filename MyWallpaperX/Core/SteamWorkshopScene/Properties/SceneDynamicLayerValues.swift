import Foundation

nonisolated enum SceneDynamicLayerValues {
    static func alpha(
        layerID: Int,
        authoredValue: Double?,
        snapshot: SceneDynamicSnapshot
    ) -> Float {
        let target = SceneDynamicTarget.layer(layerID: layerID, field: .alpha)
        if let resolved = snapshot[target],
           case let .scalar(value) = resolved.value,
           value.isFinite {
            return normalizedAlpha(value)
        }
        return normalizedAlpha(authoredValue ?? 1)
    }

    static func color(
        layerID: Int,
        authoredValue: [Float]?,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Float> {
        let target = SceneDynamicTarget.layer(layerID: layerID, field: .color)
        if let resolved = snapshot[target],
           case let .vector3(x, y, z) = resolved.value,
           x.isFinite, y.isFinite, z.isFinite {
            return normalizedColor(x, y, z)
        }
        guard let authoredValue else {
            return SIMD3(repeating: 1)
        }
        return normalizedColor(
            authoredComponent(at: 0, in: authoredValue),
            authoredComponent(at: 1, in: authoredValue),
            authoredComponent(at: 2, in: authoredValue)
        )
    }

    private static func normalizedAlpha(_ value: Double) -> Float {
        guard value.isFinite else { return 1 }
        return Float(min(max(value, 0), 1))
    }

    private static func normalizedColor(
        _ red: Double,
        _ green: Double,
        _ blue: Double
    ) -> SIMD3<Float> {
        guard red.isFinite, green.isFinite, blue.isFinite else {
            return SIMD3(repeating: 1)
        }
        return SIMD3(
            Float(min(max(red, 0), 1)),
            Float(min(max(green, 0), 1)),
            Float(min(max(blue, 0), 1))
        )
    }

    private static func authoredComponent(at index: Int, in values: [Float]) -> Double {
        index < values.count ? Double(values[index]) : 1
    }
}
