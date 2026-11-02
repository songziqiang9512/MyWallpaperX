//
//  WebWallpaperHTMLTransformer.swift
//  MyWallpaperX
//

import Foundation

enum WebWallpaperHTMLTransformer {
    private struct Attribute {
        let value: String?
        let valueRange: NSRange?
    }

    private static let rawTextElementNames: Set<String> = [
        "iframe", "noembed", "noframes", "noscript", "plaintext",
        "script", "style", "textarea", "title", "xmp"
    ]

    static func transform(_ html: String) -> String {
        let source = html as NSString
        let ranges = linkTagRanges(in: source)
        guard !ranges.isEmpty else { return html }

        let output = NSMutableString(string: html)
        for range in ranges.reversed() {
            let tag = source.substring(with: range)
            guard let rewritten = rewriteLinkTag(tag) else { continue }
            output.replaceCharacters(in: range, with: rewritten)
        }
        return output as String
    }

    private static func linkTagRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        var rawTextElementName: String?

        while cursor < source.length {
            if let rawName = rawTextElementName {
                if rawName == "plaintext" { break }
                guard let closingOffset = rawTextClosingOffset(
                    named: rawName,
                    in: source,
                    from: cursor
                ) else {
                    break
                }
                cursor = consumeTag(in: source, at: closingOffset)
                    .map { NSMaxRange($0.range) } ?? closingOffset + 2
                rawTextElementName = nil
                continue
            }

            let nextRange = NSRange(location: cursor, length: source.length - cursor)
            let lessThan = source.range(of: "<", options: [], range: nextRange).location
            guard lessThan != NSNotFound else { break }

            if hasPrefix("<!--", in: source, at: lessThan, caseInsensitive: false) {
                let start = lessThan + 4
                let searchRange = NSRange(location: start, length: source.length - start)
                let commentEnd = source.range(of: "-->", options: [], range: searchRange)
                guard commentEnd.location != NSNotFound else { break }
                cursor = NSMaxRange(commentEnd)
                continue
            }

            guard let tag = consumeTag(in: source, at: lessThan) else {
                cursor = lessThan + 1
                continue
            }
            cursor = NSMaxRange(tag.range)
            guard !tag.isClosing else { continue }
            if tag.name == "link" { ranges.append(tag.range) }
            if rawTextElementNames.contains(tag.name) { rawTextElementName = tag.name }
        }
        return ranges
    }

    private static func consumeTag(
        in source: NSString,
        at offset: Int
    ) -> (range: NSRange, name: String, isClosing: Bool)? {
        guard offset < source.length, source.character(at: offset) == 60 else { return nil }
        var index = offset + 1
        guard index < source.length else { return nil }

        let firstCharacter = source.character(at: index)
        if firstCharacter == 33 || firstCharacter == 63 {
            guard let end = tagClosingOffset(in: source, from: index + 1) else { return nil }
            return (NSRange(location: offset, length: end - offset + 1), "", false)
        }

        let isClosing = firstCharacter == 47
        if isClosing { index += 1 }
        let nameStart = index
        while index < source.length, isTagNameCharacter(source.character(at: index)) {
            index += 1
        }
        guard index > nameStart,
              let end = tagClosingOffset(in: source, from: index) else {
            return nil
        }
        let nameRange = NSRange(location: nameStart, length: index - nameStart)
        return (
            NSRange(location: offset, length: end - offset + 1),
            source.substring(with: nameRange).lowercased(),
            isClosing
        )
    }

    private static func tagClosingOffset(in source: NSString, from offset: Int) -> Int? {
        var index = offset
        var quote: unichar?
        while index < source.length {
            let character = source.character(at: index)
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == 34 || character == 39 {
                quote = character
            } else if character == 62 {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func rawTextClosingOffset(
        named name: String,
        in source: NSString,
        from offset: Int
    ) -> Int? {
        let needle = "</\(name)"
        var searchStart = offset
        while searchStart < source.length {
            let searchRange = NSRange(location: searchStart, length: source.length - searchStart)
            let match = source.range(of: needle, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound else { return nil }
            let boundary = NSMaxRange(match)
            if boundary >= source.length || isTagBoundary(source.character(at: boundary)) {
                return match.location
            }
            searchStart = match.location + 2
        }
        return nil
    }

    private static func rewriteLinkTag(_ tag: String) -> String? {
        guard let attributes = parseAttributes(in: tag),
              let hrefAttribute = attributes["href"],
              let href = hrefAttribute.value,
              let hrefValueRange = hrefAttribute.valueRange,
              let relAttribute = attributes["rel"],
              let rel = relAttribute.value,
              let relValueRange = relAttribute.valueRange else {
            return nil
        }

        let relTokens = rel.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let loweredTokens = relTokens.map { $0.lowercased() }
        guard loweredTokens.contains("stylesheet"),
              !loweredTokens.contains("alternate"),
              !loweredTokens.contains("preload"),
              attributes["disabled"] == nil,
              attributes["media"] == nil,
              attributes["as"] == nil,
              attributes["data-mwx-deferred-stylesheet"] == nil,
              attributes["onload"] == nil,
              attributes["onerror"] == nil else {
            return nil
        }
        if let type = attributes["type"]?.value,
           type.caseInsensitiveCompare("text/css") != .orderedSame {
            return nil
        }
        let normalizedGoogleFontHref = normalizedGoogleFontHref(href)
        guard normalizedGoogleFontHref != nil || shouldDeferExplicitly(
            href: href,
            attributes: attributes
        ) else {
            return nil
        }

        let deferredRel = zip(relTokens, loweredTokens)
            .map { $0.1 == "stylesheet" ? "preload" : $0.0 }
            .joined(separator: " ")
        let originalRel = relTokens.joined(separator: " ")
        let mutableTag = NSMutableString(string: tag)
        var replacements = [(range: relValueRange, value: deferredRel)]
        if let normalizedGoogleFontHref, normalizedGoogleFontHref != href {
            replacements.append((range: hrefValueRange, value: normalizedGoogleFontHref))
        }
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutableTag.replaceCharacters(in: replacement.range, with: replacement.value)
        }
        let closingOffset = mutableTag.hasSuffix("/>") ? mutableTag.length - 2 : mutableTag.length - 1
        let marker = " as=\"style\" data-mwx-deferred-stylesheet=\"\(escapeAttribute(originalRel))\""
        mutableTag.insert(marker, at: closingOffset)
        return mutableTag as String
    }

    private static func parseAttributes(in tag: String) -> [String: Attribute]? {
        let source = tag as NSString
        guard source.length >= 6,
              hasPrefix("<link", in: source, at: 0, caseInsensitive: true) else {
            return nil
        }

        var attributes: [String: Attribute] = [:]
        var index = 5
        let contentEnd = source.length - 1
        while index < contentEnd {
            while index < contentEnd, isWhitespace(source.character(at: index)) { index += 1 }
            if index >= contentEnd || source.character(at: index) == 47 { break }

            let nameStart = index
            while index < contentEnd, isAttributeNameCharacter(source.character(at: index)) {
                index += 1
            }
            guard index > nameStart else { return nil }
            let nameRange = NSRange(location: nameStart, length: index - nameStart)
            let name = source.substring(with: nameRange).lowercased()
            guard attributes[name] == nil else { return nil }

            while index < contentEnd, isWhitespace(source.character(at: index)) { index += 1 }
            guard index < contentEnd, source.character(at: index) == 61 else {
                attributes[name] = Attribute(value: nil, valueRange: nil)
                continue
            }

            index += 1
            while index < contentEnd, isWhitespace(source.character(at: index)) { index += 1 }
            guard index < contentEnd else { return nil }
            let quote = source.character(at: index)
            let valueStart: Int
            let valueEnd: Int
            if quote == 34 || quote == 39 {
                valueStart = index + 1
                index = valueStart
                while index < contentEnd, source.character(at: index) != quote { index += 1 }
                guard index < contentEnd else { return nil }
                valueEnd = index
                index += 1
            } else {
                valueStart = index
                while index < contentEnd, !isWhitespace(source.character(at: index)) {
                    let character = source.character(at: index)
                    guard character != 34, character != 39, character != 60,
                          character != 61, character != 62, character != 96 else {
                        return nil
                    }
                    index += 1
                }
                valueEnd = index
                guard valueEnd > valueStart else { return nil }
            }
            let valueRange = NSRange(location: valueStart, length: valueEnd - valueStart)
            attributes[name] = Attribute(
                value: source.substring(with: valueRange),
                valueRange: valueRange
            )
        }
        return attributes
    }

    private static func normalizedGoogleFontHref(_ href: String) -> String? {
        let normalizedHref: String
        if href.hasPrefix("//") {
            normalizedHref = "https:\(href)"
        } else if href.range(of: "http://", options: [.anchored, .caseInsensitive]) != nil {
            normalizedHref = "https://\(href.dropFirst(7))"
        } else if href.range(of: "https://", options: [.anchored, .caseInsensitive]) != nil {
            normalizedHref = "https://\(href.dropFirst(8))"
        } else {
            return nil
        }
        guard let components = URLComponents(string: normalizedHref),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "fonts.googleapis.com" else {
            return nil
        }
        return normalizedHref
    }

    private static func shouldDeferExplicitly(
        href: String,
        attributes: [String: Attribute]
    ) -> Bool {
        guard attributes["data-mwx-defer-stylesheet"] != nil,
              let url = URL(string: href),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        return true
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

    private static func isTagNameCharacter(_ character: unichar) -> Bool {
        isASCIIAlphaNumeric(character) || character == 45 || character == 58
    }

    private static func isAttributeNameCharacter(_ character: unichar) -> Bool {
        !isWhitespace(character) &&
            character != 34 && character != 39 && character != 47 &&
            character != 60 && character != 61 && character != 62 && character != 96
    }

    private static func isTagBoundary(_ character: unichar) -> Bool {
        isWhitespace(character) || character == 47 || character == 62
    }

    private static func isASCIIAlphaNumeric(_ character: unichar) -> Bool {
        (character >= 48 && character <= 57) ||
            (character >= 65 && character <= 90) ||
            (character >= 97 && character <= 122)
    }
}
