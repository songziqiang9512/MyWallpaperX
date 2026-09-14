import simd

/// Immutable light publication consumed by lit material producers in the
/// shared frame. It carries scene data only; it owns no renderer or targets.
struct SceneLightSnapshot {
    struct Directional {
        let directionTowardLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
    }

    struct Spot {
        let position: SIMD3<Float>
        let directionFromLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
        let innerConeCosine: Float
        let outerConeCosine: Float
    }

    let ambient: SIMD3<Float>
    let directional: [Directional]
    let spot: [Spot]
    var distanceFogColor: SIMD4<Float> = .zero
    var distanceFogRange: SIMD4<Float> = .zero

    static func make(
        descriptor: SceneRenderDescriptor,
        worldFramesByLayerID: [Int: simd_float4x4],
        dynamicLayerColors: [Int: SIMD3<Float>] = [:],
        candidateLayerIDs: [Int]? = nil,
        layersByID: [Int: SceneRenderDescriptor.Layer]? = nil
    ) -> SceneLightSnapshot {
        let ambient = color(descriptor.lighting?.ambientColorRGB)
            + color(descriptor.lighting?.skylightColorRGB)
        let lightLayers = candidateLayerIDs?.compactMap { layersByID?[$0] }
            ?? descriptor.layers
        let directional = lightLayers.compactMap { layer -> Directional? in
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
                color: dynamicLayerColors[layer.id]
                    ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
                intensity: intensity
            )
        }.prefix(4)
        let spot = lightLayers.compactMap { layer -> Spot? in
            guard layer.visible != false,
                  let definition = layer.spotLight,
                  let frame = worldFramesByLayerID[layer.id],
                  let direction = normalized(-SIMD3(
                      frame.columns.2.x,
                      frame.columns.2.y,
                      frame.columns.2.z
                  )),
                  let intensity = definition.intensity,
                  let radius = definition.radius,
                  let innerCone = definition.innerConeDegrees,
                  let outerCone = definition.outerConeDegrees,
                  intensity.isFinite, intensity >= 0,
                  radius.isFinite, radius > 0,
                  innerCone.isFinite, outerCone.isFinite,
                  innerCone > 0, innerCone <= outerCone, outerCone < 180 else {
                return nil
            }
            let position = SIMD3(
                frame.columns.3.x,
                frame.columns.3.y,
                frame.columns.3.z
            )
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                return nil
            }
            let degreesToHalfRadians = Float.pi / 360
            return Spot(
                position: position,
                directionFromLight: direction,
                color: dynamicLayerColors[layer.id]
                    ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
                intensity: intensity,
                radius: radius,
                innerConeCosine: cos(innerCone * degreesToHalfRadians),
                outerConeCosine: cos(outerCone * degreesToHalfRadians)
            )
        }.prefix(4)
        let fog = descriptor.lighting?.distanceFog
        return SceneLightSnapshot(
            ambient: ambient == .zero && directional.isEmpty && spot.isEmpty
                ? SIMD3(1, 1, 1) : ambient,
            directional: Array(directional),
            spot: Array(spot),
            distanceFogColor: fog.map { SIMD4($0.color[0], $0.color[1], $0.color[2], 1) } ?? .zero,
            distanceFogRange: fog.map { SIMD4($0.start, $0.end, $0.startDensity, $0.endDensity) } ?? .zero
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
