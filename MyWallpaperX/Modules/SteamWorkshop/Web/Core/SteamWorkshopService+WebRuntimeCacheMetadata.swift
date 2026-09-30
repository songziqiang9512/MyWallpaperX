import Foundation

extension SteamWorkshopService {
    /// 签名只被逐字节比较、从不被解码，因此字典键序必须与进程哈希种子无关。
    static let webSignatureJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func webRuntimeCacheOverridesSignature(for record: SteamWorkshopDownloadRecord) -> Data? {
        let overrides = webPropertyOverrides(for: record)
        guard !overrides.isEmpty else { return nil }
        return try? Self.webSignatureJSONEncoder.encode(overrides)
    }

    func webRuntimeCacheProjectModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let projectFileURL = record.projectFileURL else { return nil }
        return (try? projectFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func webRuntimeCachePropertySourceProjectModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let sourceRecord = webPropertyDefinitionSourceRecord(for: record),
              let projectFileURL = sourceRecord.projectFileURL else { return nil }
        return (try? projectFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func webRuntimeCacheResolvedEntryModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let entryURL = record.webEntryURL else { return nil }
        return (try? entryURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
