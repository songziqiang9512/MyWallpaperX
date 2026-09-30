import Foundation

struct CachedWebValidationReport {
    let signature: String
    let report: SteamWorkshopWebValidationReport
}

struct CachedWebRuntimeModel {
    let signature: String
    let model: ResolvedWebRuntimeModel
}

extension SteamWorkshopService {
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
    }

    func invalidateAllCachedWebRuntime() {
        webValidationReportCache.removeAll()
        webRuntimeModelCache.removeAll()
    }
}
