import Foundation

extension SteamWorkshopService {
    nonisolated static func normalizedStubTitle(_ stub: SteamWorkshopBrowseStub) -> String {
        let title = stub.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Workshop #\(stub.id)" : title
    }

    nonisolated static func normalizedStubAuthor(_ stub: SteamWorkshopBrowseStub) -> String {
        let author = normalizeAuthorName(stub.author ?? "")
        return author.isEmpty ? "未知作者" : author
    }

    nonisolated static func formatSteamTimestamp(_ timestamp: Int64?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        return DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            dateStyle: .medium,
            timeStyle: .none
        )
    }

    nonisolated static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    nonisolated static func appendDetailField(
        _ label: String,
        value: String?,
        to fields: inout [SteamWorkshopDetailField]
    ) {
        guard let value, !value.isEmpty else { return }
        fields.append(SteamWorkshopDetailField(label: label, value: value))
    }

    nonisolated static func appendNormalizedDetailField(
        label: String,
        value: String,
        to fields: inout [SteamWorkshopDetailField],
        seen: inout Set<String>
    ) {
        let normalizedLabel = normalizeText(label.replacingOccurrences(of: ":", with: ""))
        let normalizedValue = normalizeText(value)
        guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else { return }
        let key = "\(normalizedLabel)|\(normalizedValue)"
        guard seen.insert(key).inserted else { return }
        fields.append(SteamWorkshopDetailField(label: normalizedLabel, value: normalizedValue))
    }

    nonisolated static func buildOfficialDetailFields(
        fileSizeText: String?,
        resolutionText: String?,
        postedText: String?,
        updatedText: String?,
        subscriptionsText: String?,
        favoritesText: String?,
        lifetimeSubscriptionsText: String?,
        lifetimeFavoritesText: String?,
        visibilityText: String?,
        moderationText: String?,
        tags: [String]
    ) -> [SteamWorkshopDetailField] {
        var fields: [SteamWorkshopDetailField] = []

        Self.appendDetailField("File Size", value: fileSizeText, to: &fields)
        Self.appendDetailField("Resolution", value: resolutionText, to: &fields)
        Self.appendDetailField("Posted", value: postedText, to: &fields)
        Self.appendDetailField("Updated", value: updatedText, to: &fields)
        Self.appendDetailField("Subscriptions", value: subscriptionsText, to: &fields)
        Self.appendDetailField("Favorited", value: favoritesText, to: &fields)
        Self.appendDetailField("Lifetime Subscriptions", value: lifetimeSubscriptionsText, to: &fields)
        Self.appendDetailField("Lifetime Favorited", value: lifetimeFavoritesText, to: &fields)
        Self.appendDetailField("Visibility", value: visibilityText, to: &fields)
        Self.appendDetailField("Moderation", value: moderationText, to: &fields)
        if !tags.isEmpty {
            Self.appendDetailField("Tags", value: tags.joined(separator: " · "), to: &fields)
        }
        return fields
    }

    nonisolated static func visibilityText(for visibility: Int?) -> String? {
        guard let visibility else { return nil }
        switch visibility {
        case 0: return "公开"
        case 1: return "好友可见"
        case 2: return "私有"
        case 3: return "未列出"
        default: return "可见性 \(visibility)"
        }
    }

    nonisolated static func moderationText(banned: Int?, banReason: String?) -> String? {
        guard let banned else { return nil }
        if banned == 0 {
            return "正常"
        }
        let reason = normalizeText(banReason ?? "")
        return reason.isEmpty ? "已封禁" : "已封禁 · \(reason)"
    }

    nonisolated static func preferredTag(in tags: [String], matching candidates: [String]) -> String? {
        tags.first { tag in
            candidates.contains { candidate in
                tag.compare(candidate, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    nonisolated static func isResolutionTag(_ tag: String) -> Bool {
        tag.range(of: #"\d{3,5}\s*x\s*\d{3,5}"#, options: [.regularExpression, .caseInsensitive]) != nil
            || tag.range(of: #"\d{3,5}\s*×\s*\d{3,5}"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func isSystemWorkshopTag(_ tag: String) -> Bool {
        if preferredTag(in: [tag], matching: SteamWorkshopBrowserContentMode.allCases.map(\.requiredTagValue)) != nil {
            return true
        }
        if preferredTag(in: [tag], matching: SteamWorkshopAgeRatingFilter.ratingTagValues) != nil {
            return true
        }
        if preferredTag(in: [tag], matching: SteamWorkshopCategoryFilter.allCases.dropFirst().map(\.rawValue)) != nil {
            return true
        }
        return isResolutionTag(tag)
    }

    nonisolated static func normalizeAuthorName(_ text: String) -> String {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return "" }
        let statusTokens = ["在线", "离线", "游戏中", "正在游戏", "当前离线"]
        for token in statusTokens {
            if let range = normalized.range(of: token) {
                return String(normalized[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return normalized
    }

    nonisolated static func firstCapture(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard let swiftRange = Range(targetRange, in: html) else { return nil }
        return String(html[swiftRange])
    }

    nonisolated static func firstCaptureMatches(pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let swiftRange = Range(targetRange, in: html) else { return nil }
            return normalizeText(String(html[swiftRange]))
        }
    }

    nonisolated static func normalizeText(_ text: String) -> String {
        let noBreaks = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        let withoutTags = noBreaks.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = htmlDecode(withoutTags)
        let compacted = decoded.replacingOccurrences(
            of: #"[ \t\r\f\v]+"#,
            with: " ",
            options: .regularExpression
        )
        return compacted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func htmlDecode(_ text: String) -> String {
        var decoded = text
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#x2F;": "/"
        ]
        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }

    nonisolated static func fileSizeText(forBytes bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1fGB", mb / 1024)
        }
        if mb >= 100 {
            return String(format: "%.0fMB", mb)
        }
        if mb >= 10 {
            return String(format: "%.1fMB", mb)
        }
        return String(format: "%.2fMB", mb)
    }

    nonisolated static func parseByteCount(from text: String?) -> Int64? {
        guard let text else { return nil }
        let normalized = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard let value = Double(firstCapture(pattern: #"([0-9]+(?:\.[0-9]+)?)"#, in: normalized) ?? "") else {
            return nil
        }

        if normalized.contains("GB") {
            return Int64(value * 1024 * 1024 * 1024)
        }
        if normalized.contains("MB") {
            return Int64(value * 1024 * 1024)
        }
        if normalized.contains("KB") {
            return Int64(value * 1024)
        }
        if normalized.contains("B") {
            return Int64(value)
        }
        return nil
    }
}
