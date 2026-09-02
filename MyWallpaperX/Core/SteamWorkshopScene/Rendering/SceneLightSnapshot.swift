import simd

/// Immutable light publication consumed by lit material producers in the
/// shared frame. It carries scene data only; it owns no renderer or targets.
struct SceneLightSnapshot {
    struct Directional {
        let directionTowardLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
    }

    let ambient: SIMD3<Float>
    let directional: [Directional]

    static func make(
        descriptor: SceneRenderDescriptor,
        worldFramesByLayerID: [Int: simd_float4x4]
    ) -> SceneLightSnapshot {
        let ambient = color(descriptor.lighting?.ambientColorRGB)
            + color(descriptor.lighting?.skylightColorRGB)
        let directional = descriptor.layers.compactMap { layer -> Directional? in
            guard layer.visible != false,
                  let definition = layer.directionalLight,
                  let frame = worldFramesByLayerID[layer.id],
                  let direction = normalized(SIMD3(
                    frame.columns.2.x,
                    frame.columns.2.y,
                    frame.columns.2.z
                  )),
                  let intensity = definition.intensity,
                  intensity.isFinite,
                  intensity >= 0 else {
                return nil
            }
            return Directional(
                directionTowardLight: direction,
                color: color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
                intensity: intensity
            )
        }.prefix(4)
        if ambient == .zero && directional.isEmpty {
            return SceneLightSnapshot(ambient: SIMD3(1, 1, 1), directional: [])
        }
        return SceneLightSnapshot(
            ambient: ambient,
            directional: Array(directional)
        )
    }

    private static func color(
        _ values: [Float]?,
        fallback: SIMD3<Float> = .zero
    ) -> SIMD3<Float> {
        guard let values, values.count == 3,
              values.allSatisfy(\.isFinite) else { return fallback }
        return SIMD3(
            max(values[0], 0),
            max(values[1], 0),
            max(values[2], 0)
        )
    }

    private static func normalized(_ value: SIMD3<Float>) -> SIMD3<Float>? {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared.isFinite, lengthSquared > 1e-8 else { return nil }
        return value / sqrt(lengthSquared)
    }
}
