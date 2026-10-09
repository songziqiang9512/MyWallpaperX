import Foundation

nonisolated enum SceneTextGeometry {
    struct RasterLayout: Equatable {
        let width: Int
        let height: Int
        let scale: Float
        let padding: Float
        let contentWidth: Float
        let contentHeight: Float
    }

    // Authored points use 300 DPI. Quantize the prepared font once to whole
    // pixels; fixed-client width probes at 24/28/29/36 points distinguish this
    // from fractional CoreText sizing. Raster downsampling remains continuous.
    // The 1...1024 budget is project policy, not an official size limit.
    nonisolated static func pointSizeInPixels(_ authoredPointSize: Float) -> Float {
        floor(min(max(authoredPointSize * 300 / 72, 1), 1_024))
    }

    nonisolated static func rasterLayout(
        renderSize: [Float]?,
        padding: Float,
        maxDimension: Int
    ) -> RasterLayout? {
        guard let renderSize, renderSize.count >= 2 else { return nil }
        let sourceWidth = max(1, renderSize[0])
        let sourceHeight = max(1, renderSize[1])
        let scale = min(1, Float(maxDimension) / max(sourceWidth, sourceHeight))
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))
        // The prepared extent includes a full padding margin on each edge.
        // Raster placement and the layer pivot consume the same per-edge value.
        let scaledPadding = max(0, padding) * scale
        return RasterLayout(
            width: width,
            height: height,
            scale: scale,
            padding: scaledPadding,
            contentWidth: max(1, Float(width) - scaledPadding * 2),
            contentHeight: max(1, Float(height) - scaledPadding * 2)
        )
    }
}
