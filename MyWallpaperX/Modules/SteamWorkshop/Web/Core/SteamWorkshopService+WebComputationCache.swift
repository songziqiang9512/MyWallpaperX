import Foundation

struct CachedWebLaunchEligibility {
    let signature: String
    let isValid: Bool
}

struct CachedWebProjectDescriptor {
    let signature: String
    let descriptor: ResolvedWebProjectDescriptor
}

extension SteamWorkshopService {
    /// descriptor 记忆缓存键：只含影响 descriptor 内容的字段（项目/属性源/
    /// 入口三个 mtime、入口与根路径、依赖态、语言）。descriptor 不含用户
    /// 覆盖（effectiveWebPropertyValues 在消费侧叠加），覆盖变化不进键；
    /// 播放失败字段与 descriptor 内容无关，同样不进键。
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

    func invalidateCachedWebRuntime(for recordID: String) {
        webLaunchEligibilityCache.removeValue(forKey: recordID)
        webProjectDescriptorCache.removeValue(forKey: recordID)
    }

    func invalidateAllCachedWebRuntime() {
        webLaunchEligibilityCache.removeAll()
        webProjectDescriptorCache.removeAll()
    }
}
