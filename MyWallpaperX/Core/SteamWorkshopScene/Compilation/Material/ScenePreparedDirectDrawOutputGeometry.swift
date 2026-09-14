import Foundation
import simd

/// Immutable geometry facts carried from Program preparation into the frame.
/// Values remain independent of a sample, layer, effect name, path, or hash.
nonisolated struct ScenePreparedDirectDrawOutputGeometry: Equatable {
    /// The source-less quad unit used by stock authoring presets is half the
    /// authored canvas before the layer's authored scale.
    let canvasExtentScale: Float
    /// A source-proven normalized top inset. Moving the carrier by this amount
    /// keeps its authored size while aligning the active region to the
    /// carrier's original top edge.
    let normalizedContentTopInset: Float

    static let centeredHalfCanvas = Self(
        canvasExtentScale: 0.5,
        normalizedContentTopInset: 0
    )

    static func topAlignedHalfCanvas(
        normalizedPerspectivePoints points: [SIMD2<Float>]
    ) -> Self? {
        guard points.count == 4,
              points.allSatisfy({ point in
                  point.x.isFinite && point.y.isFinite
                      && (0 ... 1).contains(point.x)
                      && (0 ... 1).contains(point.y)
              }), let top = points.map(\.y).min(),
              (0 ... 0.5).contains(top) else {
            return nil
        }
        return .init(
            canvasExtentScale: 0.5,
            normalizedContentTopInset: top
        )
    }
}
