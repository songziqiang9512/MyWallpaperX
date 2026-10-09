import Foundation
import simd

/// Immutable light publication consumed by lit material producers in the
/// shared frame. It carries scene data only; it owns no renderer or targets.
struct SceneLightSnapshot {
    static let maximumLightCount = 4

    struct Directional {
        var layerID: Int? = nil
        var castsShadow: Bool = false
        let directionTowardLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
    }

    struct Point {
        var layerID: Int? = nil
        var castsShadow: Bool = false
        /// Official splits point-light kinds by consumer (own-fixture
        /// black-box, 2026-10-06): `lpoint` illuminates static models only,
        /// `point` illuminates 2D lit images only.
        var illuminatesStaticModels: Bool = true
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
    }

    struct Spot {
        var layerID: Int? = nil
        var castsShadow: Bool = false
        let position: SIMD3<Float>
        let directionFromLight: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
        let innerConeCosine: Float
        let outerConeCosine: Float
        /// Authored off-axis angle, rather than the complete cone opening.
        let outerConeDegrees: Float
    }

    enum ShadowLight {
        case directional(Directional)
        case spot(Spot)
        case point(Point)

        var layerID: Int? {
            switch self {
            case .directional(let light): light.layerID
            case .spot(let light): light.layerID
            case .point(let light): light.layerID
            }
        }
    }

    /// Preserve directional and spot priority before complete point atlases.
    /// Each group keeps this snapshot's already-admitted author order.
    var shadowLights: [ShadowLight] {
        var result: [ShadowLight] = []
        if let light = directional.first(where: { $0.castsShadow }) {
            result.append(.directional(light))
        }
        result.append(contentsOf: spot.filter { $0.castsShadow }.map { .spot($0) })
        result.append(contentsOf: point.filter {
            $0.castsShadow && $0.illuminatesStaticModels
        }.map { .point($0) })
        return result
    }

    let ambient: SIMD3<Float>
    let skylight: SIMD3<Float>
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
        let resolvedLayersByID = layersByID ?? Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        let lightLayerIDs = candidateLayerIDs ?? orderedLightLayerIDs(
            descriptor: descriptor,
            layersByID: resolvedLayersByID
        )
        let visibleLayerIDs = visibleLayerIDs ?? dynamicSnapshot.map {
            SceneLayerVisibility.visibleLayerIDs(
                in: descriptor, layersByID: resolvedLayersByID, snapshot: $0
            )
        } ?? SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let lightLayers = lightLayerIDs.compactMap { resolvedLayersByID[$0] }
        var directionalLights: [Directional] = []
        var pointLights: [Point] = []
        var spotLights: [Spot] = []
        var acceptedCount = 0
        var overflowCount = 0
        for layer in lightLayers {
            // The same current visibility authority gates direct light,
            // shadow publication and the model-light budget. Launch candidates
            // remain complete so a later show can use its prepared producers.
            guard visibleLayerIDs.contains(layer.id),
                  let frame = worldFramesByLayerID[layer.id] else { continue }
            // general.lightconfig gates the STATIC-MODEL light classes per
            // scene: an absent author field leaves directional/lpoint/spot
            // inert for models in the official client (own-fixture N-series
            // and SP1/SP2 black-box, 2026-10-06). The 2D lit-image consumer
            // is NOT config-gated — `point` lights illuminate images with no
            // lightconfig at all (corpus 2815826216 and the IMG6 own-fixture
            // pair) — so 2D-only `point` lights always enter the snapshot.
            // They bypass the static-model budget: the four-slot model budget
            // stays owned by model lights. The 2D packer truncates its own
            // point+spot payload to the four ABI slots in authored order.
            let isImageOnlyPointLight = layer.pointLight?.kind == "point"
            let admitted: Bool
            if isImageOnlyPointLight {
                admitted = true
            } else if layer.pointLight != nil {
                admitted = descriptor.lighting?.lightClasses.point ?? false
            } else if layer.directionalLight != nil {
                admitted = descriptor.lighting?.lightClasses.directional ?? false
            } else if layer.spotLight != nil {
                admitted = descriptor.lighting?.lightClasses.spot ?? false
            } else {
                admitted = true
            }
            guard admitted else { continue }
            let dynamicColor = dynamicLayerColors[layer.id]
            let intensity = dynamicSnapshot.flatMap {
                SceneDynamicLayerValues.lightIntensity(
                    layerID: layer.id,
                    authoredValue: authoredIntensity(layer),
                    snapshot: $0
                )
            } ?? authoredIntensity(layer)
            if isImageOnlyPointLight, let light = point(
                layer: layer, frame: frame, dynamicColor: dynamicColor,
                intensity: intensity
            ) {
                pointLights.append(light)
                continue
            }
            if let light = directional(
                layer: layer, frame: frame,
                dynamicColor: dynamicColor,
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
        #if DEBUG
        if ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_LIGHT_TRACE"] == "1" {
            struct LightTraceThrottle {
                static var count: Int = 0
                static var lock = NSLock()
            }
            LightTraceThrottle.lock.lock()
            LightTraceThrottle.count += 1
            let traceThisCall = LightTraceThrottle.count <= 3
                || LightTraceThrottle.count % 120 == 0
            LightTraceThrottle.lock.unlock()
            if traceThisCall {
                for light in directionalLights {
                    NSLog("MWX DEBUG LIGHT TRACE: kind=directional layer=%d direction=%.4f %.4f %.4f intensity=%.3f",
                        light.layerID ?? -1,
                        light.directionTowardLight.x, light.directionTowardLight.y,
                        light.directionTowardLight.z, light.intensity)
                }
                for light in pointLights {
                    NSLog("MWX DEBUG LIGHT TRACE: kind=point layer=%d position=%.4f %.4f %.4f radius=%.3f intensity=%.3f",
                        light.layerID ?? -1,
                        light.position.x, light.position.y, light.position.z,
                        light.radius, light.intensity)
                }
            }
        }
        #endif
        let fog = descriptor.lighting?.distanceFog
        // An unauthored ambient stays black: official renders gated-away or
        // lightless scenes black for lit static models (own-fixture N-series
        // and ambient-omitted ADEF probes, 2026-10-06), and every corpus
        // sample that lights models authors ambient or skylight, so the
        // historical white unlit default is retired.
        return SceneLightSnapshot(
            ambient: color(descriptor.lighting?.ambientColorRGB),
            skylight: color(descriptor.lighting?.skylightColorRGB),
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
        // Light emission follows the same world-frame +X axis as a spot.
        // Direct lighting and shadows consume its opposite, toward the light.
        // Parent transforms, typed angles and orthographic reflection are
        // already resolved by the shared world-frame owner.
        guard let definition = layer.directionalLight,
              let direction = normalized(-SIMD3(
                  frame.columns.0.x, frame.columns.0.y, frame.columns.0.z
              )),
              let intensity,
              intensity.isFinite, intensity >= 0 else { return nil }
        return Directional(
            layerID: layer.id, castsShadow: definition.shadowCastIntent == .enabled,
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
            layerID: layer.id, castsShadow: definition.castsShadow == true,
            illuminatesStaticModels: definition.kind != "point",
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
              let direction = normalized(SIMD3(
                  frame.columns.0.x,
                  frame.columns.0.y,
                  frame.columns.0.z
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
        // Own-fixture official black-box cones (2026-10-09) establish that
        // authored inner/outer values measure away from the light axis.
        let degreesToRadians = Float.pi / 180
        return Spot(
            layerID: layer.id, castsShadow: definition.castsShadow == true,
            position: position,
            directionFromLight: direction,
            color: dynamicColor
                ?? color(definition.colorRGB, fallback: SIMD3(1, 1, 1)),
            intensity: intensity,
            radius: radius,
            innerConeCosine: cos(innerCone * degreesToRadians),
            outerConeCosine: cos(outerCone * degreesToRadians),
            outerConeDegrees: outerCone
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
