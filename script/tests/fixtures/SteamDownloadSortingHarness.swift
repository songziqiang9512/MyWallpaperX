import Foundation

struct SteamWorkshopBrowserItem: Codable { let id: String }
// MODELS
@MainActor final class SteamWorkshopService {
    // METHODS
}
@main struct SteamDownloadSortingHarness {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sample = root.appendingPathComponent("sample", isDirectory: true)
        let nested = sample.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let entry = sample.appendingPathComponent("scene.pkg")
        try Data(repeating: 1, count: 1_048_576).write(to: entry)
        try Data([2]).write(to: nested.appendingPathComponent("extra.bin"))
        func snapshot(_ fetched: TimeInterval, first: Date? = nil) -> SteamWorkshopDownloadMetadataSnapshot {
            var value = SteamWorkshopDownloadMetadataSnapshot(fetchedAt: Date(timeIntervalSince1970: fetched),
                item: .init(id: "1"), sourceVideoRelativePath: nil, previewRelativePath: nil,
                exportedVideoURL: nil, legacyFolderURL: sample)
            value.firstDownloadedAt = first
            return value
        }
        var checks: [String: Bool] = [:]
        let first = Date(timeIntervalSince1970: 100)
        let saved = snapshot(200, first: first)
        let original = SteamWorkshopService.localDownloadStatistics(metadata: saved, sampleDirectory: sample, standaloneFile: entry)
        checks["sampleStatisticsIncludeNestedFiles"] = original.bytes == 1_048_577
        checks["detailTextAndSortShareExactTotal"] = original.sizeText == SteamWorkshopService.fileSizeText(forBytes: 1_048_577)
        let changed = Date().addingTimeInterval(3600)
        try FileManager.default.setAttributes([.modificationDate: changed], ofItemAtPath: entry.path)
        try FileManager.default.setAttributes([.modificationDate: changed], ofItemAtPath: sample.path)
        let after = SteamWorkshopService.localDownloadStatistics(metadata: saved, sampleDirectory: sample, standaloneFile: entry)
        checks["fileAndDirectoryEditsDoNotChangeFirstDownloadDate"] = original.createdAt == first && after.createdAt == first
        try Data([2, 3]).write(to: nested.appendingPathComponent("extra.bin"))
        let larger = SteamWorkshopService.localDownloadStatistics(metadata: saved, sampleDirectory: sample, standaloneFile: entry)
        checks["subDisplayPrecisionBytesRemainDistinct"] = larger.bytes == 1_048_578 && larger.bytes != original.bytes
            && larger.sizeText == original.sizeText
        let video = root.appendingPathComponent("standalone.mp4")
        try Data(repeating: 4, count: 31).write(to: video)
        let independent = SteamWorkshopService.localDownloadStatistics(metadata: nil, sampleDirectory: nil, standaloneFile: video)
        checks["standaloneVideoDoesNotSumSharedLibraryDirectory"] = independent.bytes == 31
        let legacyBefore = SteamWorkshopService.localDownloadStatistics(metadata: nil, sampleDirectory: sample, standaloneFile: nil)
        try FileManager.default.setAttributes([.modificationDate: changed.addingTimeInterval(100)], ofItemAtPath: sample.path)
        let legacyAfter = SteamWorkshopService.localDownloadStatistics(metadata: nil, sampleDirectory: sample, standaloneFile: nil)
        checks["legacyUsesCreationDateInsteadOfModificationDate"] = legacyBefore.createdAt != nil && legacyBefore.createdAt == legacyAfter.createdAt
        let service = SteamWorkshopService()
        let metadataURL = root.appendingPathComponent("1.json")
        service.writeDownloadMetadataSnapshot(saved, to: metadataURL)
        service.writeDownloadMetadataSnapshot(snapshot(900, first: changed), to: metadataURL)
        let persisted = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: Data(contentsOf: metadataURL))
        checks["metadataRefreshPreservesFirstDownloadDate"] = persisted.firstDownloadedAt == first && persisted.fetchedAt == Date(timeIntervalSince1970: 900)
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot(300))) as! [String: Any]
        legacyJSON.removeValue(forKey: "firstDownloadedAt")
        let old = try JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        checks["olderMetadataWithoutNewDateStillDecodes"] = old.firstDownloadedAt == nil
        var committed = snapshot(900)
        committed.commit = SteamWorkshopLibraryCommit(version: 3, workshopId: "1", jobId: "job", attempt: 1,
            directoryName: "1", manifestId: "manifest", contentDigest: "digest", contentType: "scene",
            entryPath: nil, committedAt: first)
        checks["existingCommitDateSurvivesFreshDetailTimestamp"] = committed.resolvedFirstDownloadDate(fallbackCreationDate: changed) == first
        let hidden = sample.appendingPathComponent(".assets", isDirectory: true)
        let package = sample.appendingPathComponent("resources.bundle", isDirectory: true)
        for directory in [hidden, package] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 0, count: 17).write(to: directory.appendingPathComponent("data.bin"))
        }
        try FileManager.default.createSymbolicLink(at: sample.appendingPathComponent("external-link"), withDestinationURL: video)
        checks["wholeSampleIncludesHiddenAndPackageResourcesWithoutFollowingLinks"] =
            SteamWorkshopService.directoryTotalBytes(at: sample) == 1_048_612
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        checks["validEmptyDirectoryIsKnownZero"] = SteamWorkshopService.directoryTotalBytes(at: empty) == 0
        let unreadable = root.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        let knownEntry = unreadable.appendingPathComponent("scene.pkg")
        try Data([1]).write(to: knownEntry)
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: unreadable.path)
        let inaccessible = SteamWorkshopService.localDownloadStatistics(metadata: nil, sampleDirectory: unreadable, standaloneFile: knownEntry)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        checks["unreadableDirectoryRemainsUnknownWithoutPartialFileFallback"] = inaccessible.bytes == nil && inaccessible.sizeText == "未知大小"
        let missingDirectory = root.appendingPathComponent("absent", isDirectory: true)
        checks["missingDirectoryRemainsUnknown"] = SteamWorkshopService.directoryTotalBytes(at: missingDirectory) == nil
        let missing = SteamWorkshopService.localDownloadStatistics(metadata: nil, sampleDirectory: nil, standaloneFile: nil)
        checks["unavailableStatisticsRemainUnknown"] = missing.createdAt == nil && missing.bytes == nil && missing.sizeText == "未知大小"
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
