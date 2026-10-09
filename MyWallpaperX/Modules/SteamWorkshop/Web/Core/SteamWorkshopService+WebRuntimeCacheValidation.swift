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
        // 会话新鲜清单快速路径：本会话后台保存段写入清单时刚完成同源签名
        // 扫描，会话内校验免再扫（扫描是 mtime 键之外最强的资源级校验，
        // 只对跨会话清单逐次执行——外部改动检测语义不变；上方 mtime/路径
        // 等廉价键对本会话清单仍然逐项生效）。
        let manifestIsSessionFresh = manifest.generatedAt >= webRuntimeCacheSessionStartDate
        if manifestIsSessionFresh == false,
           manifest.resourceSignature != webRuntimeResourceSignature(for: record) {
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

    /// 运行时缓存清单的纯比对：输入快照与实时签名都由调用方给定（扫描在
    /// 后台完成后传入），本函数不做任何 IO，可在任意线程执行。
    nonisolated static func isRuntimeManifestValid(
        _ manifest: SteamWorkshopWebRuntimeCacheManifest,
        inputs: WebRuntimeCacheManifestInputs,
        liveResourceSignature: SteamWorkshopWebRuntimeResourceSignature?
    ) -> Bool {
        if manifest.language != inputs.language {
            return false
        }
        if manifest.projectModifiedAt != inputs.projectModifiedAt {
            return false
        }
        if manifest.propertySourceRecordID != inputs.propertySourceRecordID {
            return false
        }
        if manifest.propertySourceProjectModifiedAt != inputs.propertySourceProjectModifiedAt {
            return false
        }
        if manifest.resolvedEntryModifiedAt != inputs.resolvedEntryModifiedAt {
            return false
        }
        if manifest.resourceSignature != liveResourceSignature {
            return false
        }
        if manifest.overridesSignature != inputs.overridesSignature {
            return false
        }
        if inputs.currentEntryPath != manifest.execution.resolvedEntryPath {
            return false
        }
        if inputs.currentRootPath != manifest.execution.effectiveRootPath {
            return false
        }
        return true
    }
}
