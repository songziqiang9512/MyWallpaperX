import Foundation

extension SteamWorkshopService {
    func shouldRefreshFullWebPropertyPayload(
        afterUpdating key: String,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool {
        definitions.contains { definition in
            if let condition = definition.displayCondition,
               Self.webDisplayConditionReferencesKey(condition, key: key) {
                return true
            }

            return definition.options.contains { option in
                guard let condition = option.displayCondition else { return false }
                return Self.webDisplayConditionReferencesKey(condition, key: key)
            }
        }
    }

    func isMeaningfulWebPropertyStaticText(_ rawTitle: String) -> Bool {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        if trimmed.contains("ugcDanger") || trimmed.contains("___") {
            return false
        }
        return trimmed.contains("<") == false || trimmed.contains("<b>") || trimmed.contains("<span")
    }

    func shouldSuppressNoisyWebPropertyControl(_ definition: SteamWorkshopWebPropertyDefinition) -> Bool {
        let normalizedKey = definition.key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedKey.isEmpty == false else { return false }

        let suppressedExactKeys: Set<String> = [
            "fps",
            "userid",
            "ugcid",
            "contentrating",
            "contentwarning",
            "previewmode",
            "supportsaudioprocessing",
            "internal"
        ]
        if suppressedExactKeys.contains(normalizedKey) {
            return true
        }

        // 抑制只看内部 key：title 是作者展示文本或本地化译文，用它做片段匹配会误杀
        // 合法用户属性（例如 key 为 showhud、标题写成 "Show HUD & Diagnostics" 的开关），
        // 而属性值本来就会全量注入 payload，隐藏只会让用户看不到、改不了。
        let suppressedKeyFragments = [
            "ugc",
            "contentwarning",
            "contentrating",
            "previewmode",
            "debug",
            "diagnostic"
        ]

        return suppressedKeyFragments.contains { fragment in
            normalizedKey.contains(fragment)
        }
    }

    func isMeaningfulWebPropertyGroupTitle(_ rawTitle: String) -> Bool {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return trimmed.contains("<") == false
    }
}
