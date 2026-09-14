import CoreText
import Foundation

/// WE 的 text layer 有两组溢出控制：Limit width / Max width 决定换行宽度，
/// Limit rows / Max rows 决定最多排几行，Overflow ellipsis 决定被裁时是否补省略号。
/// 三个开关关闭时必须完全不改变原有排版，因为 `maxwidth`/`maxrows` 在关闭状态下
/// 仍带着编辑器默认值（本机语料 393 个 `limitwidth: false` 的 layer 全是 500，
/// 其中 79 个作者宽度已经超过 500），一旦无条件生效就会把它们错误地压窄。
nonisolated enum SceneTextRowLimit {
    private static let ellipsis = "…"

    /// `maxwidth` 的单位是像素（lib.sceneScript.d.ts 的 ITextLayer："Max width in
    /// pixels"），所以要和 padding 一样乘上栅格降采样比例；上界仍是作者外框的内容宽度，
    /// 超出外框的部分本来也画不出来。
    nonisolated static func wrapWidth(
        contentWidth: CGFloat,
        style: SceneTextDescriptor,
        scale: Float
    ) -> CGFloat {
        guard style.limitWidth, style.maxWidth > 0 else { return contentWidth }
        return min(contentWidth, CGFloat(style.maxWidth) * CGFloat(max(0, scale)))
    }

    /// 按 `maxrows` 裁行：多出来的行整行丢掉，`limituseellipsis` 打开时在末行补 `…`，
    /// 并逐个（按组合字符序列）回退末行字符，保证补上省略号后仍不超过换行宽度。
    nonisolated static func limitedText(
        _ text: String,
        style: SceneTextDescriptor,
        attributes: CFDictionary,
        wrapWidth: CGFloat
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
        for _ in 0 ..< maxRows {
            guard index < source.length else { break }
            let count = CTTypesetterSuggestLineBreak(typesetter, index, Double(wrapWidth))
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
              width(lastRow + Self.ellipsis, attributes: attributes) > wrapWidth
        {
            lastRow = droppingLastCharacter(lastRow)
        }
        return head + lastRow + Self.ellipsis
    }

    private nonisolated static func width(_ value: String, attributes: CFDictionary) -> CGFloat {
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault, value as CFString, attributes
        ) else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
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
