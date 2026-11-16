import Metal
import simd

/// Fit the existing light map to visible receivers without dropping offscreen
/// occluders that can cast into that region.
struct SceneDirectionalShadowProjection {
    let worldToClip: simd_float4x4
    let depthBias: Float

    static func make(
        bounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4)],
        receiverBounds: [(minimum: SIMD3<Float>, maximum: SIMD3<Float>, world: simd_float4x4,
                          clip: simd_float4x4?)],
        directionTowardLight: SIMD3<Float>, resolution: Int
    ) -> Self? {
        let toward = SIMD3<Double>(directionTowardLight)
        let magnitude = simd_length(toward)
        guard magnitude.isFinite, magnitude > 0, !bounds.isEmpty else { return nil }
        let z = -toward / magnitude
        let reference = abs(z.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        let light = simd_double4x4(rows: [SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(0, 0, 0, 1)])
        var receiverMinimum = SIMD3<Double>(repeating: .infinity)
        var receiverMaximum = SIMD3<Double>(repeating: -.infinity)
        for item in receiverBounds {
            guard let region = receiverRegion(minimum: item.minimum, maximum: item.maximum,
                world: item.world, clip: item.clip, light: light) else { continue }
            receiverMinimum = simd_min(receiverMinimum, region.minimum)
            receiverMaximum = simd_max(receiverMaximum, region.maximum)
        }
        guard receiverMinimum.x <= receiverMaximum.x else { return nil }
        var minimum = SIMD3<Double>(repeating: .infinity)
        var maximum = SIMD3<Double>(repeating: -.infinity)
        for item in bounds {
            guard let region = fullRegion(minimum: item.minimum, maximum: item.maximum,
                world: item.world, light: light) else { return nil }
            let overlapMinimum = simd_max(region.minimum, receiverMinimum)
            let overlapMaximum = simd_min(region.maximum, receiverMaximum)
            guard overlapMinimum.x <= overlapMaximum.x, overlapMinimum.y <= overlapMaximum.y,
                  region.minimum.z <= receiverMaximum.z else { continue }
            minimum = simd_min(minimum, SIMD3(overlapMinimum.x, overlapMinimum.y, region.minimum.z))
            maximum = simd_max(maximum, SIMD3(overlapMaximum.x, overlapMaximum.y, receiverMaximum.z))
        }
        guard minimum.x <= maximum.x else { return nil }
        minimum.z = min(minimum.z, receiverMinimum.z)
        let span = maximum - minimum
        let xyScale = max(span.x, span.y, 0.0001)
        let rasterResolution = Double(resolution)
        let xyPadding = max(xyScale * 2 / rasterResolution, xyScale * 0.001)
        let fitX = stabilizedAxis(span: span.x, center: (maximum.x + minimum.x) * 0.5,
            padding: xyPadding, resolution: rasterResolution)
        let fitY = stabilizedAxis(span: span.y, center: (maximum.y + minimum.y) * 0.5,
            padding: xyPadding, resolution: rasterResolution)
        let zPadding = max(span.z, 0.0001) * 0.001
        minimum.z -= zPadding
        maximum.z += zPadding
        let depthExtent = maximum.z - minimum.z
        let rowX = SIMD4<Double>(x * (2 / fitX.extent), -2 * fitX.center / fitX.extent)
        let rowY = SIMD4<Double>(y * (2 / fitY.extent), -2 * fitY.center / fitY.extent)
        let rowZ = SIMD4<Double>(z / depthExtent, -minimum.z / depthExtent)
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

    private static func stabilizedAxis(span: Double, center: Double, padding: Double,
        resolution: Double
    ) -> (extent: Double, center: Double) {
        // Three texels leave the filter's 2.5-texel border after center rounding.
        let minimumExtent = max(span + 2 * padding, span / (1 - 6 / resolution))
        let extent = exp2(ceil(log2(minimumExtent) * 16) / 16)
        let texel = extent / resolution
        return (extent, (center / texel).rounded() * texel)
    }

    private static func fullRegion(minimum: SIMD3<Float>, maximum: SIMD3<Float>,
        world: simd_float4x4, light: simd_double4x4
    ) -> (minimum: SIMD3<Double>, maximum: SIMD3<Double>)? {
        var low = SIMD3<Double>(repeating: .infinity)
        var high = SIMD3<Double>(repeating: -.infinity)
        for corner in 0..<8 {
            let transformed = world * SIMD4(
                corner & 1 == 0 ? minimum.x : maximum.x,
                corner & 2 == 0 ? minimum.y : maximum.y,
                corner & 4 == 0 ? minimum.z : maximum.z, 1)
            guard transformed.x.isFinite, transformed.y.isFinite, transformed.z.isFinite else { return nil }
            let point = light * SIMD4<Double>(transformed)
            let xyz = SIMD3(point.x, point.y, point.z)
            low = simd_min(low, xyz); high = simd_max(high, xyz)
        }
        return (low, high)
    }

    private static func receiverRegion(minimum: SIMD3<Float>, maximum: SIMD3<Float>,
        world: simd_float4x4, clip: simd_float4x4?, light: simd_double4x4
    ) -> (minimum: SIMD3<Double>, maximum: SIMD3<Double>)? {
        guard let clip else {
            return fullRegion(minimum: minimum, maximum: maximum, world: world, light: light)
        }
        let worldDouble = simd_double4x4(columns: (SIMD4<Double>(world.columns.0),
            SIMD4<Double>(world.columns.1), SIMD4<Double>(world.columns.2), SIMD4<Double>(world.columns.3)))
        let clipDouble = simd_double4x4(columns: (SIMD4<Double>(clip.columns.0),
            SIMD4<Double>(clip.columns.1), SIMD4<Double>(clip.columns.2), SIMD4<Double>(clip.columns.3)))
        let localToClip = clipDouble * worldDouble
        let clipToLocal = localToClip.inverse
        var frustum: [SIMD3<Double>] = []
        frustum.reserveCapacity(8)
        for corner in 0..<8 {
            let point = clipToLocal * SIMD4<Double>(corner & 1 == 0 ? -1 : 1,
                corner & 2 == 0 ? -1 : 1, corner & 4 == 0 ? 0 : 1, 1)
            let xyz = SIMD3(point.x, point.y, point.z) / point.w
            // Infinite/degenerate camera domains keep conservative coverage.
            guard xyz.x.isFinite, xyz.y.isFinite, xyz.z.isFinite else {
                return fullRegion(minimum: minimum, maximum: maximum, world: world, light: light)
            }
            frustum.append(xyz)
        }
        let localMinimum = SIMD3<Double>(minimum), localMaximum = SIMD3<Double>(maximum)
        let localToLight = light * worldDouble
        var low = SIMD3<Double>(repeating: .infinity)
        var high = SIMD3<Double>(repeating: -.infinity)
        func include(_ point: SIMD3<Double>) {
            let projected = localToLight * SIMD4(point, 1)
            let xyz = SIMD3(projected.x, projected.y, projected.z)
            low = simd_min(low, xyz); high = simd_max(high, xyz)
        }
        // Both edge sets are needed when either convex volume contains the
        // other, or when their faces intersect without containing a corner.
        for corner in 0..<8 {
            let a = SIMD3(corner & 1 == 0 ? localMinimum.x : localMaximum.x,
                corner & 2 == 0 ? localMinimum.y : localMaximum.y,
                corner & 4 == 0 ? localMinimum.z : localMaximum.z)
            for axis in 0..<3 where corner & (1 << axis) == 0 {
                var b = a; b[axis] = localMaximum[axis]
                if let interval = clipInterval(localToClip * SIMD4(a, 1), localToClip * SIMD4(b, 1)) {
                    include(a + (b - a) * interval.lowerBound)
                    include(a + (b - a) * interval.upperBound)
                }
                let c = frustum[corner], d = frustum[corner | (1 << axis)]
                if let interval = boxInterval(c, d, minimum: localMinimum, maximum: localMaximum) {
                    include(c + (d - c) * interval.lowerBound)
                    include(c + (d - c) * interval.upperBound)
                }
            }
        }
        return low.x <= high.x ? (low, high) : nil
    }

    private static func clipInterval(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> ClosedRange<Double>? {
        var lower = 0.0, upper = 1.0
        for axis in 0..<3 {
            for side in 0..<2 {
                let start = side == 0 ? (axis == 2 ? a.z : a.w + a[axis]) : a.w - a[axis]
                let end = side == 0 ? (axis == 2 ? b.z : b.w + b[axis]) : b.w - b[axis]
                if start < 0, end < 0 { return nil }
                if start < 0 { lower = max(lower, start / (start - end)) }
                if end < 0 { upper = min(upper, start / (start - end)) }
                if lower > upper { return nil }
            }
        }
        return lower...upper
    }

    private static func boxInterval(_ a: SIMD3<Double>, _ b: SIMD3<Double>,
        minimum: SIMD3<Double>, maximum: SIMD3<Double>
    ) -> ClosedRange<Double>? {
        var lower = 0.0, upper = 1.0
        for axis in 0..<3 {
            let delta = b[axis] - a[axis]
            if delta == 0 {
                if a[axis] < minimum[axis] || a[axis] > maximum[axis] { return nil }
            } else {
                let first = (minimum[axis] - a[axis]) / delta
                let second = (maximum[axis] - a[axis]) / delta
                lower = max(lower, min(first, second)); upper = min(upper, max(first, second))
                if lower > upper { return nil }
            }
        }
        return lower...upper
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
        // The snapshot admits direct-light cones up to 180 authored degrees.
        // This single forward perspective map cannot cover a hemisphere or
        // wider cone; omit only its optional shadow, preserving direct light.
        guard light.outerConeDegrees < 90 else { return nil }
        let z = simd_normalize(SIMD3<Double>(light.directionFromLight))
        let reference = abs(z.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        let authored = Double(light.outerConeDegrees) * Double.pi / 180
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

/// Six axis faces cover the complete finite point-light sphere. Each basis
/// has right cross up == forward; Metal's viewport supplies the Y inversion.
struct ScenePointShadowProjection {
    let position: SIMD3<Float>
    let radius: Float
    let depthBias: Float

    init(light: SceneLightSnapshot.Point) {
        position = light.position
        radius = max(light.radius, 1e-4)
        depthBias = 8 * Float.ulpOfOne
    }

    static let worldToFaces: [simd_float4x4] = [
        (SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 0, 0)),
        (SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 1, 0), SIMD3<Float>(-1, 0, 0)),
        (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)),
        (SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, -1, 0)),
        (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)),
        (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, -1))
    ].map { right, up, forward in
        simd_float4x4(rows: [SIMD4(right, 0), SIMD4(up, 0), SIMD4(forward, 0), SIMD4(0, 0, 0, 1)])
    }
}

enum SceneStaticModelShadowProjection {
    case directional(SceneDirectionalShadowProjection)
    case spot(SceneSpotShadowProjection)
    case point(ScenePointShadowProjection)

    var faceCount: Int {
        if case .point = self { return 6 }
        return 1
    }

    var atlasColumns: Int {
        if case .point = self { return 3 }
        return 1
    }

    var atlasRows: Int { faceCount / atlasColumns }

    func viewport(face: Int, width: Int, height: Int) -> MTLViewport {
        let faceWidth = width / atlasColumns, faceHeight = height / atlasRows
        return MTLViewport(originX: Double(face % atlasColumns * faceWidth),
            originY: Double(face / atlasColumns * faceHeight), width: Double(faceWidth),
            height: Double(faceHeight), znear: 0, zfar: 1)
    }
}

struct SceneStaticModelShadow {
    let texture: MTLTexture
    let frameEpoch: UInt64
    let generation: UInt64
    let lightLayerID: Int
    let projection: SceneStaticModelShadowProjection
    let commandBuffer: MTLCommandBuffer
}
