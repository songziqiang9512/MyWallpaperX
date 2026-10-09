import Foundation

struct CachedWebValidationReport {
    let signature: String
    let report: SteamWorkshopWebValidationReport
}

struct CachedWebRuntimeModel {
    let signature: String
    let model: ResolvedWebRuntimeModel
}

struct CachedWebProjectDescriptor {
    let signature: String
    let descriptor: ResolvedWebProjectDescriptor
}

extension SteamWorkshopService {
    /// descriptor 记忆缓存键：只含影响 descriptor 内容的字段（项目/属性源/
    /// 入口三个 mtime、入口与根路径、依赖态、语言）。descriptor 不含用户
    /// 覆盖（effectiveWebPropertyValues 在消费侧叠加），覆盖变化不进键；
    /// 播放失败字段与 descriptor 内容无关，同样不进键（区别于
    /// webValidationSignature）。
    func webProjectDescriptorSignature(for record: SteamWorkshopDownloadRecord) -> String {
        let descriptorModifiedAt = webRuntimeCacheProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let propertySourceModifiedAt = webRuntimeCachePropertySourceProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryModifiedAt = webRuntimeCacheResolvedEntryModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let rootPath = record.webHostRootURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let dependencyItemID = record.dependencyItemID ?? ""
        let dependencyStatus = String(describing: record.dependencyStatus)
        return [
            record.id,
            String(descriptorModifiedAt),
            String(propertySourceModifiedAt),
            String(entryModifiedAt),
            entryPath,
            rootPath,
            dependencyItemID,
            dependencyStatus,
            Self.resolvedWebWallpaperLanguage()
        ].joined(separator: "|")
    }
    func webRuntimeComputationSignature(for record: SteamWorkshopDownloadRecord) -> String {
        let descriptorModifiedAt = webRuntimeCacheProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let propertySourceModifiedAt = webRuntimeCachePropertySourceProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryModifiedAt = webRuntimeCacheResolvedEntryModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let rootPath = record.webHostRootURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let dependencyItemID = record.dependencyItemID ?? ""
        let dependencyStatus = String(describing: record.dependencyStatus)
        let overridesData = (try? Self.webSignatureJSONEncoder.encode(webPropertyOverrides(for: record))) ?? Data()
        let overridesBase64 = overridesData.base64EncodedString()
        let failureRecordID = lastWebPlaybackFailureRecordID ?? ""
        let failurePath = lastWebPlaybackFailurePath ?? ""
        let failureMessage = lastWebPlaybackFailureMessage ?? ""
        let activeFlag = isActiveWebRecord(record) ? "1" : "0"
        return [
            record.id,
            String(descriptorModifiedAt),
            String(propertySourceModifiedAt),
            String(entryModifiedAt),
            entryPath,
            rootPath,
            dependencyItemID,
            dependencyStatus,
            overridesBase64,
            Self.resolvedWebWallpaperLanguage(),
            failureRecordID,
            failurePath,
            failureMessage,
            activeFlag
        ].joined(separator: "|")
    }

    func webValidationSignature(for record: SteamWorkshopDownloadRecord) -> String {
        let descriptorModifiedAt = webRuntimeCacheProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let propertySourceModifiedAt = webRuntimeCachePropertySourceProjectModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryModifiedAt = webRuntimeCacheResolvedEntryModifiedAt(for: record)?.timeIntervalSince1970 ?? 0
        let entryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let rootPath = record.webHostRootURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let dependencyItemID = record.dependencyItemID ?? ""
        let dependencyStatus = String(describing: record.dependencyStatus)
        let failureRecordID = lastWebPlaybackFailureRecordID ?? ""
        let failurePath = lastWebPlaybackFailurePath ?? ""
        let failureMessage = lastWebPlaybackFailureMessage ?? ""
        return [
            record.id,
            String(descriptorModifiedAt),
            String(propertySourceModifiedAt),
            String(entryModifiedAt),
            entryPath,
            rootPath,
            dependencyItemID,
            dependencyStatus,
            Self.resolvedWebWallpaperLanguage(),
            failureRecordID,
            failurePath,
            failureMessage
        ].joined(separator: "|")
    }

    func invalidateCachedWebRuntime(for recordID: String) {
        webValidationReportCache.removeValue(forKey: recordID)
        webRuntimeModelCache.removeValue(forKey: recordID)
        webProjectDescriptorCache.removeValue(forKey: recordID)
    }

    func invalidateAllCachedWebRuntime() {
        webValidationReportCache.removeAll()
        webRuntimeModelCache.removeAll()
        webProjectDescriptorCache.removeAll()
    }
}
