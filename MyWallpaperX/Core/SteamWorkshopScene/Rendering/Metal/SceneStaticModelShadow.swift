import Metal
import simd

/// Light projection uses actual prepared vertex bounds and current world transforms.
/// It is independent of the scene camera, so offscreen casters remain represented.
struct SceneDirectionalShadowProjection {
    let worldToClip: simd_float4x4
    let depthBias: Float

    static func make(
        bounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)],
        directionTowardLight: SIMD3<Float>, resolution: Int
    ) -> Self? {
        let toward = SIMD3<Double>(directionTowardLight)
        let magnitude = simd_length(toward)
        guard magnitude.isFinite, magnitude > 0, !bounds.isEmpty else { return nil }
        let z = -toward / magnitude
        let reference = abs(z.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        var minimum = SIMD3<Double>(repeating: .infinity)
        var maximum = SIMD3<Double>(repeating: -.infinity)
        for item in bounds {
            for corner in 0..<8 {
                let local = SIMD4<Float>(
                    corner & 1 == 0 ? item.minimum.x : item.maximum.x,
                    corner & 2 == 0 ? item.minimum.y : item.maximum.y,
                    corner & 4 == 0 ? item.minimum.z : item.maximum.z, 1)
                let transformed = item.world * local
                let point = SIMD3<Double>(Double(transformed.x), Double(transformed.y), Double(transformed.z))
                guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
                let light = SIMD3(simd_dot(point, x), simd_dot(point, y), simd_dot(point, z))
                minimum = simd_min(minimum, light); maximum = simd_max(maximum, light)
            }
        }
        let span = maximum - minimum
        let scale = max(simd_reduce_max(span), 0.0001)
        let texel = max(span.x, span.y, scale * 0.001) / Double(resolution)
        let padding = max(texel * 2, scale * 0.001)
        minimum -= SIMD3(repeating: padding)
        maximum += SIMD3(repeating: padding)
        let extent = maximum - minimum
        let rowX = SIMD4<Double>(x * (2 / extent.x), -(maximum.x + minimum.x) / extent.x)
        let rowY = SIMD4<Double>(y * (2 / extent.y), -(maximum.y + minimum.y) / extent.y)
        let rowZ = SIMD4<Double>(z / extent.z, -minimum.z / extent.z)
        let matrix = simd_double4x4(rows: [rowX, rowY, rowZ, SIMD4(0, 0, 0, 1)])
        let result = simd_float4x4(columns: (SIMD4<Float>(matrix.columns.0),
            SIMD4<Float>(matrix.columns.1), SIMD4<Float>(matrix.columns.2), SIMD4<Float>(matrix.columns.3)))
        guard (0..<4).allSatisfy({ column in
            (0..<4).allSatisfy { result[column][$0].isFinite }
        }) else { return nil }
        // Receiver-plane correction handles the filter footprint. Leave only
        // Float32 transform/interpolation/compare rounding tolerance, scaled
        // by the fragment's depth arithmetic magnitude in the shader.
        return Self(worldToClip: result, depthBias: 8 * Float.ulpOfOne)
    }
}

/// Finite perspective XY with fragment-written forward axial depth. The
/// relative position is formed on the GPU before applying this rotation.
struct SceneSpotShadowProjection {
    let worldToLight: simd_float4x4
    let position: SIMD3<Float>
    let tanHalfAngle: Float
    let radius: Float
    let outerCosine: Float
    let depthBias: Float

    static func make(light: SceneLightSnapshot.Spot) -> Self? {
        let z = simd_normalize(SIMD3<Double>(light.directionFromLight))
        let reference = abs(z.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        let authored = Double(light.outerConeDegrees) * Double.pi / 360
        let quantized = acos(Double(light.outerConeCosine))
        let tangent = Float(tan(max(authored, quantized)))
        let matrix = simd_double4x4(rows: [SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(0, 0, 0, 1)])
        let transform = simd_float4x4(columns: (SIMD4<Float>(matrix.columns.0),
            SIMD4<Float>(matrix.columns.1), SIMD4<Float>(matrix.columns.2), SIMD4<Float>(matrix.columns.3)))
        // The snapshot has admitted finite authored values, but extreme cone
        // angles can underflow or overflow their Float projection coefficients.
        guard tangent.isFinite, tangent > 0, (1 / tangent).isFinite,
              (0..<3).allSatisfy({ column in
                  (0..<3).allSatisfy { transform[column][$0].isFinite }
              }) else { return nil }
        return Self(worldToLight: transform, position: light.position, tanHalfAngle: tangent,
            radius: max(light.radius, 1e-4), outerCosine: light.outerConeCosine,
            depthBias: 8 * Float.ulpOfOne)
    }
}

enum SceneStaticModelShadowProjection {
    case directional(SceneDirectionalShadowProjection)
    case spot(SceneSpotShadowProjection)
}

struct SceneStaticModelShadow {
    let texture: MTLTexture
    let frameEpoch: UInt64
    let generation: UInt64
    let lightLayerID: Int
    let projection: SceneStaticModelShadowProjection
    let commandBuffer: MTLCommandBuffer
}
