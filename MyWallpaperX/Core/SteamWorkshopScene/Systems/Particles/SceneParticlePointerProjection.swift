import simd

enum SceneParticlePointerProjection {
    static func localPosition(
        mouseNormalized: SIMD2<Float>,
        isInside: Bool,
        modelViewProjection: simd_float4x4
    ) -> SIMD3<Double>? {
        guard isInside, let point = SceneLayerCursorGeometry.layerPoint(
            mouseNormalized: mouseNormalized,
            modelViewProjection: modelViewProjection
        ) else { return nil }
        return SIMD3(Double(point.x), Double(point.y), Double(point.z))
    }
}
