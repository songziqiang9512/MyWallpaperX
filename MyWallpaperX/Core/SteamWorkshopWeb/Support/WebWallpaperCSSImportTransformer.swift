//
//  WebWallpaperCSSImportTransformer.swift
//  MyWallpaperX
//

import Foundation

enum WebWallpaperCSSImportTransformer {
    private static let quotedGoogleFontImportExpression = try! NSRegularExpression(
        pattern: #"^@import\s+([\"'])((?:https?:)?//fonts\.googleapis\.com/[^\"']+)\1\s*([^;]*);$"#,
        options: [.caseInsensitive]
    )

    private static let urlGoogleFontImportExpression = try! NSRegularExpression(
        pattern: #"^@import\s+url\(\s*(?:([\"'])((?:https?:)?//fonts\.googleapis\.com/[^\"']+)\1|((?:https?:)?//fonts\.googleapis\.com/[^\s\"'()]+))\s*\)\s*([^;]*);$"#,
        options: [.caseInsensitive]
    )

    static func transform(_ css: String) -> String {
        let source = css as NSString
        let importRanges = topLevelImportRanges(in: source)
        guard !importRanges.isEmpty else { return css }

        let output = NSMutableString(string: css)
        for range in importRanges.reversed() {
            let statement = source.substring(with: range)
            guard let rewritten = rewriteGoogleFontImport(statement) else { continue }
            output.replaceCharacters(in: range, with: rewritten)
        }
        return output as String
    }

    private static func topLevelImportRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = skipIgnorables(in: source, from: 0)
        var allowsCharset = true

        while cursor < source.length {
            if hasPrefix("<!--", in: source, at: cursor, caseInsensitive: false) {
                cursor = skipIgnorables(in: source, from: cursor + 4)
                continue
            }
            if hasPrefix("-->", in: source, at: cursor, caseInsensitive: false) {
                cursor = skipIgnorables(in: source, from: cursor + 3)
                continue
            }

            let keyword: String
            if allowsCharset, hasKeyword("@charset", in: source, at: cursor) {
                keyword = "charset"
            } else if hasKeyword("@layer", in: source, at: cursor) {
                keyword = "layer"
            } else if hasKeyword("@import", in: source, at: cursor) {
                keyword = "import"
            } else {
                break
            }

            guard let statement = consumeStatement(in: source, from: cursor),
                  !statement.opensBlock else {
                break
            }
            if keyword == "import" { ranges.append(statement.range) }
            allowsCharset = false
            cursor = skipIgnorables(in: source, from: NSMaxRange(statement.range))
        }
        return ranges
    }

    private static func consumeStatement(
        in source: NSString,
        from offset: Int
    ) -> (range: NSRange, opensBlock: Bool)? {
        var index = offset
        var quote: unichar?
        var parenthesisDepth = 0
        while index < source.length {
            let character = source.character(at: index)
            if let activeQuote = quote {
                if character == 92 {
                    index = min(index + 2, source.length)
                    continue
                }
                if character == activeQuote { quote = nil }
            } else if character == 34 || character == 39 {
                quote = character
            } else if character == 47,
                      index + 1 < source.length,
                      source.character(at: index + 1) == 42 {
                guard let commentEnd = commentEnd(in: source, from: index + 2) else { return nil }
                index = commentEnd
                continue
            } else if character == 40 {
                parenthesisDepth += 1
            } else if character == 41, parenthesisDepth > 0 {
                parenthesisDepth -= 1
            } else if parenthesisDepth == 0, character == 59 || character == 123 {
                let range = NSRange(location: offset, length: index - offset + 1)
                return (range, character == 123)
            }
            index += 1
        }
        return nil
    }

    private static func rewriteGoogleFontImport(_ statement: String) -> String? {
        let source = statement as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard let googleImport = googleFontImport(in: statement, source: source, range: fullRange),
              var components = URLComponents(string: googleImport.url),
              components.host?.lowercased() == "fonts.googleapis.com" else {
            return nil
        }
        // 限定符分类处置：裸 screen 在壁纸 WKWebView 恒真，随 not all 丢弃无
        // 语义损失；其余限定符保留作者语义不动——可能为假的媒体（print 等）
        // 浏览器本就不取，layer() 因恢复路径只能以 <link> 重建、无法承载层
        // 语义，一律不改写。
        let qualifier = googleImport.qualifier.trimmingCharacters(in: .whitespaces)
        guard qualifier.isEmpty || qualifier.caseInsensitiveCompare("screen") == .orderedSame else {
            return nil
        }
        components.scheme = "https"
        guard let secureURL = components.string else { return nil }
        return "@import url(\"\(secureURL)\") not all;"
    }

    private static func googleFontImport(
        in statement: String,
        source: NSString,
        range: NSRange
    ) -> (url: String, qualifier: String)? {
        if let match = quotedGoogleFontImportExpression.firstMatch(in: statement, range: range),
           match.range == range {
            return (
                source.substring(with: match.range(at: 2)),
                source.substring(with: match.range(at: 3))
            )
        }
        guard let match = urlGoogleFontImportExpression.firstMatch(in: statement, range: range),
              match.range == range else {
            return nil
        }
        let quotedURLRange = match.range(at: 2)
        let rawURLRange = quotedURLRange.location == NSNotFound ? match.range(at: 3) : quotedURLRange
        return (source.substring(with: rawURLRange), source.substring(with: match.range(at: 4)))
    }

    private static func skipIgnorables(in source: NSString, from offset: Int) -> Int {
        var index = offset
        while index < source.length {
            if isWhitespace(source.character(at: index)) {
                index += 1
                continue
            }
            if source.character(at: index) == 47,
               index + 1 < source.length,
               source.character(at: index + 1) == 42,
               let end = commentEnd(in: source, from: index + 2) {
                index = end
                continue
            }
            break
        }
        return index
    }

    private static func commentEnd(in source: NSString, from offset: Int) -> Int? {
        let searchRange = NSRange(location: offset, length: source.length - offset)
        let range = source.range(of: "*/", options: [], range: searchRange)
        return range.location == NSNotFound ? nil : NSMaxRange(range)
    }

    private static func hasKeyword(_ keyword: String, in source: NSString, at offset: Int) -> Bool {
        guard hasPrefix(keyword, in: source, at: offset, caseInsensitive: true) else { return false }
        let boundary = offset + (keyword as NSString).length
        guard boundary < source.length else { return true }
        let character = source.character(at: boundary)
        return isWhitespace(character) || character == 34 || character == 39 || character == 40
    }

    private static func hasPrefix(
        _ prefix: String,
        in source: NSString,
        at offset: Int,
        caseInsensitive: Bool
    ) -> Bool {
        let length = (prefix as NSString).length
        guard offset >= 0, offset + length <= source.length else { return false }
        let options: NSString.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        return source.compare(
            prefix,
            options: options,
            range: NSRange(location: offset, length: length)
        ) == .orderedSame
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 12 || character == 13 || character == 32
    }
}
