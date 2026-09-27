import simd

/// Source-less quads use equal world units on both texture axes. The authored
/// canvas height sets their unit extent; layer scale and shader control points
/// remain responsible for the author's shape. Canvas aspect must not stretch it.
enum SceneDirectDrawOutputGeometry {
    static func baseExtent(canvasSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard canvasSize.x.isFinite, canvasSize.y.isFinite,
              canvasSize.x > 0, canvasSize.y > 0 else { return nil }
        return SIMD2(repeating: canvasSize.y)
    }

    static func modelMatrix(
        worldFrame: simd_float4x4,
        parallaxOffset: SIMD2<Float>,
        canvasSize: SIMD2<Float>
    ) -> simd_float4x4? {
        guard let extent = baseExtent(canvasSize: canvasSize),
              worldFrame.columns.0.allFinite,
              worldFrame.columns.1.allFinite,
              worldFrame.columns.2.allFinite,
              worldFrame.columns.3.allFinite,
              parallaxOffset.x.isFinite, parallaxOffset.y.isFinite else {
            return nil
        }
        return SceneMatrix.translation(SIMD3(parallaxOffset.x, parallaxOffset.y, 0))
            * worldFrame
            * SceneMatrix.scale(SIMD3(extent.x, -extent.y, 1))
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}
