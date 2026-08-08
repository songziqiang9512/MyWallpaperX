import simd

enum SceneLayerCursorGeometry {
    static func layerUV(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD2<Float>? {
        guard let local = layerPoint(
            mouseNormalized: mouseNormalized,
            modelViewProjection: modelViewProjection
        ) else { return nil }
        let uv = SIMD2(local.x + 0.5, 0.5 - local.y)
        return uv.x.isFinite && uv.y.isFinite ? uv : nil
    }

    static func layerPoint(
        mouseNormalized: SIMD2<Float>,
        modelViewProjection: simd_float4x4
    ) -> SIMD3<Float>? {
        guard let inverse = inverseModelViewProjection(modelViewProjection) else {
            return nil
        }
        guard let near = localPoint(
            SIMD4(mouseNormalized.x, mouseNormalized.y, 0, 1),
            inverse: inverse
        ), let far = localPoint(
            SIMD4(mouseNormalized.x, mouseNormalized.y, 1, 1),
            inverse: inverse
        ) else {
            return nil
        }
        let direction = far - near
        guard direction.z.isFinite, abs(direction.z) > 1e-8 else { return nil }
        let distance = -near.z / direction.z
        guard distance.isFinite else { return nil }
        let local = near + direction * distance
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }

    static func inverseModelViewProjection(
        _ modelViewProjection: simd_float4x4
    ) -> simd_float4x4? {
        let determinant = simd_determinant(modelViewProjection)
        guard determinant.isFinite, abs(determinant) > 1e-8 else { return nil }
        let inverse = simd_inverse(modelViewProjection)
        let columns = [
            inverse.columns.0, inverse.columns.1,
            inverse.columns.2, inverse.columns.3,
        ]
        guard columns.allSatisfy({ column in
            column.x.isFinite && column.y.isFinite
                && column.z.isFinite && column.w.isFinite
        }) else { return nil }
        return inverse
    }

    private static func localPoint(
        _ point: SIMD4<Float>,
        inverse: simd_float4x4
    ) -> SIMD3<Float>? {
        let projected = inverse * point
        guard projected.w.isFinite, abs(projected.w) > 1e-8 else { return nil }
        let local = SIMD3(projected.x, projected.y, projected.z) / projected.w
        return local.x.isFinite && local.y.isFinite && local.z.isFinite ? local : nil
    }
}
