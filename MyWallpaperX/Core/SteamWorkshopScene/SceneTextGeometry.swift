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

    nonisolated static func pointSizeInPixels(_ authoredPointSize: Float) -> Float {
        // WE stores text point size at one quarter of the rasterized glyph size.
        min(max((authoredPointSize * 4).rounded(), 1), 1_024)
    }

    nonisolated static func expandedSize(
        authoredSize: [Float]?,
        padding: Float
    ) -> [Float]? {
        guard let authoredSize, authoredSize.count >= 2 else { return nil }
        let inset = max(0, padding) * 2
        return [max(0, authoredSize[0]) + inset, max(0, authoredSize[1]) + inset]
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
