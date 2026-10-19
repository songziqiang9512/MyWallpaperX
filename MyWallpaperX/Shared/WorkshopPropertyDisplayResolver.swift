import Foundation

/// Loss-preserving, display-only author declaration. No runtime property values.
nonisolated struct WorkshopPropertyLocalization: Equatable, Sendable {
    let flat: [String: String]?
    let tables: [String: [String: String]]

    static let empty = Self(flat: nil, tables: [:])

    init(flat: [String: String]?, tables: [String: [String: String]] = [:]) {
        self.flat = flat
        self.tables = tables
    }

    init(projectRoot: [String: Any]) {
        if let flat = projectRoot["localization"] as? [String: String] {
            self.init(flat: flat)
            return
        }
        let general = projectRoot["general"] as? [String: Any]
        let raw = general?["localization"]
        if let flat = raw as? [String: String] {
            self.init(flat: flat)
            return
        }
        var tables: [String: [String: String]] = [:]
        for (language, value) in raw as? [String: Any] ?? [:] {
            guard let values = value as? [String: Any] else { continue }
            let strings = values.compactMapValues { $0 as? String }
            if !strings.isEmpty {
                tables[Self.normalizedLanguageKey(language)] = strings
            }
        }
        self.init(flat: nil, tables: tables)
    }

    /// The existing Web table selection, including its deterministic fallback.
    func strings(languageKeys: [String]) -> [String: String] {
        if let flat { return flat }
        guard !tables.isEmpty else { return [:] }
        let sortedTableKeys = tables.keys.sorted()
        let matchableTableKeys = sortedTableKeys.filter { key in
            let language = key.split(separator: "-").first.map(String.init) ?? key
            return language == "en" || WorkshopPropertyDisplayResolver.languageCode(for: key) != "en-us"
        }
        for candidate in languageKeys {
            if let direct = tables[candidate] {
                return direct
            }

            let canonicalCandidate = WorkshopPropertyDisplayResolver.languageCode(for: candidate)
            let candidateLanguage = candidate.split(separator: "-").first.map(String.init) ?? candidate
            // 未识别语言会归一成 en-us；英文回退由末尾显式处理，不让它在这里抢占。
            guard canonicalCandidate != "en-us" || candidateLanguage == "en" else {
                continue
            }
            if let exactKey = matchableTableKeys.first(where: { WorkshopPropertyDisplayResolver.languageCode(for: $0) == canonicalCandidate }) {
                return tables[exactKey] ?? [:]
            }

            if let languageOnlyKey = matchableTableKeys.first(where: {
                let canonicalKey = WorkshopPropertyDisplayResolver.languageCode(for: $0)
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

    var estimatedCost: Int {
        func tableCost(_ table: [String: String]) -> Int {
            table.reduce(256) { $0 + ($1.key.utf8.count + $1.value.utf8.count) * 4 + 256 }
        }
        return (flat.map(tableCost) ?? 0) + tables.reduce(256) {
            $0 + $1.key.utf8.count * 4 + 256 + tableCost($1.value)
        }
    }

    static func normalizedLanguageKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

/// One display resolver for Scene and Web. Original catalog/condition/value
/// owners never consume its result. Standard vocabulary is self-authored data.
nonisolated struct WorkshopPropertyDisplayResolver {
    struct Vocabulary: Decodable, Sendable {
        let schemaVersion: Int
        let languages: [String: [String: String]]

        static let empty = Self(schemaVersion: 1, languages: [:])
    }

    let authorStrings: [String: String]
    let standardStrings: [String: String]

    init(
        localization: WorkshopPropertyLocalization = .empty,
        languageKeys: [String] = Self.languageVersion,
        vocabulary: Vocabulary = Self.bundledVocabulary
    ) {
        authorStrings = localization.strings(languageKeys: languageKeys)
        let selected = WorkshopPropertyLocalization(flat: nil, tables: vocabulary.languages)
            .strings(languageKeys: languageKeys)
        // Per-token English fallback is only for our curated vocabulary. The
        // existing author table selection and explicit empty values stay intact.
        standardStrings = (vocabulary.languages["en-us"] ?? [:]).merging(selected) { _, preferred in preferred }
    }

    func string(_ raw: String) -> String {
        authorStrings[raw] ?? standardStrings[raw] ?? raw
    }

    /// Plain native presentation only: preserve every authored paragraph and
    /// never load HTML resources or turn translated labels into runtime input.
    static func plainText(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>",
            with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|h[1-6])\\s*>|<hr\\s*/?>",
            with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
        // Decode after removing markup, so encoded '<' and '>' stay literal.
        let entities = ["&nbsp;": " ", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&amp;": "&"]
        for key in entities.keys.sorted() where key != "&amp;" {
            text = text.replacingOccurrences(of: key, with: entities[key]!)
        }
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let tokenRange = Range(match.range(at: 1), in: text),
                      let fullRange = Range(match.range, in: text) else { continue }
                let token = String(text[tokenRange])
                let number = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
                if let number, let scalar = UnicodeScalar(number) { text.replaceSubrange(fullRange, with: String(scalar)) }
            }
        }
        let result = text.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    static var languageVersion: [String] {
        preferredLanguageKeys(preferredLanguages: Locale.preferredLanguages,
            currentIdentifier: Locale.current.identifier,
            autoupdatingIdentifier: Locale.autoupdatingCurrent.identifier)
    }

    /// The original Web ordered-candidate algorithm; arguments make it testable
    /// without changing the user's system language or adding a second selector.
    static func preferredLanguageKeys(
        preferredLanguages: [String], currentIdentifier: String,
        autoupdatingIdentifier: String
    ) -> [String] {
        var orderedKeys: [String] = []
        func append(_ rawKey: String) {
            let normalized = WorkshopPropertyLocalization.normalizedLanguageKey(rawKey)
            guard !normalized.isEmpty else { return }
            if !orderedKeys.contains(normalized) { orderedKeys.append(normalized) }
            let components = normalized.split(separator: "-")
            if components.count > 1 {
                let language = String(components[0])
                if !orderedKeys.contains(language) { orderedKeys.append(language) }
            }
        }
        preferredLanguages.forEach(append)
        append(currentIdentifier)
        append(autoupdatingIdentifier)
        append("en-us")
        append("en")
        return orderedKeys
    }

    nonisolated static func languageCode(for localeIdentifier: String) -> String {
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

    static let bundledVocabulary: Vocabulary = {
        guard let url = Bundle.main.url(forResource: "WorkshopPropertyDisplayStrings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let vocabulary = try? JSONDecoder().decode(Vocabulary.self, from: data),
              vocabulary.schemaVersion == 1 else { return .empty }
        return vocabulary
    }()
}
