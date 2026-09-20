import simd

/// Immutable light publication consumed by lit material producers in the
/// shared frame. It carries scene data only; it owns no renderer or targets.
struct SceneLightSnapshot {
    static let maximumLightCount = 4

    struct Directional {
        let directionTowardLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
    }

    struct Point {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
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
    let point: [Point]
    let spot: [Spot]
    let overflowCount: Int
    var distanceFogColor: SIMD4<Float> = .zero
    var distanceFogRange: SIMD4<Float> = .zero

    static func make(
        descriptor: SceneRenderDescriptor,
        worldFramesByLayerID: [Int: simd_float4x4],
        dynamicLayerColors: [Int: SIMD3<Float>] = [:],
        dynamicSnapshot: SceneDynamicSnapshot? = nil,
        candidateLayerIDs: [Int]? = nil,
        layersByID: [Int: SceneRenderDescriptor.Layer]? = nil,
        visibleLayerIDs: Set<Int>? = nil
    ) -> SceneLightSnapshot {
        let ambient = color(descriptor.lighting?.ambientColorRGB)
            + color(descriptor.lighting?.skylightColorRGB)
        let resolvedLayersByID = layersByID ?? Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        let lightLayerIDs = candidateLayerIDs ?? orderedLightLayerIDs(
            descriptor: descriptor,
            layersByID: resolvedLayersByID
        )
        let lightLayers = lightLayerIDs.compactMap { resolvedLayersByID[$0] }
        var directionalLights: [Directional] = []
        var pointLights: [Point] = []
        var spotLights: [Spot] = []
        var acceptedCount = 0
        var overflowCount = 0
        for layer in lightLayers {
            guard visibleLayerIDs?.contains(layer.id)
                    ?? (layer.visible != false) else { continue }
            guard let frame = worldFramesByLayerID[layer.id] else { continue }
            let dynamicColor = dynamicLayerColors[layer.id]
            let intensity = dynamicSnapshot.flatMap {
                SceneDynamicLayerValues.lightIntensity(
                    layerID: layer.id,
                    authoredValue: authoredIntensity(layer),
                    snapshot: $0
                )
            } ?? authoredIntensity(layer)
            if let light = directional(
                layer: layer, frame: frame, dynamicColor: dynamicColor,
                intensity: intensity
            ) {
                if acceptedCount < maximumLightCount {
                    directionalLights.append(light)
                    acceptedCount += 1
                } else {
                    overflowCount += 1
                }
            } else if let light = point(
                layer: layer, frame: frame, dynamicColor: dynamicColor,
                intensity: intensity
            ) {
                if acceptedCount < maximumLightCount {
                    pointLights.append(light)
                    acceptedCount += 1
                } else {
                    overflowCount += 1
                }
            } else if let light = spot(
                layer: layer, frame: frame, dynamicColor: dynamicColor,
                intensity: intensity
            ) {
                if acceptedCount < maximumLightCount {
                    spotLights.append(light)
                    acceptedCount += 1
                } else {
                    overflowCount += 1
                }
            }
        }
        let fog = descriptor.lighting?.distanceFog
        return SceneLightSnapshot(
            ambient: ambient == .zero && directionalLights.isEmpty
                && pointLights.isEmpty && spotLights.isEmpty
                ? SIMD3(1, 1, 1) : ambient,
            directional: directionalLights,
            point: pointLights,
            spot: spotLights,
            overflowCount: overflowCount,
            distanceFogColor: fog.map { SIMD4($0.color[0], $0.color[1], $0.color[2], 1) } ?? .zero,
            distanceFogRange: fog.map { SIMD4($0.start, $0.end, $0.startDensity, $0.endDensity) } ?? .zero
        )
    }

    /// Projects light candidates from the same current authored order used by
    /// layer encoding. Storage order is not an execution-order authority.
    static func orderedLightLayerIDs(
        descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> [Int] {
        descriptor.renderOrderLayerIDs.compactMap { layerID in
            guard let layer = layersByID[layerID],
                  layer.pointLight != nil || layer.spotLight != nil
                    || layer.directionalLight != nil else { return nil }
            return layerID
        }
    }

    /// Declares launch-stable typed inputs for every authored light candidate.
    /// Frame visibility remains the snapshot consumer's authority, but it may
    /// change through a typed producer after launch. Reserving the candidate
    /// set here prevents authored-hidden lights or hidden parent chains from
    /// losing their color/intensity lanes when they later become visible.
    static func liveConsumerTargets(
        descriptor: SceneRenderDescriptor
    ) -> Set<SceneDynamicTarget> {
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        return orderedLightLayerIDs(
            descriptor: descriptor,
            layersByID: layersByID
        ).reduce(into: Set<SceneDynamicTarget>()) { targets, layerID in
            guard let layer = layersByID[layerID] else { return }
            targets.insert(.layer(layerID: layerID, field: .color))
            if authoredIntensity(layer) != nil {
                targets.insert(.layer(layerID: layerID, field: .intensity))
            }
        }
    }

    private static func directional(
        layer: SceneRenderDescriptor.Layer,
        frame: simd_float4x4,
        dynamicColor: SIMD3<Float>?,
        intensity: Float?
    ) -> Directional? {
        guard let definition = layer.directionalLight,
              let direction = normalized(SIMD3(
                  frame.columns.2.x,
                  frame.columns.2.y,
                  frame.columns.2.z
              )),
              let intensity,
              intensity.isFinite, intensity >= 0 else { return nil }
        return Directional(
            directionTowardLight: direction,
            color: dynamicColor
                ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
            intensity: intensity
        )
    }

    private static func authoredIntensity(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Float? {
        layer.pointLight?.intensity
            ?? layer.spotLight?.intensity
            ?? layer.directionalLight?.intensity
    }

    private static func point(
        layer: SceneRenderDescriptor.Layer,
        frame: simd_float4x4,
        dynamicColor: SIMD3<Float>?,
        intensity: Float?
    ) -> Point? {
        guard let definition = layer.pointLight,
              let intensity,
              let radius = definition.radius,
              intensity.isFinite, intensity >= 0,
              radius.isFinite, radius > 0,
              let position = position(of: frame) else { return nil }
        return Point(
            position: position,
            color: dynamicColor
                ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
            intensity: intensity,
            radius: radius
        )
    }

    private static func spot(
        layer: SceneRenderDescriptor.Layer,
        frame: simd_float4x4,
        dynamicColor: SIMD3<Float>?,
        intensity: Float?
    ) -> Spot? {
        guard let definition = layer.spotLight,
              let direction = normalized(-SIMD3(
                  frame.columns.2.x,
                  frame.columns.2.y,
                  frame.columns.2.z
              )),
              let intensity,
              let radius = definition.radius,
              let innerCone = definition.innerConeDegrees,
              let outerCone = definition.outerConeDegrees,
              intensity.isFinite, intensity >= 0,
              radius.isFinite, radius > 0,
              innerCone.isFinite, outerCone.isFinite,
              innerCone > 0, innerCone <= outerCone, outerCone < 180,
              let position = position(of: frame) else { return nil }
        let degreesToHalfRadians = Float.pi / 360
        return Spot(
            position: position,
            directionFromLight: direction,
            color: dynamicColor
                ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
            intensity: intensity,
            radius: radius,
            innerConeCosine: cos(innerCone * degreesToHalfRadians),
            outerConeCosine: cos(outerCone * degreesToHalfRadians)
        )
    }

    private static func position(of frame: simd_float4x4) -> SIMD3<Float>? {
        let position = SIMD3(
            frame.columns.3.x,
            frame.columns.3.y,
            frame.columns.3.z
        )
        return position.x.isFinite && position.y.isFinite && position.z.isFinite
            ? position : nil
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
