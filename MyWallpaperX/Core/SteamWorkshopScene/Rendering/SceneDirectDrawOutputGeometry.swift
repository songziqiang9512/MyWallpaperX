import simd

/// World-space output carrier for a prepared transparent direct-draw product.
///
/// A direct-draw layer has no imported image `size`. Its prepared contract
/// supplies both the stock half-canvas carrier scale and any source-proven
/// normalized content inset. The author-provided layer transform then places
/// that unchanged-size carrier in the world.
enum SceneDirectDrawOutputGeometry {
    typealias Contract = ScenePreparedDirectDrawOutputGeometry

    static func baseExtent(
        canvasSize: SIMD2<Float>,
        contract: Contract
    ) -> SIMD2<Float>? {
        guard canvasSize.x.isFinite,
              canvasSize.y.isFinite,
              canvasSize.x > 0,
              canvasSize.y > 0,
              contract.canvasExtentScale.isFinite,
              contract.canvasExtentScale > 0,
              contract.canvasExtentScale <= 1 else {
            return nil
        }
        return canvasSize * contract.canvasExtentScale
    }

    static func modelMatrix(
        worldFrame: simd_float4x4,
        parallaxOffset: SIMD2<Float>,
        canvasSize: SIMD2<Float>,
        contract: Contract
    ) -> simd_float4x4? {
        guard let extent = baseExtent(
                  canvasSize: canvasSize,
                  contract: contract
              ),
              worldFrame.columns.0.allFinite,
              worldFrame.columns.1.allFinite,
              worldFrame.columns.2.allFinite,
              worldFrame.columns.3.allFinite,
              parallaxOffset.x.isFinite,
              parallaxOffset.y.isFinite,
              contract.normalizedContentTopInset.isFinite,
              (0 ... 0.5).contains(
                  contract.normalizedContentTopInset
              ) else {
            return nil
        }
        return SceneMatrix.translation(
            SIMD3(parallaxOffset.x, parallaxOffset.y, 0)
        )
            * worldFrame
            * SceneMatrix.scale(SIMD3(1, -1, 1))
            * SceneMatrix.scale(SIMD3(extent.x, extent.y, 1))
            * SceneMatrix.translation(SIMD3(
                0,
                contract.normalizedContentTopInset,
                0
            ))
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
