import simd

/// Shared transparent direct-draw quad geometry.
///
/// Stock presets and real projects omit `size` while keeping authored scale
/// near 2 across 256-, 2560-, and 3840-wide canvases. This bounded profile
/// therefore treats the unscaled quad as half of the authored canvas. The
/// effect's perspective points remain texture-space inputs and never alter
/// this layer-space extent.
enum SceneDirectDrawQuadGeometry {
    static func baseExtent(
        canvasSize: SIMD2<Float>
    ) -> SIMD2<Float>? {
        guard canvasSize.x.isFinite,
              canvasSize.y.isFinite,
              canvasSize.x > 0,
              canvasSize.y > 0 else {
            return nil
        }
        return canvasSize * 0.5
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
              parallaxOffset.x.isFinite,
              parallaxOffset.y.isFinite else {
            return nil
        }
        return SceneMatrix.translation(
            SIMD3(parallaxOffset.x, parallaxOffset.y, 0)
        )
            * worldFrame
            * SceneMatrix.scale(SIMD3(1, -1, 1))
            * SceneMatrix.scale(SIMD3(extent.x, extent.y, 1))
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
