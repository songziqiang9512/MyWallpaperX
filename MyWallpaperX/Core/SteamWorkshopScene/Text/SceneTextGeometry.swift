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

    // WE 的 `pointsize` 是 300 DPI 下的磅值（lib.sceneScript.d.ts 的 ITextLayer：
    // "Size of the font in points for 300 DPI"），换算到像素就是 300/72 = 25/6。
    // 随包 `dino_run` 用同一字体 assets/fonts/Segment7Standard.otf 排同一内容 "00000"：
    // pointsize 64 -> 266.667 px 时排版宽正好 780、pointsize 32 -> 133.333 px 时正好 390，
    // 与作者 size 的 780/390 逐位相符；上限 1_024 是纹理边长保护，不是官方合同。
    nonisolated static func pointSizeInPixels(_ authoredPointSize: Float) -> Float {
        min(max(authoredPointSize * 300 / 72, 1), 1_024)
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
        // Wallpaper Engine's `padding` grows the complete text geometry by the
        // authored amount. It is not a per-edge inset: a value of 32 contributes
        // 16 pixels on each side. Treating it as 32 per edge makes the drawable
        // width 32 pixels too narrow and can change the last accepted row even
        // when the authored outer size is otherwise exact.
        let scaledPadding = max(0, padding) * scale * 0.5
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
