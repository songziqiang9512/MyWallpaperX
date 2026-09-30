import Foundation
import UniformTypeIdentifiers

extension SteamWorkshopService {
    static func normalizedWebDirectoryMode(from propertyObject: [String: Any]) -> String? {
        trimmedNonEmptyString(
            (propertyObject["mode"] as? String)
            ?? (propertyObject["directoryMode"] as? String)
        )?.lowercased()
    }

    static func normalizedWebPropertyFileType(
        from propertyObject: [String: Any],
        key: String,
        rawTitle: String?
    ) -> String? {
        if let explicitType = trimmedNonEmptyString(
            (propertyObject["filetype"] as? String)
            ?? (propertyObject["fileType"] as? String)
        )?.lowercased() {
            return explicitType
        }

        let rawValue = trimmedNonEmptyString(propertyObject["value"] as? String) ?? ""
        let pathExtension = URL(fileURLWithPath: rawValue).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "pnga", "bmp", "gif", "svg", "webp", "heic", "heif", "tif", "tiff"].contains(pathExtension) {
            return "image"
        }
        if ["webm", "ogv", "mp4", "mov", "m4v", "avi", "mkv"].contains(pathExtension) {
            return "video"
        }
        if ["mp3", "wav", "flac", "m4a", "aac", "ogg"].contains(pathExtension) {
            return "audio"
        }
        if ["ttf", "otf", "ttc", "woff", "woff2"].contains(pathExtension) {
            return "font"
        }

        let semanticText = "\(key) \(rawTitle ?? "")".lowercased()
        if semanticText.contains("video") || semanticText.contains("movie") {
            return "video"
        }
        if semanticText.contains("audio") || semanticText.contains("music") || semanticText.contains("sound") {
            return "audio"
        }
        if semanticText.contains("font") {
            return "font"
        }
        if semanticText.contains("image")
            || semanticText.contains("img")
            || semanticText.contains("picture")
            || semanticText.contains("photo")
            || semanticText.contains("wallpaper")
            || semanticText.contains("background")
            || semanticText.contains("foreground")
            || semanticText.contains("texture")
            || semanticText.contains("particle")
            || semanticText.contains("custom_bg") {
            return "image"
        }
        return nil
    }

    static func webFileURL(_ url: URL, matches fileType: String?) -> Bool {
        guard let expectedTypes = webAllowedContentTypes(for: fileType) else {
            return true
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return expectedTypes.contains(where: { contentType.conforms(to: $0) })
        }
        guard let extensionType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return expectedTypes.contains(where: { extensionType.conforms(to: $0) })
    }

    static func webAllowedContentTypes(for fileType: String?) -> [UTType]? {
        guard let normalized = trimmedNonEmptyString(fileType)?.lowercased() else {
            return nil
        }
        switch normalized {
        case "image": return [.image]
        case "video": return [.movie, .video]
        case "audio", "music": return [.audio]
        case "font": return [.font]
        default: return nil
        }
    }

    static func webProjectLocalization(from root: [String: Any]) -> [String: String] {
        if let localization = root["localization"] as? [String: String] {
            return localization
        }
        if let general = root["general"] as? [String: Any],
           let localizationObject = general["localization"] {
            if let localization = localizationObject as? [String: String] {
                return localization
            }

            let tables = webLocalizationTables(from: localizationObject)
            guard tables.isEmpty == false else { return [:] }

            // 系统候选（zh-Hans-CN/zh-cn/zh）与作者表键（zh-chs）拼写不同，直接比较只能落到
            // `zh` 前缀，取简还是取繁取决于字典迭代序；两侧先归一到官方语言码，再按有序表键
            // 精确匹配、后退到语言前缀，结果不再随进程变化。未识别语言的表键同样会被归一成
            // en-us，必须排除，否则英文候选会拿到陌生语言表。
            let sortedTableKeys = tables.keys.sorted()
            let matchableTableKeys = sortedTableKeys.filter { key in
                let language = key.split(separator: "-").first.map(String.init) ?? key
                return language == "en" || wallpaperEngineLanguageCode(for: key) != "en-us"
            }
            for candidate in preferredWebLocalizationKeys() {
                if let direct = tables[candidate] {
                    return direct
                }

                let canonicalCandidate = wallpaperEngineLanguageCode(for: candidate)
                let candidateLanguage = candidate.split(separator: "-").first.map(String.init) ?? candidate
                // 未识别语言会归一成 en-us；英文回退由末尾显式处理，不让它在这里抢占。
                guard canonicalCandidate != "en-us" || candidateLanguage == "en" else {
                    continue
                }
                if let exactKey = matchableTableKeys.first(where: { wallpaperEngineLanguageCode(for: $0) == canonicalCandidate }) {
                    return tables[exactKey] ?? [:]
                }

                if let languageOnlyKey = matchableTableKeys.first(where: {
                    let canonicalKey = wallpaperEngineLanguageCode(for: $0)
                    return canonicalKey == candidateLanguage || canonicalKey.hasPrefix(candidateLanguage + "-")
                }) {
                    return tables[languageOnlyKey] ?? [:]
                }
            }

            if let english = tables["en"] ?? tables["en-us"] {
                return english
            }
            return sortedTableKeys.first.flatMap { tables[$0] } ?? [:]
        }
        return [:]
    }

    static func localizedWebString(_ raw: String, localization: [String: String]) -> String {
        normalizedWebDisplayText(localization[raw] ?? raw)
    }

    static func resolvedWebWallpaperLanguage() -> String {
        let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
        return wallpaperEngineLanguageCode(for: preferredLanguage)
    }

    static func wallpaperEngineLanguageCode(for localeIdentifier: String) -> String {
        let normalized = localeIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized == "zh"
            || normalized.hasPrefix("zh-chs") {
            return "zh-chs"
        }
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo")
            || normalized.hasPrefix("zh-cht") {
            return "zh-cht"
        }

        let supportedLanguages: Set<String> = [
            "ar-sa", "be-by", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-us",
            "es-es", "eu-es", "fa-ir", "fi-fi", "fr-fr", "he-il", "hu-hu", "id-id",
            "it-it", "ja-jp", "ko-kr", "lt-lt", "nb-no", "nl-nl", "pl-pl", "pt-br",
            "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sv-se", "th-th", "tr-tr",
            "uk-ua", "vi-vn"
        ]
        if supportedLanguages.contains(normalized) {
            return normalized
        }

        let language = normalized.split(separator: "-").first.map(String.init) ?? ""
        let fallbackLanguages = [
            "ar": "ar-sa", "be": "be-by", "bg": "bg-bg", "cs": "cs-cz", "da": "da-dk",
            "de": "de-de", "el": "el-gr", "en": "en-us", "es": "es-es", "eu": "eu-es",
            "fa": "fa-ir", "fi": "fi-fi", "fr": "fr-fr", "he": "he-il", "hu": "hu-hu",
            "id": "id-id", "it": "it-it", "ja": "ja-jp", "ko": "ko-kr", "lt": "lt-lt",
            "nb": "nb-no", "nl": "nl-nl", "no": "nb-no", "pl": "pl-pl", "pt": "pt-pt",
            "ro": "ro-ro", "ru": "ru-ru", "sk": "sk-sk", "sl": "sl-si", "sv": "sv-se",
            "th": "th-th", "tr": "tr-tr", "uk": "uk-ua", "vi": "vi-vn"
        ]
        return fallbackLanguages[language] ?? "en-us"
    }

    static func normalizedWebPropertyTitleText(_ raw: String) -> String {
        let segments = normalizedWebDisplaySegments(from: raw)
        guard segments.isEmpty == false else {
            return normalizedWebDisplayText(raw)
        }

        let lowercasedRaw = raw.lowercased()
        if lowercasedRaw.contains("<small"), let first = segments.first {
            return first
        }
        if lowercasedRaw.contains("<h1") || lowercasedRaw.contains("<h2")
            || lowercasedRaw.contains("<h3") || lowercasedRaw.contains("<h4")
            || lowercasedRaw.contains("<h5") || lowercasedRaw.contains("<h6") {
            return Array(segments.prefix(2)).joined(separator: " / ")
        }
        return Array(segments.prefix(2)).joined(separator: " / ")
    }

    static func normalizedWebDisplayText(_ raw: String) -> String {
        let segments = normalizedWebDisplaySegments(from: raw)
        guard segments.isEmpty == false else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return segments.joined(separator: " / ")
    }

    static func normalizedWebColorRuntimeString(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let rgb = parseWebColorComponents(from: trimmed) {
            return String(format: "%.6f %.6f %.6f", rgb.red, rgb.green, rgb.blue)
        }
        return nil
    }

    static func parseWebColorComponents(from raw: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let hex = parseHexWebColor(trimmed) {
            return hex
        }

        let lowercase = trimmed.lowercased()
        if lowercase.hasPrefix("rgb(") || lowercase.hasPrefix("rgba(") {
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")"),
                  open < close else {
                return nil
            }
            let payload = String(trimmed[trimmed.index(after: open)..<close])
            let components = payload
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard components.count >= 3 else { return nil }
            return normalizeWebColorTriplet(Array(components.prefix(3)))
        }

        let separators = CharacterSet(charactersIn: ", ")
        let components = trimmed
            .components(separatedBy: separators)
            .filter { $0.isEmpty == false }
            .compactMap(Double.init)
        guard components.count >= 3 else { return nil }
        return normalizeWebColorTriplet(Array(components.prefix(3)))
    }

    private static func webLocalizationTables(from rawValue: Any) -> [String: [String: String]] {
        guard let rawTables = rawValue as? [String: Any] else { return [:] }
        var tables: [String: [String: String]] = [:]
        for (languageKey, tableValue) in rawTables {
            guard let rawTable = tableValue as? [String: Any] else { continue }
            var normalizedTable: [String: String] = [:]
            for (token, rawTranslation) in rawTable {
                if let translation = rawTranslation as? String {
                    normalizedTable[token] = translation
                }
            }
            if normalizedTable.isEmpty == false {
                tables[normalizeWebLocalizationKey(languageKey)] = normalizedTable
            }
        }
        return tables
    }

    private static func normalizedWebDisplaySegments(from raw: String) -> [String] {
        let normalizedRaw = raw
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let breakPattern = "(?i)<br(?:\\s|/|&nbsp;)*?>"
        let withoutBreakTags = normalizedRaw.replacingOccurrences(
            of: breakPattern,
            with: "\n",
            options: .regularExpression
        )
        let withoutHTMLTags = withoutBreakTags.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        var lines = withoutHTMLTags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else {
            let fallback = normalizedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [fallback]
        }

        lines = collapseRepeatedWebDisplaySegments(lines)

        var uniqueOrderedLines: [String] = []
        for line in lines where uniqueOrderedLines.contains(line) == false {
            uniqueOrderedLines.append(line)
        }
        return uniqueOrderedLines
    }

    private static func collapseRepeatedWebDisplaySegments(_ segments: [String]) -> [String] {
        guard segments.count >= 2 else { return segments }

        let halfCount = segments.count / 2
        if segments.count.isMultiple(of: 2),
           Array(segments[..<halfCount]) == Array(segments[halfCount...]) {
            return Array(segments[..<halfCount])
        }

        var collapsed: [String] = []
        for segment in segments where collapsed.last != segment {
            collapsed.append(segment)
        }
        return collapsed
    }

    private static func preferredWebLocalizationKeys() -> [String] {
        var orderedKeys: [String] = []

        func append(_ rawKey: String?) {
            guard let rawKey else { return }
            let normalized = normalizeWebLocalizationKey(rawKey)
            guard normalized.isEmpty == false else { return }
            if orderedKeys.contains(normalized) == false {
                orderedKeys.append(normalized)
            }

            let components = normalized.split(separator: "-")
            if components.count > 1 {
                let languageOnly = String(components[0])
                if orderedKeys.contains(languageOnly) == false {
                    orderedKeys.append(languageOnly)
                }
            }
        }

        Locale.preferredLanguages.forEach(append)
        append(Locale.current.identifier)
        append(Locale.autoupdatingCurrent.identifier)
        append("en-us")
        append("en")
        return orderedKeys
    }

    private static func normalizeWebLocalizationKey(_ rawKey: String) -> String {
        rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static func normalizeWebColorTriplet(_ components: [Double]) -> (red: Double, green: Double, blue: Double)? {
        guard components.count >= 3 else { return nil }
        let usesByteRange = components.contains { $0 > 1.0 }
        let scale = usesByteRange ? 255.0 : 1.0
        let normalized = components.prefix(3).map { component in
            min(max(component / scale, 0), 1)
        }
        guard normalized.count == 3 else { return nil }
        return (normalized[0], normalized[1], normalized[2])
    }

    private static func parseHexWebColor(_ raw: String) -> (red: Double, green: Double, blue: Double)? {
        guard raw.hasPrefix("#") else { return nil }
        let hex = String(raw.dropFirst())
        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = hex
        case 8:
            expanded = String(hex.prefix(6))
        default:
            return nil
        }
        guard let value = Int(expanded, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return (red, green, blue)
    }
}
