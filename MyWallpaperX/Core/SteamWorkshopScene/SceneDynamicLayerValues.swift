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

    private static func normalizedAlpha(_ value: Double) -> Float {
        guard value.isFinite else { return 1 }
        return Float(min(max(value, 0), 1))
    }
}
