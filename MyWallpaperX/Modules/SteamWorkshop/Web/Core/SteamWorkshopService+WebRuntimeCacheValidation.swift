import Foundation

extension SteamWorkshopService {
    func webRuntimeRequiresLiveResourceResolution(for record: SteamWorkshopDownloadRecord) -> Bool {
        let overrides = webPropertyOverrides(for: record)
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

    /// 分析清单的廉价键比对（语言/三 mtime/属性源 ID/入口与根路径）：
    /// 无 IO，先于签名扫描短路（与 HEAD 校验序一致）。
    nonisolated static func analysisManifestCheapFieldsMatch(
        _ manifest: SteamWorkshopWebAnalysisCacheManifest,
        inputs: WebRuntimeCacheManifestInputs
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
        if inputs.currentEntryPath != manifest.analysis.resolvedEntryPath {
            return false
        }
        if inputs.currentRootPath != manifest.analysis.effectiveRootPath {
            return false
        }
        return true
    }

    /// 运行时清单先比较已有廉价字段，失配时不扫描资源。版本与 record ID
    /// 由解码入口检查；字段匹配后，调用方仍须验证实时资源签名。
    nonisolated static func runtimeManifestCheapFieldsMatch(
        _ manifest: SteamWorkshopWebRuntimeCacheManifest,
        inputs: WebRuntimeCacheManifestInputs
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
