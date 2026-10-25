import AppKit
import Combine
import Foundation

actor DownloadedSourceProbe {
    static let shared = DownloadedSourceProbe()
    var scans = 0, metadata = 0
    var holdNext = false, holdMetadata = false
    var holdFailure = false
    var heldMetadata: CheckedContinuation<Void, Never>?
    var held: CheckedContinuation<Void, Never>?
    var heldFailure: CheckedContinuation<Void, Never>?
    func startedScan() async throws {
        scans += 1
        if holdFailure {
            holdFailure = false
            await withCheckedContinuation { heldFailure = $0 }
            throw CocoaError(.fileReadNoPermission)
        }
    }
    func holdOneFailedScan() { holdFailure = true }
    var isHoldingFailure: Bool { heldFailure != nil }
    func releaseFailure() { let value = heldFailure; heldFailure = nil; value?.resume() }
    func metadataRead() async {
        metadata += 1
        if holdMetadata {
            holdMetadata = false
            await withCheckedContinuation { heldMetadata = $0 }
        }
    }
    func holdOneMetadata() { holdMetadata = true }
    var isHoldingMetadata: Bool { heldMetadata != nil }
    func releaseMetadata() { let value = heldMetadata; heldMetadata = nil; value?.resume() }
    func holdOneCompletedScan() { holdNext = true }
    func finishedScan() async {
        guard holdNext else { return }
        holdNext = false
        await withCheckedContinuation { held = $0 }
    }
    var isHolding: Bool { held != nil }
    func release() { let continuation = held; held = nil; continuation?.resume() }
}

@MainActor enum DownloadedDeletionLeaf {
    static var failingNames = Set<String>()
    static var synchronizationFailureNames = Set<String>()
    static func remove(_ prepared: WallpaperSourceFileDeletion.Prepared) -> WallpaperSourceFileDeletion.Outcome {
        if failingNames.contains(prepared.url.lastPathComponent) {
            return .init(sourceFileDeleted: false, failureMessage: "controlled file-write permission failure")
        }
        let result = WallpaperSourceFileDeletion.remove(prepared)
        if result.succeeded && synchronizationFailureNames.contains(prepared.url.lastPathComponent) {
            return .init(sourceFileDeleted: true, failureMessage: "controlled synchronization acknowledgement failure after actual unlink")
        }
        return result
    }
}
extension OnlineLibraryVideoItem {
    init(id: Int) {
        self.init(id: id, pageURL: "https://fixture.invalid/\(id)", tags: "", duration: 0, user: "",
            videos: .init(large: .init(url: "https://fixture.invalid/\(id).mp4", width: 0, height: 0, size: 0, thumbnail: ""),
                          medium: nil, small: nil, tiny: nil))
    }
}
struct ImportedVideoPlaybackAdmission { let reference: WallpaperReference }
enum WallpaperPlaybackSequence { struct Pending {} }
@MainActor struct ImportedVideoPlaybackRequest {
    let localURL: URL; let admission: ImportedVideoPlaybackAdmission
    static var posted: [Self] = []
    func post(name: Notification.Name) { Self.posted.append(self) }
}
extension Notification.Name { static let onlineVideoReadyToPlay = Self("source-ready") }

@MainActor final class OnlineLibraryService {
    static var instance: OnlineLibraryService!
    static var shared: OnlineLibraryService { instance }
    static var downloadDirectory = URL(fileURLWithPath: "/unused")
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var prepareExplicitLibraryRestoration: ((WallpaperReference) -> (() -> Void)?)?
    var prepareVideoPlaybackIntent: ((WallpaperReference, WallpaperPlaybackSequence.Pending?) -> ImportedVideoPlaybackAdmission?)?
    var networkStarts = 0
    var completesFetch = false
    func fetchAndMove(from url: URL, name: String, itemID: Int) async throws -> URL {
        networkStarts += 1
        if completesFetch {
            let destination = Self.downloadDirectory.appendingPathComponent(name)
            try Data([7, 7]).write(to: destination)
            return destination
        }
        throw CocoaError(.fileReadUnknown)
    }
    // SOURCE_FIELDS
    // SOURCE_OWNER
}

@MainActor enum OLDownloadedThumbnailStore {
    final class Cache { func cachedImage(forKey key: String) -> NSImage? { nil } }
    static let sharedCache = Cache()
}
// INSPECTOR_SNAPSHOT

@main struct OnlineDownloadedContentHarness {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func file(_ id: String, _ bytes: [UInt8] = [1, 2, 3]) throws -> URL {
            let url = root.appendingPathComponent("online_\(id).mp4")
            try Data(bytes).write(to: url)
            return url
        }
        let one = try file("1"), two = try file("2", [4, 5]), three = try file("3", [6])
        OnlineLibraryService.downloadDirectory = root
        let service = OnlineLibraryService()
        OnlineLibraryService.instance = service
        var publications: [OnlineLibraryDownloadedContentSnapshot] = []
        let publication = service.$downloadedContent.sink { publications.append($0) }
        defer { publication.cancel() }
        func failed(_ snapshot: OnlineLibraryDownloadedContentSnapshot) -> Bool {
            if case .failed(let message) = snapshot.status.phase { return !message.isEmpty }
            return false
        }
        func sameContent(_ lhs: OnlineLibraryDownloadedContentSnapshot, _ rhs: OnlineLibraryDownloadedContentSnapshot) -> Bool {
            lhs.revision == rhs.revision && lhs.entries == rhs.entries
        }
        var references: [String] = []
        service.prepareVideoPlaybackIntent = { reference, _ in references.append(reference.sourceID); return .init(reference: reference) }
        // Playback admission is a controlled boundary here; the separate real
        // admission gate verifies the original Manager ticket and async import.
        service.requestLibraryPlayback = { reference in
            _ = service.setLocalFileAsWallpaper(id: Int(reference.sourceID)!, libraryPending: .init())
        }
        var checks: [String: Bool] = [:]
        let explicitBeforeFirstScan = service.libraryContentItemForExplicitPlayback(id: 1)
        checks["explicit-action-before-first-scan-projects-canonical-file-with-unknown-metadata"] = explicitBeforeFirstScan?.reference == .init(provider: .pixabay, sourceID: "1")
            && explicitBeforeFirstScan?.capabilities.contains(.play) == true && explicitBeforeFirstScan?.locator.path == one.path
            && explicitBeforeFirstScan?.metadata.fileSizeBytes == nil && explicitBeforeFirstScan?.metadata.createdAt == nil
            && explicitBeforeFirstScan?.aliases.isEmpty == true && service.downloadedContent.revision == 0
        checks["explicit-action-for-missing-file-never-creates-a-download-or-row"] = service.libraryContentItemForExplicitPlayback(id: 999) == nil
            && service.networkStarts == 0 && service.downloadedContent.entries.isEmpty
        service.downloadAndSet(item: .init(id: 1))
        checks["first-click-during-initial-scan-plays-existing-file-without-downloading"] = service.networkStarts == 0
            && service.downloadedIDs.isEmpty && ImportedVideoPlaybackRequest.posted.last?.localURL == one && references == ["1"]
        await service.downloadedContentTask?.value
        checks["single-source-publishes-real-files-ids-dates-and-shared-identity"] = service.downloadedContent.entries.count == 3 && service.downloadedIDs == [1, 2, 3]
            && service.downloadedContent.entries.allSatisfy {
                $0.creationDate != nil && $0.modificationDate != nil && $0.thumbnailSourceKey == OnlineLibraryDownloadedFileIdentity.key(for: $0.localURL)
            }
        checks["initial-success-publishes-ready-with-the-same-atomic-entries-and-success-fact"] =
            publications.first?.status == .initial && service.initialDownloadedScanCompleted
            && service.downloadedContent.status == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)
            && publications.last == service.downloadedContent
        let sourceRow = service.downloadedContent.entries.first { $0.id == 1 }!
        let explicitPublished = service.libraryContentItemForExplicitPlayback(id: 1)
        checks["explicit-action-reuses-source-metadata-and-never-infers-a-backing-alias"] = explicitPublished?.metadata.fileSizeBytes == Int64(sourceRow.fileSize)
            && explicitPublished?.metadata.createdAt == sourceRow.creationDate && explicitPublished?.aliases.isEmpty == true
        let relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        // The new downloads page consumes the same source values through the
        // production pure query. Progress, sorting and searching never rescan.
        func projectedIDs(_ entries: [OLDownloadedEntry]? = nil, sort: WallpaperLibrarySort,
                          ascending: Bool, search: String = "") throws -> [Int] {
            var catalog = WallpaperLibraryCatalog()
            catalog.downloads = (entries ?? service.downloadedContent.entries).compactMap { entry in
                PixabayLibraryContentProjection.project(download: entry, facts: .init(
                    isPublishedLocally: true, isAvailable: entry.isAvailable,
                    canPlay: entry.isAvailable, canDelete: true, canQuickLook: true,
                    localURL: entry.localURL, resourceRevision: entry.thumbnailSourceKey))
            }
            var query = WallpaperLibraryQueryState()
            query.sort = sort; query.ascending = ascending; query.search = search
            return try WallpaperLibraryQuery.project(page: .downloads, state: query, catalog: catalog,
                relationships: relationships).items.compactMap { Int($0.providerReference.sourceID) }
        }
        let scans = await DownloadedSourceProbe.shared.scans, metadata = await DownloadedSourceProbe.shared.metadata
        for index in 0..<20 { service.downloadProgressByID = [1: Double(index) / 20] }
        checks["sorting-consumes-cached-size-with-no-source-scan"] = try projectedIDs(sort: .fileSize, ascending: false) == [1, 2, 3]
        checks["name-sort-and-search-remain-pure-value-projections"] = try projectedIDs(sort: .name, ascending: false) == [3, 2, 1]
        checks["search-keeps-the-existing-filename-rule"] = try projectedIDs(sort: .name, ascending: false, search: "online_2") == [2]
        let inspector = OnlineLibraryDownloadsInspectorSnapshot.load(itemID: 2)
        checks["inspector-consumes-the-same-resolved-record-without-av-or-stat"] = inspector?.fileURL == two
            && inspector?.creationDateText != "未知"
        let afterScans = await DownloadedSourceProbe.shared.scans, afterMetadata = await DownloadedSourceProbe.shared.metadata
        checks["progress-sort-search-and-inspector-do-not-trigger-scanning-or-metadata"] = afterScans == scans && afterMetadata == metadata
        let beforeWarmRefresh = service.downloadedContent, beforeWarmIDs = service.downloadedIDs
        service.refreshDownloadedContent()
        checks["warm-refresh-immediately-publishes-loading-without-revoking-entries-or-success"] =
            sameContent(service.downloadedContent, beforeWarmRefresh) && service.downloadedIDs == beforeWarmIDs
            && service.downloadedContent.status == .init(phase: .loading, hasSuccessfulScan: true)
        await service.downloadedContentTask?.value
        checks["unchanged-refresh-reuses-av-metadata-by-the-shared-file-key"] = await DownloadedSourceProbe.shared.metadata == metadata
        checks["phase-only-ready-restoration-keeps-the-original-content-revision"] =
            sameContent(service.downloadedContent, beforeWarmRefresh)
            && service.downloadedContent.status == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)
        let firstKey = service.downloadedContent.entries.first { $0.id == 1 }!.thumbnailSourceKey
        try Data([7, 8, 9]).write(to: one)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: one.path)
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        let replacementMetadata = await DownloadedSourceProbe.shared.metadata
        checks["same-url-replacement-publishes-new-cache-identity-and-rereads-only-that-file"] = service.downloadedContent.entries.first { $0.id == 1 }!.thumbnailSourceKey != firstKey
            && replacementMetadata == metadata + 1
        let beforeRacingRead = service.downloadedContent
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_001)], ofItemAtPath: one.path)
        await DownloadedSourceProbe.shared.holdOneMetadata()
        service.refreshDownloadedContent()
        let metadataDeadline = Date().addingTimeInterval(3)
        while !(await DownloadedSourceProbe.shared.isHoldingMetadata), Date() < metadataDeadline { try? await Task.sleep(for: .milliseconds(3)) }
        let metadataHeld = await DownloadedSourceProbe.shared.isHoldingMetadata
        precondition(metadataHeld)
        try Data([10, 11, 12, 13]).write(to: one)
        await DownloadedSourceProbe.shared.releaseMetadata(); await service.downloadedContentTask?.value
        checks["a-file-replaced-during-av-read-never-publishes-mixed-revision-metadata"] = sameContent(service.downloadedContent, beforeRacingRead)
            && failed(service.downloadedContent) && service.downloadedContent.status.hasSuccessfulScan
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        let dateEntries = service.downloadedContent.entries.enumerated().map { index, entry in
            var copy = entry
            copy.creationDate = Date(timeIntervalSince1970: Double(30 - index))
            copy.modificationDate = Date(timeIntervalSince1970: Double(index))
            return copy
        }
        checks["date-sorts-use-source-facts-and-retain-both-direction-rules"] = try projectedIDs(dateEntries, sort: .createdAt, ascending: true) == [3, 2, 1]
            && projectedIDs(dateEntries, sort: .modifiedAt, ascending: false) == [3, 2, 1]
        let preserved = service.downloadedContent, preservedIDs = service.downloadedIDs
        OnlineLibraryService.downloadDirectory = one // real directory-read failure
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        checks["scan-failure-preserves-last-successful-snapshot-and-download-ids"] = sameContent(service.downloadedContent, preserved)
            && service.downloadedIDs == preservedIDs && failed(service.downloadedContent)
            && service.downloadedContent.status.hasSuccessfulScan
        let initiallyFailed = OnlineLibraryService()
        await initiallyFailed.downloadedContentTask?.value
        checks["initial-scan-failure-is-explicit-rather-than-a-successful-empty-publication"] = initiallyFailed.downloadedContent.revision == 0
            && failed(initiallyFailed.downloadedContent) && initiallyFailed.downloadedIDs.isEmpty
            && !initiallyFailed.downloadedContent.status.hasSuccessfulScan && initiallyFailed.initialDownloadedScanCompleted
        let postsBeforeFailureDownload = ImportedVideoPlaybackRequest.posted.count
        initiallyFailed.download(item: .init(id: 999))
        let failureDownloadDeadline = Date().addingTimeInterval(3)
        while (initiallyFailed.networkStarts == 0 || !initiallyFailed.downloadingIDs.isEmpty), Date() < failureDownloadDeadline {
            try? await Task.sleep(for: .milliseconds(3))
        }
        checks["initial-scan-failure-ends-the-original-download-wait-without-autoplay-or-fake-readiness"] =
            initiallyFailed.networkStarts == 1 && initiallyFailed.downloadingIDs.isEmpty
            && initiallyFailed.downloadedIDs.isEmpty && failed(initiallyFailed.downloadedContent)
            && !initiallyFailed.downloadedContent.status.hasSuccessfulScan
            && ImportedVideoPlaybackRequest.posted.count == postsBeforeFailureDownload
        OnlineLibraryService.downloadDirectory = root
        let unavailableDirectory = root.appendingPathExtension("offline")
        try FileManager.default.moveItem(at: root, to: unavailableDirectory)
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        checks["a-disappeared-source-directory-does-not-publish-a-false-empty-library"] = sameContent(service.downloadedContent, preserved)
            && service.downloadedIDs == preservedIDs && failed(service.downloadedContent)
            && service.downloadedContent.status.hasSuccessfulScan
        try FileManager.default.moveItem(at: unavailableDirectory, to: root)

        // Make the old real AV read stale, then let a newer complete scan win.
        // The cancelled predecessor must not replace ready with its late error.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_002)], ofItemAtPath: one.path)
        await DownloadedSourceProbe.shared.holdOneMetadata()
        service.refreshDownloadedContent()
        let staleMetadataTask = service.downloadedContentTask
        let staleMetadataDeadline = Date().addingTimeInterval(3)
        while !(await DownloadedSourceProbe.shared.isHoldingMetadata), Date() < staleMetadataDeadline {
            try? await Task.sleep(for: .milliseconds(3))
        }
        let staleMetadataHeld = await DownloadedSourceProbe.shared.isHoldingMetadata
        precondition(staleMetadataHeld)
        try Data([14, 15, 16, 17, 18]).write(to: one)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_003)], ofItemAtPath: one.path)
        service.refreshDownloadedContent()
        await service.downloadedContentTask?.value
        let winningScan = service.downloadedContent, winningIDs = service.downloadedIDs
        await DownloadedSourceProbe.shared.releaseMetadata()
        await staleMetadataTask?.value
        checks["a-cancelled-old-generation-metadata-read-cannot-replace-current-ready-status-or-entries"] =
            service.downloadedContent == winningScan && service.downloadedIDs == winningIDs
            && service.downloadedContent.status == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)

        await DownloadedSourceProbe.shared.holdOneFailedScan()
        service.refreshDownloadedContent()
        let staleFailureTask = service.downloadedContentTask
        let staleFailureDeadline = Date().addingTimeInterval(3)
        while !(await DownloadedSourceProbe.shared.isHoldingFailure), Date() < staleFailureDeadline {
            try? await Task.sleep(for: .milliseconds(3))
        }
        let staleFailureHeld = await DownloadedSourceProbe.shared.isHoldingFailure
        precondition(staleFailureHeld)
        service.refreshDownloadedContent()
        await service.downloadedContentTask?.value
        let beforeLateFailure = service.downloadedContent, beforeLateFailureIDs = service.downloadedIDs
        await DownloadedSourceProbe.shared.releaseFailure()
        await staleFailureTask?.value
        checks["a-late-failed-old-worker-cannot-overwrite-current-successful-status-or-content"] =
            service.downloadedContent == beforeLateFailure && service.downloadedIDs == beforeLateFailureIDs
            && service.downloadedContent.status == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)

        await DownloadedSourceProbe.shared.holdOneCompletedScan()
        service.refreshDownloadedContent()
        let oldTask = service.downloadedContentTask
        let deadline = Date().addingTimeInterval(3)
        while !(await DownloadedSourceProbe.shared.isHolding), Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
        let holding = await DownloadedSourceProbe.shared.isHolding
        precondition(holding)
        DownloadedDeletionLeaf.failingNames = [two.lastPathComponent]
        let partial = service.deleteLocalFiles(at: [one, two])
        checks["partial-delete-retains-failed-resource-bytes-id-and-reports-each-real-result"] = !FileManager.default.fileExists(atPath: one.path)
            && FileManager.default.fileExists(atPath: two.path) && service.downloadedIDs == [2, 3]
            && partial.map(\.id) == [1, 2] && partial.map(\.succeeded) == [true, false]
            && partial[1].failureMessage?.isEmpty == false
        await DownloadedSourceProbe.shared.release(); await oldTask?.value
        await service.downloadedContentTask?.value
        checks["late-scan-cannot-resurrect-a-successfully-deleted-source-row"] = !service.downloadedIDs.contains(1)
            && service.downloadedContent.entries.map(\.id) == [2, 3]
        let beforeAllFailure = service.downloadedContent
        let idsBeforeAllFailure = service.downloadedIDs
        let bytesBeforeAllFailure = try Data(contentsOf: two)
        let failed = service.deleteLocalFiles(at: [two])
        let bytesAfterAllFailure = try Data(contentsOf: two)
        checks["all-delete-failures-preserve-source-snapshot-and-bytes"] = service.downloadedContent.entries == beforeAllFailure.entries
            && service.downloadedContent.revision == beforeAllFailure.revision && service.downloadedIDs == idsBeforeAllFailure
            && service.downloadedContent.status == .init(phase: .loading, hasSuccessfulScan: true)
            && FileManager.default.fileExists(atPath: two.path) && bytesAfterAllFailure == bytesBeforeAllFailure
            && failed.count == 1 && !failed[0].succeeded
            && failed[0].failureMessage?.isEmpty == false
        await service.downloadedContentTask?.value
        let allFailureSettledReady: Bool
        if case .ready = service.downloadedContent.status.phase { allFailureSettledReady = true }
        else { allFailureSettledReady = false }
        checks["all-delete-failure-refresh-retains-the-same-content-after-ready"] = service.downloadedContent.entries == beforeAllFailure.entries
            && service.downloadedContent.revision == beforeAllFailure.revision && service.downloadedIDs == idsBeforeAllFailure
            && service.downloadedContent.status.hasSuccessfulScan && allFailureSettledReady
        DownloadedDeletionLeaf.failingNames = []
        let successful = service.deleteLocalFiles(at: [two])
        checks["successful-single-delete-publishes-only-the-remaining-source-row"] = successful.count == 1 && successful[0].succeeded
            && service.downloadedContent.entries.map(\.id) == [3] && service.downloadedIDs == [3]
        let absent = service.deleteLocalFiles(at: [two])
        checks["already-missing-delete-is-reported-as-success"] = absent.count == 1 && absent[0].succeeded && absent[0].id == 2
        await service.downloadedContentTask?.value
        let busy = service.deleteLocalFiles(at: [three], isInUse: { _ in true })
        checks["checked-delete-cannot-unlink-a-source-still-owned-by-the-original-runtime"] = busy.count == 1
            && !busy[0].succeeded && !busy[0].sourceFileDeleted && FileManager.default.fileExists(atPath: three.path)
        let outside = root.deletingLastPathComponent().appendingPathComponent("online_99.mp4")
        try Data([67]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let outsideResult = service.deleteLocalFiles(at: [outside])
        checks["checked-delete-refuses-a-valid-looking-id-outside-the-owner-directory"] = outsideResult.first?.succeeded == false
            && (try? Data(contentsOf: outside)) == Data([67])
        let link = root.appendingPathComponent("online_98.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let linkResult = service.deleteLocalFiles(at: [link])
        checks["checked-delete-refuses-symlink-and-retains-its-external-target"] = linkResult.first?.succeeded == false
            && (try? Data(contentsOf: outside)) == Data([67])
            && (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil
        try FileManager.default.removeItem(at: link)
        await service.downloadedContentTask?.value
        let uncertainURL = try file("88")
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        precondition(service.downloadedContent.entries.contains { $0.id == 88 })
        DownloadedDeletionLeaf.synchronizationFailureNames = [uncertainURL.lastPathComponent]
        let uncertain = service.deleteLocalFiles(at: [uncertainURL])
        checks["post-unlink-ack-failure-is-failed-with-real-file-effect-and-no-false-logical-success"] = uncertain.first?.succeeded == false
            && uncertain.first?.sourceFileDeleted == true && !FileManager.default.fileExists(atPath: uncertainURL.path)
            && service.downloadedContent.entries.contains { $0.id == 88 }
        DownloadedDeletionLeaf.synchronizationFailureNames = []
        await service.downloadedContentTask?.value
        checks["real-source-refresh-publishes-missing-after-post-unlink-ack-failure"] = !service.downloadedIDs.contains(88)
            && !service.downloadedContent.entries.contains { $0.id == 88 }
        _ = try file("0"); _ = try file("-1"); _ = try file("0003")
        _ = try file("33", [0])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("online_9.mp4"), withIntermediateDirectories: true)
        try Data([0]).write(to: root.appendingPathComponent(".online_4.mp4"))
        try Data([0]).write(to: root.appendingPathComponent("online_5.MP4"))
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        let duplicateWarnings: [String]
        if case .ready(let warnings) = service.downloadedContent.status.phase { duplicateWarnings = warnings }
        else { duplicateWarnings = [] }
        checks["legacy-zero-negative-leading-zero-and-case-boundaries-are-preserved"] = Set(service.downloadedContent.entries.map(\.id)) == [-1, 0, 3, 9, 33]
            && service.downloadedContent.entries.first { $0.id == 3 }?.localURL == three
            && duplicateWarnings.contains { $0.contains("多个同号文件") }
            && service.downloadedContent.status.hasSuccessfulScan
        checks["a-matching-directory-remains-visible-but-is-never-advertised-as-playable"] = !service.downloadedIDs.contains(9)
            && service.downloadedContent.entries.first { $0.id == 9 }?.isAvailable == false
        let thirtyThree = root.appendingPathComponent("online_33.mp4")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: thirtyThree.path)
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        checks["unreadable-local-file-is-not-advertised-as-available"] = service.downloadedContent.entries.first { $0.id == 33 }?.isAvailable == false
            && !service.downloadedIDs.contains(33)
        let unreadableKey = service.downloadedContent.entries.first { $0.id == 33 }?.thumbnailSourceKey
        let readsBeforePermissionRecovery = await DownloadedSourceProbe.shared.metadata
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: thirtyThree.path)
        service.refreshDownloadedContent(); await service.downloadedContentTask?.value
        let readsAfterPermissionRecovery = await DownloadedSourceProbe.shared.metadata
        checks["permission-recovery-rereads-metadata-once-even-when-size-mtime-and-key-are-unchanged"] = service.downloadedContent.entries.first { $0.id == 33 }?.thumbnailSourceKey == unreadableKey
            && service.downloadedIDs.contains(33) && readsAfterPermissionRecovery == readsBeforePermissionRecovery + 1
        let disappeared = root.appendingPathComponent("online_0.mp4")
        try FileManager.default.removeItem(at: disappeared)
        service.downloadAndSet(item: .init(id: 0))
        checks["a-stale-play-button-for-an-externally-deleted-file-never-starts-a-download-or-admits-playback"] = service.networkStarts == 0
            && ImportedVideoPlaybackRequest.posted.count == 1 && references == ["1"] && !service.downloadedIDs.contains(0)
        await service.downloadedContentTask?.value
        let remote = OnlineLibraryVideoItem(id: 101)
        service.downloadAndSet(item: remote)
        try? await Task.sleep(for: .milliseconds(10))
        checks["first-click-for-unpublished-file-only-downloads-and-does-not-claim-playback"] = service.networkStarts == 1
            && ImportedVideoPlaybackRequest.posted.count == 1 && references == ["1"]
        let initialAlternative = root.appendingPathComponent("initial-alternative", isDirectory: true)
        try FileManager.default.createDirectory(at: initialAlternative, withIntermediateDirectories: true)
        let leadingZero = initialAlternative.appendingPathComponent("online_0007.mp4")
        try Data([1]).write(to: leadingZero)
        OnlineLibraryService.downloadDirectory = initialAlternative
        let alternativeService = OnlineLibraryService()
        checks["explicit-leadingzero-file-waits-for-the-original-worker-identity"] = alternativeService.libraryContentItemForExplicitPlayback(id: 7) == nil
        alternativeService.prepareVideoPlaybackIntent = { _, _ in preconditionFailure("download-only initial lookup must not claim playback") }
        alternativeService.downloadAndSet(item: .init(id: 7))
        // Replacing the still-pending initial scan must not let its cancelled
        // predecessor release the download before the current lookup finishes.
        alternativeService.refreshDownloadedContent()
        await alternativeService.downloadedContentTask?.value
        try? await Task.sleep(for: .milliseconds(10))
        checks["initial-legacy-filename-lookup-does-not-redownload-or-autoplay-after-scan-replacement"] = alternativeService.networkStarts == 0
            && alternativeService.downloadedIDs == [7] && alternativeService.downloadingIDs.isEmpty
            && alternativeService.downloadedContent.entries.first?.localURL == leadingZero
            && !FileManager.default.fileExists(atPath: initialAlternative.appendingPathComponent("online_7.mp4").path)
        let explicitLeadingZero = alternativeService.libraryContentItemForExplicitPlayback(id: 7)
        checks["explicit-leadingzero-file-is-playable-after-original-worker-publication"] = explicitLeadingZero?.capabilities.contains(.play) == true
            && explicitLeadingZero?.locator.path == leadingZero.path && explicitLeadingZero?.reference.sourceID == "7"
        var restoreAdmissions: [WallpaperReference] = [], restoreSuccesses: [WallpaperReference] = []
        alternativeService.prepareExplicitLibraryRestoration = { reference in
            restoreAdmissions.append(reference)
            return { restoreSuccesses.append(reference) }
        }
        alternativeService.download(item: .init(id: 7))
        checks["explicit-existing-download-consumes-its-admitted-restore-receipt-without-transfer"] = restoreAdmissions.map(\.sourceID) == ["7"]
            && restoreSuccesses.map(\.sourceID) == ["7"] && alternativeService.networkStarts == 0
        alternativeService.refreshDownloadedContent(); await alternativeService.downloadedContentTask?.value
        checks["automatic-scan-never-creates-or-consumes-a-library-restore-receipt"] = restoreAdmissions.count == 1 && restoreSuccesses.count == 1
        alternativeService.download(item: .init(id: 80))
        for _ in 0..<100 where alternativeService.downloadingIDs.contains(80) { try? await Task.sleep(nanoseconds: 5_000_000) }
        checks["failed-explicit-download-never-clears-its-library-exclusion"] = restoreAdmissions.map(\.sourceID) == ["7", "80"]
            && restoreSuccesses.map(\.sourceID) == ["7"] && !alternativeService.downloadingIDs.contains(80)
        alternativeService.completesFetch = true
        alternativeService.download(item: .init(id: 81))
        for _ in 0..<100 where alternativeService.downloadingIDs.contains(81) { try? await Task.sleep(nanoseconds: 5_000_000) }
        checks["successful-explicit-download-consumes-only-the-original-success-receipt"] = restoreSuccesses.map(\.sourceID) == ["7", "81"]
            && !alternativeService.downloadingIDs.contains(81) && alternativeService.networkStarts == 2
        try FileManager.default.removeItem(at: initialAlternative.appendingPathComponent("online_81.mp4"))
        alternativeService.refreshDownloadedContent()
        await alternativeService.downloadedContentTask?.value
        let entryOnlySource = OnlineLibraryService()
        entryOnlySource.publishDownloadedContent(alternativeService.downloadedContent.entries)
        checks["a-direct-entry-publication-does-not-claim-a-completed-or-successful-full-scan"] =
            entryOnlySource.downloadedContent.revision > 0 && !entryOnlySource.downloadedContent.entries.isEmpty
            && entryOnlySource.downloadedContent.status == .initial && !entryOnlySource.initialDownloadedScanCompleted
        await entryOnlySource.downloadedContentTask?.value
        checks["the-first-real-scan-can-publish-success-after-an-entry-only-content-revision"] =
            entryOnlySource.initialDownloadedScanCompleted && entryOnlySource.downloadedContent.status.hasSuccessfulScan
            && entryOnlySource.downloadedIDs == [7]
        let empty = root.appendingPathComponent("successfully-empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        OnlineLibraryService.downloadDirectory = empty
        let emptySource = OnlineLibraryService()
        emptySource.publishDownloadedContent([])
        checks["non-scan-empty-mutation-does-not-claim-an-initial-source-publication"] = emptySource.downloadedContent.revision == 0
            && emptySource.downloadedContent.status == .initial && !emptySource.initialDownloadedScanCompleted
        await emptySource.downloadedContentTask?.value
        checks["a-successful-empty-first-scan-publishes-known-empty-once"] = emptySource.downloadedContent.revision == 1
            && emptySource.downloadedContent.entries.isEmpty
            && emptySource.downloadedContent.status == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)
        emptySource.refreshDownloadedContent(); await emptySource.downloadedContentTask?.value
        checks["unchanged-empty-refresh-does-not-publish-redundant-generations"] = emptySource.downloadedContent.revision == 1
        OnlineLibraryService.downloadDirectory = root
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
