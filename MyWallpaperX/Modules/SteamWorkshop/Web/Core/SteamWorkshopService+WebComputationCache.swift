import Foundation

struct CachedWebLaunchEligibility {
    let signature: String
    let isValid: Bool
}

#if DEBUG
struct CachedWebValidationReport {
    let signature: String
    let report: SteamWorkshopWebValidationReport
}

#endif

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
#if DEBUG
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

#endif

    func invalidateCachedWebRuntime(for recordID: String) {
        webLaunchEligibilityCache.removeValue(forKey: recordID)
#if DEBUG
        webValidationReportCache.removeValue(forKey: recordID)
#endif
        webProjectDescriptorCache.removeValue(forKey: recordID)
    }

    func invalidateAllCachedWebRuntime() {
        webLaunchEligibilityCache.removeAll()
#if DEBUG
        webValidationReportCache.removeAll()
#endif
        webProjectDescriptorCache.removeAll()
    }
}
