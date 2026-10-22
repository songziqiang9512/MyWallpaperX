import CoreText
import Foundation

/// Width and row limits share one prepared CoreText bound policy. Disabled limits
/// ignore the editor's saved default maxwidth/maxrows values.
nonisolated enum SceneTextRowLimit {
    enum LineBounds {
        case glyphPath
        case typographic

        var options: CTLineBoundsOptions {
            self == .glyphPath ? .useGlyphPathBounds : []
        }
    }

    private static let ellipsis = "…"

    /// Some native font/paragraph combinations return finite sentinel origins
    /// (-DBL_MAX) while retaining a positive ink size. Such an interval has no
    /// representable right/top edge and cannot place glyphs in any raster.
    /// Qualify the actual content before truncation; keep one policy through
    /// row selection, measurement and drawing, including dynamic updates.
    static func lineBounds(text: String, font: CTFont, useEllipsis: Bool) -> LineBounds {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String):
                paragraphStyle(alignment: .natural, lineBounds: .glyphPath)
        ]
        let attributed = NSAttributedString(
            string: useEllipsis ? text + ellipsis : text, attributes: attributes
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        // Empty/whitespace-only ink is legal and must not acquire a fallback.
        if bounds.isNull { return .glyphPath }
        let usableX = bounds.width == 0
            || (bounds.minX.isFinite && bounds.maxX.isFinite && bounds.maxX > bounds.minX)
        let usableY = bounds.height == 0
            || (bounds.minY.isFinite && bounds.maxY.isFinite && bounds.maxY > bounds.minY)
        return usableX && usableY ? .glyphPath : .typographic
    }

    static func paragraphStyle(
        alignment: CTTextAlignment, lineBounds: LineBounds
    ) -> CTParagraphStyle {
        var alignment = alignment
        var lineBreak = CTLineBreakMode.byWordWrapping
        var bounds = lineBounds.options
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreak) { lineBreakPointer in
                withUnsafePointer(to: &bounds) { boundsPointer in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                        CTParagraphStyleSetting(spec: .lineBreakMode,
                            valueSize: MemoryLayout<CTLineBreakMode>.size, value: lineBreakPointer),
                        CTParagraphStyleSetting(spec: .lineBoundsOptions,
                            valueSize: MemoryLayout<CTLineBoundsOptions>.size, value: boundsPointer)
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
    }

    /// `maxwidth` 的单位是像素（lib.sceneScript.d.ts 的 ITextLayer："Max width in
    /// pixels"），所以要和 padding 一样乘上栅格降采样比例；上界是准备阶段按同一
    /// width/row limit 测得的内容宽度，不是保存的作者 size。
    nonisolated static func wrapWidth(
        contentWidth: CGFloat,
        style: SceneTextDescriptor,
        scale: Float
    ) -> CGFloat {
        guard style.limitWidth, style.maxWidth > 0 else { return contentWidth }
        return min(contentWidth, CGFloat(style.maxWidth) * CGFloat(max(0, scale)))
    }

    /// Earlier rows use word wrapping; the final permitted row fills with
    /// complete glyph clusters before truncation. CoreText preserves hard line
    /// breaks in both modes. Ellipsis backs off composed characters to fit.
    nonisolated static func limitedText(
        _ text: String,
        style: SceneTextDescriptor,
        attributes: CFDictionary,
        wrapWidth: CGFloat,
        lineBounds: LineBounds
    ) -> String {
        guard style.limitRows, wrapWidth > 0 else { return text }
        let source = text as NSString
        guard source.length > 0,
              let attributed = CFAttributedStringCreate(
                  kCFAllocatorDefault, text as CFString, attributes
              )
        else { return text }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let maxRows = max(1, style.maxRows)
        var rowStart = 0
        var index = 0
        for row in 0 ..< maxRows {
            guard index < source.length else { break }
            let count = row == maxRows - 1
                ? CTTypesetterSuggestClusterBreak(typesetter, index, Double(wrapWidth))
                : CTTypesetterSuggestLineBreak(typesetter, index, Double(wrapWidth))
            guard count > 0 else { return text }
            rowStart = index
            index += count
        }
        guard index < source.length else { return text }

        let head = source.substring(to: rowStart)
        var lastRow = trimmingTrailingWhitespace(
            source.substring(with: NSRange(location: rowStart, length: index - rowStart))
        )
        guard style.useEllipsis else { return head + lastRow }
        while !lastRow.isEmpty,
              width(lastRow + Self.ellipsis, attributes: attributes, lineBounds: lineBounds) > wrapWidth
        {
            lastRow = droppingLastCharacter(lastRow)
        }
        return head + lastRow + Self.ellipsis
    }

    private nonisolated static func width(
        _ value: String, attributes: CFDictionary, lineBounds: LineBounds
    ) -> CGFloat {
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault, value as CFString, attributes
        ) else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return lineBounds == .glyphPath
            ? CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).width
            : CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private nonisolated static func droppingLastCharacter(_ value: String) -> String {
        let text = value as NSString
        guard text.length > 0 else { return value }
        let range = text.rangeOfComposedCharacterSequence(at: text.length - 1)
        return text.substring(to: range.location)
    }

    private nonisolated static func trimmingTrailingWhitespace(_ value: String) -> String {
        var result = value
        while let last = result.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last)
        {
            result.unicodeScalars.removeLast()
        }
        return result
    }
}
