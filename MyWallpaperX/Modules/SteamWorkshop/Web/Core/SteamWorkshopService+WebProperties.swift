import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func shouldRenderWebPropertyControl(
        _ definition: SteamWorkshopWebPropertyDefinition,
        staticContentSummary: ResolvedWebStaticContentSummary? = nil
    ) -> Bool {
        if shouldSuppressNoisyWebPropertyControl(definition) {
            return false
        }

        if definition.key.caseInsensitiveCompare("schemecolor") == .orderedSame,
           definition.order <= 1,
           let staticContentSummary,
           staticContentSummary.referencesSchemeColorUserProperty == false,
           staticContentSummary.hasUncertainUserPropertyUsage == false {
            return false
        }

        switch definition.kind {
        case .label:
            return isMeaningfulWebPropertyStaticText(definition.title)
        case .group:
            return isMeaningfulWebPropertyGroupTitle(definition.title)
        case .unknown:
            return false
        case .slider, .color, .toggle, .text, .combo, .file, .directory:
            return true
        }
    }

    func isPrimaryWebPropertyControl(_ definition: SteamWorkshopWebPropertyDefinition) -> Bool {
        switch definition.kind {
        case .slider, .color, .toggle, .combo, .file, .directory:
            return true
        case .text:
            let normalizedKey = definition.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedTitle = definition.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let primaryFragments = [
                "speed", "size", "scale", "opacity", "color", "colour", "volume",
                "intensity", "zoom", "blur", "radius", "width", "height", "count",
                "amount", "strength", "brightness", "contrast", "saturation"
            ]
            return primaryFragments.contains { fragment in
                normalizedKey.contains(fragment) || normalizedTitle.contains(fragment)
            }
        case .label, .group, .unknown:
            return false
        }
    }

    func previewWebPropertyValue(_ value: SteamWorkshopWebPropertyValue, for definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) {
        guard isActiveWebRecord(record) else { return }
        let deltaValue = resolvedWebRuntimeValue(
            forKey: definition.key,
            definition: definition,
            rawValue: value,
            record: record
        )
        let deltaJSON = resolvedWebRuntimePropertyPayloadJSON(
            for: definition,
            rawValue: value,
            runtimeValue: deltaValue,
            visibleOptions: visibleWebPropertyOptions(for: definition, record: record),
            record: record
        )
        WallpaperEngine.shared.updateCurrentWebWallpaperProperties(deltaJSON)
    }

    func updateWebPropertyValue(_ value: SteamWorkshopWebPropertyValue, for definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) {
        let baselineValue = webPropertyBaselineValues(for: record, definitions: [definition])[definition.key] ?? definition.defaultValue
        var overrides = webPropertyOverrides(for: record)
        if value == baselineValue {
            overrides.removeValue(forKey: definition.key)
        } else {
            overrides[definition.key] = value
        }
        objectWillChange.send()
        saveWebPropertyOverrides(overrides, for: record)
        updateWebPropertyBookmark(for: definition, value: value, record: record)
        invalidateCachedWebRuntime(for: record.id)

        guard isActiveWebRecord(record) else { return }
        let propertyDefinitions = webPropertyDefinitions(for: record)
        let committedValue = currentWebPropertyValue(for: definition, record: record)
        if shouldRefreshFullWebPropertyPayload(
            afterUpdating: definition.key,
            definitions: propertyDefinitions
        ) {
            WallpaperEngine.shared.updateCurrentWebWallpaperProperties(
                effectiveWebPropertiesJSONString(
                    for: record,
                    definitions: propertyDefinitions
                )
            )
            return
        }

        let deltaValue = resolvedWebRuntimeValue(
            forKey: definition.key,
            definition: definition,
            rawValue: committedValue,
            record: record
        )
        let deltaJSON = resolvedWebRuntimePropertyPayloadJSON(
            for: definition,
            rawValue: committedValue,
            runtimeValue: deltaValue,
            visibleOptions: visibleWebPropertyOptions(for: definition, record: record),
            record: record
        )
        WallpaperEngine.shared.updateCurrentWebWallpaperProperties(deltaJSON)
    }

    func currentWebPropertyValue(for definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebPropertyValue {
        effectiveWebPropertyValues(for: record, definitions: [definition])[definition.key] ?? definition.defaultValue
    }

    func resolveAccessibleWebPropertyURL(for definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) -> URL? {
        guard definition.kind == .file || definition.kind == .directory else { return nil }
        let effectiveValue = currentWebPropertyValue(for: definition, record: record)
        return resolveAccessibleWebPropertyURL(for: definition, rawValue: effectiveValue, record: record)
    }

    func resolveAccessibleWebPropertyURL(
        for definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) -> URL? {
        guard definition.kind == .file || definition.kind == .directory else { return nil }
        return resolvedWebRuntimeAssetURL(forKey: definition.key, definition: definition, rawValue: rawValue, record: record)
    }

    func isActiveWebRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        guard record.contentType == .web,
              WallpaperEngine.shared.currentPlaybackContentKind == .web else {
            return false
        }

        if let currentRecordID = WallpaperEngine.shared.currentWebRecordID {
            return currentRecordID == record.id
        }

        guard let entryURL = record.webEntryURL,
              let currentPath = WallpaperEngine.shared.currentContentPath else {
            return false
        }

        return currentPath == entryURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func resetWebPropertyValues(for record: SteamWorkshopDownloadRecord) {
        objectWillChange.send()
        saveWebPropertyOverrides([:], for: record)
        clearWebPropertyBookmarks(for: record)
        invalidateCachedWebRuntime(for: record.id)
        guard isActiveWebRecord(record) else { return }
        WallpaperEngine.shared.updateCurrentWebWallpaperProperties(effectiveWebPropertiesJSONString(for: record))
    }

    func visibleWebPropertyOptions(for definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) -> [SteamWorkshopWebPropertyOption] {
        let definitions = webPropertyDefinitions(for: record)
        let values = effectiveWebPropertyValues(for: record, definitions: definitions)
        return visibleWebPropertyOptions(
            for: definition,
            values: values,
            definitions: definitions
        )
    }

    nonisolated func visibleWebPropertyOptions(
        for definition: SteamWorkshopWebPropertyDefinition,
        values: [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> [SteamWorkshopWebPropertyOption] {
        definition.options.filter { option in
            guard let condition = option.displayCondition else { return true }
            return Self.evaluateWebDisplayCondition(
                condition,
                values: values,
                definitions: definitions
            )
        }
    }

    func shouldDisplayWebProperty(_ definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord) -> Bool {
        guard let condition = definition.displayCondition else { return true }
        let definitions = webPropertyDefinitions(for: record)
        let values = effectiveWebPropertyValues(for: record, definitions: definitions)
        return Self.evaluateWebDisplayCondition(
            condition,
            values: values,
            definitions: definitions
        )
    }

    nonisolated func shouldDisplayWebProperty(
        _ definition: SteamWorkshopWebPropertyDefinition,
        values: [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool {
        guard let condition = definition.displayCondition else { return true }
        return Self.evaluateWebDisplayCondition(
            condition,
            values: values,
            definitions: definitions
        )
    }
}
