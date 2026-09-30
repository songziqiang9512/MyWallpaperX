import Foundation

extension SteamWorkshopService {
    func webRuntimeRequiresLiveResourceResolution(for record: SteamWorkshopDownloadRecord) -> Bool {
        let overrides = webPropertyOverrides(for: record)
        guard !overrides.isEmpty else { return false }
        return webPropertyDefinitions(for: record).contains { definition in
            guard definition.kind == .file || definition.kind == .directory else {
                return false
            }
            if hasWebPropertyBookmark(forKey: definition.key, record: record) {
                return true
            }
            let path = overrides[definition.key]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.hasPrefix("/")
        }
    }

    func isWebAnalysisCacheManifestValid(
        _ manifest: SteamWorkshopWebAnalysisCacheManifest,
        for record: SteamWorkshopDownloadRecord
    ) -> Bool {
        if manifest.language != Self.resolvedWebWallpaperLanguage() {
            return false
        }
        if manifest.projectModifiedAt != webRuntimeCacheProjectModifiedAt(for: record) {
            return false
        }
        if manifest.propertySourceRecordID != webPropertyDefinitionSourceRecord(for: record)?.id {
            return false
        }
        if manifest.propertySourceProjectModifiedAt != webRuntimeCachePropertySourceProjectModifiedAt(for: record) {
            return false
        }
        if manifest.resolvedEntryModifiedAt != webRuntimeCacheResolvedEntryModifiedAt(for: record) {
            return false
        }
        if manifest.resourceSignature != webRuntimeResourceSignature(for: record) {
            return false
        }
        let currentEntryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let cachedEntryPath = manifest.analysis.resolvedEntryPath
        if currentEntryPath != cachedEntryPath {
            return false
        }
        let currentRootPath: String = if let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL {
            effectiveWebRootURL(for: record, entryURL: entryURL).path
        } else {
            ""
        }
        let cachedRootPath = manifest.analysis.effectiveRootPath
        if currentRootPath != cachedRootPath {
            return false
        }
        return true
    }

    func isWebRuntimeCacheManifestValid(
        _ manifest: SteamWorkshopWebRuntimeCacheManifest,
        for record: SteamWorkshopDownloadRecord
    ) -> Bool {
        if manifest.language != Self.resolvedWebWallpaperLanguage() {
            return false
        }
        if manifest.projectModifiedAt != webRuntimeCacheProjectModifiedAt(for: record) {
            return false
        }
        if manifest.propertySourceRecordID != webPropertyDefinitionSourceRecord(for: record)?.id {
            return false
        }
        if manifest.propertySourceProjectModifiedAt != webRuntimeCachePropertySourceProjectModifiedAt(for: record) {
            return false
        }
        if manifest.resolvedEntryModifiedAt != webRuntimeCacheResolvedEntryModifiedAt(for: record) {
            return false
        }
        if manifest.resourceSignature != webRuntimeResourceSignature(for: record) {
            return false
        }
        if manifest.overridesSignature != webRuntimeCacheOverridesSignature(for: record) {
            return false
        }
        let currentEntryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let cachedEntryPath = manifest.execution.resolvedEntryPath
        if currentEntryPath != cachedEntryPath {
            return false
        }
        let currentRootPath: String = if let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL {
            effectiveWebRootURL(for: record, entryURL: entryURL).path
        } else {
            ""
        }
        let cachedRootPath = manifest.execution.effectiveRootPath
        if currentRootPath != cachedRootPath {
            return false
        }
        return true
    }
}
