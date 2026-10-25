import Foundation
import UniformTypeIdentifiers

extension SteamWorkshopService {
    nonisolated static func normalizedWebDirectoryMode(from propertyObject: [String: Any]) -> String? {
        trimmedNonEmptyString(
            (propertyObject["mode"] as? String)
            ?? (propertyObject["directoryMode"] as? String)
        )?.lowercased()
    }

    nonisolated static func normalizedWebPropertyFileType(
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

    nonisolated static func webProjectLocalization(from root: [String: Any], languageKeys: [String] = WorkshopPropertyDisplayResolver.languageVersion) -> [String: String] {
        WorkshopPropertyLocalization(projectRoot: root).strings(languageKeys: languageKeys)
    }

    nonisolated static func localizedWebString(_ raw: String, localization: [String: String]) -> String {
        normalizedWebDisplayText(WorkshopPropertyDisplayResolver(
            localization: .init(flat: localization), vocabulary: .empty).string(raw))
    }

    nonisolated static func localizedWebPropertyDisplayString(_ raw: String, resolver: WorkshopPropertyDisplayResolver) -> String {
        WorkshopPropertyDisplayResolver.plainText(resolver.string(raw)) ?? ""
    }

    static func resolvedWebWallpaperLanguage() -> String {
        let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
        return wallpaperEngineLanguageCode(for: preferredLanguage)
    }

    nonisolated static func wallpaperEngineLanguageCode(for localeIdentifier: String) -> String {
        WorkshopPropertyDisplayResolver.languageCode(for: localeIdentifier)
    }

    nonisolated static func normalizedWebPropertyTitleText(_ raw: String) -> String {
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

    nonisolated static func normalizedWebDisplayText(_ raw: String) -> String {
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

    nonisolated static func parseWebColorComponents(from raw: String) -> (red: Double, green: Double, blue: Double)? {
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



    private nonisolated static func normalizedWebDisplaySegments(from raw: String) -> [String] {
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

    private nonisolated static func collapseRepeatedWebDisplaySegments(_ segments: [String]) -> [String] {
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





    private nonisolated static func normalizeWebColorTriplet(_ components: [Double]) -> (red: Double, green: Double, blue: Double)? {
        guard components.count >= 3 else { return nil }
        let usesByteRange = components.contains { $0 > 1.0 }
        let scale = usesByteRange ? 255.0 : 1.0
        let normalized = components.prefix(3).map { component in
            min(max(component / scale, 0), 1)
        }
        guard normalized.count == 3 else { return nil }
        return (normalized[0], normalized[1], normalized[2])
    }

    private nonisolated static func parseHexWebColor(_ raw: String) -> (red: Double, green: Double, blue: Double)? {
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
