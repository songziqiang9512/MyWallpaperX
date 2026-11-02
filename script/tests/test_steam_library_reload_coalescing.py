"""Real reloadInstalledItems scan protocol: one scan in flight, coalesced catch-up, final projection kept.

Drives the production reload entry against a real metadata index (real
loadManagedDownloadSnapshots pipeline) with an instrumented scan body that can
be held in flight and counted. Asserts the observable contract: overlapping
reloads never run concurrent whole-library scans, every coalesced request is
answered by exactly one catch-up scan launched from the newest state, stale
results never overwrite it, and interleaved deletions are not lost.
"""
import hashlib
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES

COALESCING_MEMBERS = (
    '    private func startInstalledLibraryScan(',
    '    private func finishInstalledLibraryScan(',
    '    private var installedLibraryScanFlight: SteamWorkshopInstalledLibraryScanFlight {',
)


def extract(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('unterminated Swift member: ' + signature)


class SteamLibraryReloadCoalescingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-reload-coalescing-build-')
        folder = pathlib.Path(cls.build.name)
        source = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        members = []
        for signature in (
            '    @discardableResult\n    func reloadInstalledItems() -> Task<Void, Never> {',
            '    func managedDownloadSnapshots() ->',
            '    func loadManagedDownloadSnapshots(',
            '    private func applyInstalledLibraryRecords(',
        ):
            members.append(extract(source, signature))
        members.append(extract((CORE / 'SteamWorkshopService+BrowseStateRecovery.swift').read_text(),
                               '    func clearAllCachedState('))
        for signature in COALESCING_MEMBERS:
            member = extract(source, signature)
            if 'finishInstalledLibraryScan(' in signature:
                member = member.replace('private func', 'func', 1)
            members.append(member)
        snapshot_members = (
            '    private var installedLibrarySnapshotURL:', '    func restoreInstalledLibrarySnapshot()',
            '    func invalidateInstalledLibrarySnapshot()', '    private func saveInstalledLibrarySnapshot(',
        )
        for signature in snapshot_members:
            member = extract(source, signature)
            if 'installedLibrarySnapshotURL:' in signature:
                member = member.replace('private var', 'var', 1)
            if 'saveInstalledLibrarySnapshot(' in signature:
                marker = '                try JSONEncoder().encode(snapshot).write(to: staged, options: .atomic)'
                assert member.count(marker) == 1
                member = member.replace(marker, marker + '\n' + r'''
                let held = ScanGate.gate { () -> Bool in
                    let held = ScanGate.holdSnapshotWrite; ScanGate.holdSnapshotWrite = false
                    if held { ScanGate.snapshotWritesHeld += 1 }
                    return held
                }
                if held { precondition(ScanGate.snapshotWriteRelease.wait(timeout: .now() + 5) == .success) }
''')
            members.append(member)
        flight_type = extract(source, '@MainActor private final class SteamWorkshopInstalledLibraryScanFlight {')
        snapshot_type = extract(source, 'nonisolated private struct SteamWorkshopInstalledLibrarySnapshot:')
        metadata_type = extract((CORE / 'SteamWorkshopAPIModels.swift').read_text(),
                                'nonisolated struct SteamWorkshopDownloadMetadataSnapshot:')
        model_sources = [CORE / 'SteamWorkshopModels.swift',
                         ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebValidationModels.swift']
        observed = [pathlib.Path(__file__), CORE / 'SteamWorkshopService+DownloadLibrarySync.swift',
                    CORE / 'SteamWorkshopService+BrowseStateRecovery.swift', CORE / 'SteamWorkshopAPIModels.swift',
                    *model_sources, *SOURCES]
        cls.input_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        harness = r'''
import Foundation
import Darwin

''' + flight_type + '\n' + snapshot_type + '\n' + metadata_type + r'''
nonisolated func fixtureItem(_ id: String, _ title: String) -> SteamWorkshopBrowserItem {
    SteamWorkshopBrowserItem(id: id, title: title, author: "fixture", authorProfileURL: nil, authorWorkshopURL: nil,
        hasAdultContent: false, summary: "summary", descriptionText: "description", tags: ["fixture"], workshopTypeText: "Web",
        ageRatingText: nil, genreText: nil, categoryText: nil, dependencyIDs: [], previewImageURL: nil, previewVideoURL: nil,
        previewAssetKind: .stillImage, fileSizeText: nil, resolutionText: nil, postedText: nil, updatedText: nil,
        favoritesText: nil, subscriptionsText: nil, scoreText: nil, lifetimeFavoritesText: nil, lifetimeSubscriptionsText: nil,
        visibilityText: nil, moderationText: nil, detailFields: [], detailURL: URL(string: "https://fixture.invalid/" + id)!)
}
nonisolated func fixtureRecord(_ item: SteamWorkshopBrowserItem, root: URL,
                              status: SteamWorkshopDownloadRecord.Status = .ready, account: String? = nil) -> SteamWorkshopDownloadRecord {
    var record = SteamWorkshopDownloadRecord(id: item.id, title: item.title, description: item.descriptionText, tags: item.tags,
        folderURL: root, projectFileURL: nil, ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
        entryHTMLURL: root.appendingPathComponent("index.html"), resolvedWebRootURL: root, previewURL: nil,
        sourceVideoURL: nil, exportedVideoURL: nil, updatedAt: Date(timeIntervalSince1970: 123), sizeText: "1 KB",
        status: status, browserItem: item, contentType: .web, dependencyItemID: nil, dependencyStatus: .none,
        createdAt: Date(timeIntervalSince1970: 100), sizeBytes: 1024)
    record.intentAccountSteamID = account
    return record
}
struct SteamWorkshopInstalledLibraryScanContext: Sendable { let libraryRoot: URL }

/// Instrumented scan body: counts entries, tracks peak concurrency, holds while
/// the gate is closed and reports the managed snapshot it was launched with.
enum ScanGate {
    static let lock = NSLock()
    static var hold = true
    static var holdCatchup = true
    static var started = 0
    static var inFlight = 0
    static var peakInFlight = 0
    static var seenManagedCounts: [Int] = []
    static var failNextScan = false
    static var holdSnapshotWrite = false
    static var snapshotWritesHeld = 0
    static let snapshotWriteRelease = DispatchSemaphore(value: 0)
    static func gate<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

@MainActor final class CacheClearAuth {
    let accountID = "kept-account"
    private(set) var cancellations = 0
    func cancelPendingAuthentication() { cancellations += 1 }
}
@MainActor final class CacheClearBrowseStore {
    private(set) var clears = 0
    func clear() { clears += 1 }
}
@MainActor enum CacheClearTrace { static var events: [String] = [] }
@MainActor final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()
    private(set) var invalidations = 0
    func invalidateCachedResults() {
        invalidations += 1
        CacheClearTrace.events.append("generated.invalidate")
    }
}
@MainActor final class SteamWorkshopPreviewImageCache {
    static let shared = SteamWorkshopPreviewImageCache()
    private(set) var clears = 0
    var completion: (@Sendable () -> Void)?
    func clearAll(completion: (@Sendable () -> Void)? = nil) {
        clears += 1; CacheClearTrace.events.append("preview.clear"); self.completion = completion
    }
    func finish() { let pending = completion; completion = nil; pending?() }
}
final class CacheClearCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false, onMain = false
    func finish() { lock.lock(); completed = true; onMain = Thread.isMainThread; lock.unlock() }
    var finishedOnMain: Bool { lock.lock(); defer { lock.unlock() }; return completed && onMain }
}
@MainActor final class CacheClearProgress {
    private(set) var clears = 0
    func removeAll() { clears += 1 }
}
enum CacheClearOption {
    case idle, discovery, video, all, featured, subscriptionDate, week, none
    var title: String { "Steam Workshop" }
}
@MainActor final class SteamWorkshopService {
    var statusMessage = ""
    let steamDownloadLibraryRootURL: URL
    var installedLibraryScanGeneration = 0
    var removingDownloadIDs: Set<String> = []
    var downloads: [SteamWorkshopDownloadRecord] = []
    var hasCompletedInstalledLibraryLoad = false
    let steamAuth = CacheClearAuth()
    let steamKitBrowseStore = CacheClearBrowseStore()
    let downloadProgressStore = CacheClearProgress()
    let downloadJobStore: SteamDownloadJobStore
    var browserFetchTask: Task<Void, Never>?
    var browserItems = ["old"], displayedBrowserItems = ["old"]
    var retainedBrowseSections = ["old": "snapshot"]
    var pendingBrowserScrollRestoreOffset: Double? = 400
    var browserState = CacheClearOption.idle
    var isRefreshingBrowserFeed = true, isLoadingMoreBrowserItems = true, hasMoreBrowserItems = false
    var previewReloadToken = 0
    var browserLoadMoreFailureMessage: String? = "old", selectedBrowserItem: String? = "old"
    var browserLoadMoreRetryAfter = Date.distantFuture
    var selectedBrowserItemError: String? = "old", currentWorkshopItemID: String? = "old"
    var isRefreshingSelectedBrowserItem = true
    var currentPageTitle = "old", activeDownloadItemIDs: Set<String> = ["active"]
    var selectedDownloadInspectorItem: String? = "old", selectedDownloadDetailItem: String? = "old"
    var selectedDownloadDetailError: String? = "old", downloadError: String? = "old"
    var isRefreshingSelectedDownloadDetailItem = true
    var browseContext = CacheClearOption.discovery, browserContentMode = CacheClearOption.video
    var source = CacheClearOption.featured, personalSort = CacheClearOption.subscriptionDate
    var trendingWindow = CacheClearOption.week, facetFilters = CacheClearOption.none
    var discoveryBrowseSnapshot: String? = "old", savedDiscoveryQueryBeforeAuthorBrowse: String? = "old"
    var isUpdatingBrowserQueryProgrammatically = false, suppressAutomaticBrowseNavigation = false
    var browserQuery = "old", navigationVersion = 0
    var detailCancellations = 0
    var cacheDirectoryURL: URL { steamDownloadLibraryRootURL.appendingPathComponent("cache") }
    func cancelSelectedItemDetailRefresh() { detailCancellations += 1 }
    init(libraryRoot: URL) {
        steamDownloadLibraryRootURL = libraryRoot
        downloadJobStore = SteamDownloadJobStore(persistenceURL: libraryRoot.deletingLastPathComponent().appendingPathComponent("jobs.json"))
        restoreInstalledLibrarySnapshot()
    }
    func referencedLibraryStorageIdentities() -> Set<String> { [] }
    func scheduleLegacyLibraryPublicationMigration(from snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {}
    func reconcileDownloadCommits(_ snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {}
    func scheduleTerminalDownloadCleanup() {}
    func installedLibraryScanContext() -> SteamWorkshopInstalledLibraryScanContext {
        SteamWorkshopInstalledLibraryScanContext(libraryRoot: steamDownloadLibraryRootURL)
    }
    func scheduleLibraryVersionReclamation() {}
    nonisolated static func scanInstalledLibraryRecords(
        managed: [String: SteamWorkshopDownloadMetadataSnapshot],
        context: SteamWorkshopInstalledLibraryScanContext,
        allowMissingRoot: Bool = false
    ) throws -> [SteamWorkshopDownloadRecord] {
        let scanNumber = ScanGate.gate {
            ScanGate.started &+= 1
            ScanGate.inFlight &+= 1
            ScanGate.peakInFlight = max(ScanGate.peakInFlight, ScanGate.inFlight)
            ScanGate.seenManagedCounts.append(managed.count)
            return ScanGate.started
        }
        while ScanGate.gate({ ScanGate.hold || (scanNumber == 2 && ScanGate.holdCatchup) }) {
            Thread.sleep(forTimeInterval: 0.002)
        }
        defer { ScanGate.gate { ScanGate.inFlight -= 1 } }
        let fail = ScanGate.gate { () -> Bool in
            let fail = ScanGate.failNextScan; ScanGate.failNextScan = false; return fail
        }
        if fail { throw CocoaError(.fileReadNoPermission) }
        return managed.values
            .sorted { $0.item.id < $1.item.id }
            .map { fixtureRecord($0.item, root: context.libraryRoot) }
    }
''' + '\n'.join(members) + r'''
}
@main struct Harness {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let library = base.appendingPathComponent("library", isDirectory: true)
        let service = SteamWorkshopService(libraryRoot: library)
        func waitUntil(_ label: String, deadlineSeconds: Double = 5, _ condition: @MainActor () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(deadlineSeconds)
            while Date() < deadline {
                if condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            fatalError("timed out waiting for: " + label
                + " [started=\(ScanGate.gate { ScanGate.started }) inFlight=\(ScanGate.gate { ScanGate.inFlight })"
                + " hold=\(ScanGate.gate { ScanGate.hold }) seen=\(ScanGate.gate { ScanGate.seenManagedCounts })"
                + " generation=\(service.installedLibraryScanGeneration) downloads=\(service.downloads.count)]")
        }
        func publish(_ id: String, _ title: String) throws {
            let generation = UUID().uuidString
            var commit = SteamWorkshopLibraryCommit(
                version: 3, workshopId: id, jobId: "job-" + id, attempt: 1,
                directoryName: id, manifestId: "m-" + id,
                contentDigest: String(repeating: "a", count: 64),
                contentType: "web", entryPath: "index.html",
                committedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            commit.generation = generation
            // Canonical v3 layout (see canonicalCommit): the public content
            // directory is the workshop ID itself; `generation` only names the
            // retired public generation it replaced.
            let content = library.appendingPathComponent("Web", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: content.appendingPathComponent("project.json"))
            try Data("<html>".utf8).write(to: content.appendingPathComponent("index.html"))
            var snapshot = SteamWorkshopDownloadMetadataSnapshot(
                fetchedAt: Date(), item: fixtureItem(id, title),
                sourceVideoRelativePath: nil, previewRelativePath: nil,
                exportedVideoURL: nil, legacyFolderURL: content
            )
            snapshot.commit = commit
            try SteamWorkshopLibraryTransaction.publish(
                metadata: JSONEncoder().encode(snapshot), itemID: id, libraryRoot: library
            )
        }
        func removeItem(_ id: String) throws {
            let index = library.appendingPathComponent(
                SteamWorkshopLibraryTransaction.metadataName, isDirectory: true
            )
            try? FileManager.default.removeItem(at: index.appendingPathComponent("\(id).json"))
            let webRoot = library.appendingPathComponent("Web", isDirectory: true)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: webRoot.path)) ?? []
            where name == id || name.hasPrefix(id + "-") {
                try? FileManager.default.removeItem(at: webRoot.appendingPathComponent(name))
            }
        }

        // --- Scenario 1: continuous refresh while a scan is in flight. ---
        try publish("100001", "alpha-v1")
        let retainedJob = service.downloadJobStore.enqueue(workshopItemId: "654321", title: "Retained queued job", accountSteamId: "kept-account").job
        let jobBytesBefore = try Data(contentsOf: base.appendingPathComponent("jobs.json"))
        let browseTask = Task { while !Task.isCancelled { await Task.yield() } }
        service.browserFetchTask = browseTask
        let oldDetailDirectory = service.cacheDirectoryURL.appendingPathComponent("ItemDetails", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDetailDirectory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldDetailDirectory.appendingPathComponent("old.json"))
        let clearCompletion = CacheClearCompletion()
        service.clearAllCachedState { clearCompletion.finish() }
        precondition(browseTask.isCancelled && service.browserFetchTask == nil && service.detailCancellations == 1)
        precondition(service.browserItems.isEmpty && service.displayedBrowserItems.isEmpty && service.retainedBrowseSections.isEmpty)
        let retired = try FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("cache.clear-") }
        precondition(retired.count == 1 && FileManager.default.fileExists(atPath: retired[0].appendingPathComponent("ItemDetails/old.json").path)
            && !FileManager.default.fileExists(atPath: oldDetailDirectory.path),
            "the root and its ItemDetails child are detached once without recursively deleting on the main actor")
        precondition(SteamWorkshopPreviewImageCache.shared.clears == 1)
        precondition(SteamWorkshopDownloadThumbnailPipeline.shared.invalidations == 1
            && CacheClearTrace.events == ["generated.invalidate", "preview.clear"],
            "the original service invalidates generated results before deleting its disk root, once")
        let postClearFile = service.cacheDirectoryURL.appendingPathComponent("new-generation")
        try Data("new".utf8).write(to: postClearFile)
        precondition(!clearCompletion.finishedOnMain)
        SteamWorkshopPreviewImageCache.shared.finish()
        try await waitUntil("old cache recursive deletion completed") { clearCompletion.finishedOnMain }
        let postClearBytes = try Data(contentsOf: postClearFile)
        precondition(!FileManager.default.fileExists(atPath: retired[0].path)
            && postClearBytes == Data("new".utf8),
            "completion waits for detached deletion while new cache writes remain intact")
        precondition(service.steamAuth.accountID == "kept-account" && service.steamAuth.cancellations == 1)
        precondition(service.downloadJobStore.jobs == [retainedJob])
        let jobBytesAfter = try Data(contentsOf: base.appendingPathComponent("jobs.json"))
        precondition(jobBytesBefore == jobBytesAfter, "cache clearing must not cancel/rewrite the durable download queue")
        precondition(service.navigationVersion == 1 && !service.isUpdatingBrowserQueryProgrammatically && !service.suppressAutomaticBrowseNavigation)
        try await waitUntil("first scan started") { ScanGate.gate { ScanGate.started == 1 } }
        precondition(service.installedLibraryScanGeneration == 1 && ScanGate.gate { ScanGate.started == 1 },
            "cache clear must directly request one original source reload without waiting for a grid/window/query")
        for index in 2...6 {
            try publish(String(100_000 + index), "item-\(index)")
        }
        var reloadHandle: Task<Void, Never>?
        for _ in 0..<5 { reloadHandle = service.reloadInstalledItems() }
        var reloadCompleted = false
        let reloadWait = Task { await reloadHandle?.value; reloadCompleted = true }
        precondition(service.installedLibraryScanGeneration == 6,
            "every reload must still advance the result generation")
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(ScanGate.gate { ScanGate.started == 1 && ScanGate.peakInFlight == 1 },
            "reloads arriving while a scan is in flight must not start additional whole-library scans"
            + " (started=\(ScanGate.gate { ScanGate.started }), peak=\(ScanGate.gate { ScanGate.peakInFlight }))")
        ScanGate.gate { ScanGate.hold = false }
        try await waitUntil("catch-up held after stale result") { ScanGate.gate { ScanGate.started == 2 } }
        precondition(!reloadCompleted && service.downloads.isEmpty,
            "the shared reload handle must include the coalesced scan, and the stale first scan must not publish")
        ScanGate.gate { ScanGate.holdCatchup = false }
        await reloadWait.value
        precondition(reloadCompleted && service.downloads.count == 6,
            "reload completion must follow the newest requested scan's real publication")
        try await waitUntil("coalesced catch-up applied") {
            service.downloads.count == 6 && ScanGate.gate { ScanGate.started == 2 }
        }
        precondition(ScanGate.gate { ScanGate.seenManagedCounts == [1, 6] },
            "the coalesced catch-up must scan the newest managed state exactly once: "
            + "\(ScanGate.gate { ScanGate.seenManagedCounts })")
        precondition(service.downloads.map(\.title).sorted() ==
            ["alpha-v1", "item-2", "item-3", "item-4", "item-5", "item-6"].sorted(),
            "the stale first scan must never overwrite the newest projection: "
            + "\(service.downloads.map(\.title))")
        precondition(ScanGate.gate { ScanGate.peakInFlight == 1 },
            "scans must never execute concurrently (peak=\(ScanGate.gate { ScanGate.peakInFlight }))")

        // --- Scenario 2: deletion interleaved with an in-flight scan. ---
        ScanGate.gate { ScanGate.hold = true }
        for index in 2...6 { try removeItem(String(100_000 + index)) }
        let deletionReload = service.reloadInstalledItems()
        try await waitUntil("post-deletion scan started") { ScanGate.gate { ScanGate.started == 3 } }
        service.reloadInstalledItems()
        precondition(service.installedLibraryScanGeneration == 8)
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(ScanGate.gate { ScanGate.started == 3 },
            "a reload during an in-flight scan must coalesce, not start a concurrent scan")
        ScanGate.gate { ScanGate.hold = false }
        await deletionReload.value
        try await waitUntil("deletion projected") {
            service.downloads.count == 1 && ScanGate.gate { ScanGate.started == 4 }
        }
        precondition(service.downloads.map(\.title) == ["alpha-v1"],
            "the interleaved deletion must not be lost: \(service.downloads.map(\.title))")
        precondition(ScanGate.gate { ScanGate.seenManagedCounts == [1, 6, 1, 1] },
            "scan sequence must be initial, catch-up(newest), post-deletion, catch-up(newest): "
            + "\(ScanGate.gate { ScanGate.seenManagedCounts })")
        precondition(ScanGate.gate { ScanGate.peakInFlight == 1 })
        print("CACHE CLEAR REFRESH PASS: one explicit scan; auth/jobs preserved")
        print("RELOAD COALESCING PASS: scans=\(ScanGate.gate { ScanGate.started })"
            + " peakConcurrent=\(ScanGate.gate { ScanGate.peakInFlight })")

        let fm = FileManager.default
        let originalSnapshot = try JSONDecoder().decode(SteamWorkshopInstalledLibrarySnapshot.self,
            from: Data(contentsOf: service.installedLibrarySnapshotURL))
        precondition(originalSnapshot.libraryRoot == library && originalSnapshot.records == service.downloads)
        let reopened = SteamWorkshopService(libraryRoot: library)
        precondition(reopened.downloads.map(\.id) == ["100001"] && reopened.downloads.map(\.title) == ["alpha-v1"]
            && reopened.downloads.allSatisfy { $0.isStartupSnapshot == true } && !reopened.hasCompletedInstalledLibraryLoad,
            "a real display snapshot reopens rows without declaring a fresh scan complete")
        let mismatch = SteamWorkshopService(libraryRoot: base.appendingPathComponent("other-library"))
        try fm.createDirectory(at: mismatch.cacheDirectoryURL, withIntermediateDirectories: true)
        try fm.copyItem(at: service.installedLibrarySnapshotURL, to: mismatch.installedLibrarySnapshotURL)
        mismatch.restoreInstalledLibrarySnapshot()
        precondition(mismatch.downloads.isEmpty && !mismatch.hasCompletedInstalledLibraryLoad,
            "a different library root cannot consume this snapshot")
        let corrupt = SteamWorkshopService(libraryRoot: base.appendingPathComponent("corrupt-library"))
        try fm.createDirectory(at: corrupt.cacheDirectoryURL, withIntermediateDirectories: true)
        try Data("not a snapshot".utf8).write(to: corrupt.installedLibrarySnapshotURL)
        corrupt.restoreInstalledLibrarySnapshot()
        precondition(corrupt.downloads.isEmpty && !corrupt.hasCompletedInstalledLibraryLoad)

        ScanGate.gate { ScanGate.failNextScan = true }
        await reopened.reloadInstalledItems().value
        precondition(reopened.downloads.map(\.id) == ["100001"] && !reopened.hasCompletedInstalledLibraryLoad
            && reopened.statusMessage.contains("保留现有内容"), "a failed scan must retain the warm rows and unknown freshness")
        try removeItem("100001")
        await reopened.reloadInstalledItems().value
        let emptySnapshot = try JSONDecoder().decode(SteamWorkshopInstalledLibrarySnapshot.self,
            from: Data(contentsOf: reopened.installedLibrarySnapshotURL))
        precondition(reopened.downloads.isEmpty && reopened.hasCompletedInstalledLibraryLoad && emptySnapshot.records.isEmpty,
            "a successful empty scan is authoritative and persists an empty display baseline")

        let filtered = SteamWorkshopService(libraryRoot: base.appendingPathComponent("filtered-library"))
        let ready = fixtureRecord(fixtureItem("ready", "Ready"), root: filtered.steamDownloadLibraryRootURL)
        let queued = fixtureRecord(fixtureItem("queued", "Queued"), root: filtered.steamDownloadLibraryRootURL, status: .queued)
        let failed = fixtureRecord(fixtureItem("failed", "Failed"), root: filtered.steamDownloadLibraryRootURL, status: .failed("reason"))
        let transient = fixtureRecord(fixtureItem("intent", "Intent"), root: filtered.steamDownloadLibraryRootURL, account: "other-account")
        let typed = [ready, queued, failed, transient]
        let roundTrip = try JSONDecoder().decode([SteamWorkshopDownloadRecord].self, from: JSONEncoder().encode(typed))
        precondition(roundTrip == typed, "record/status/browser/dependency persistence uses the actual Codable implementation")
        await filtered.finishInstalledLibraryScan(generation: filtered.installedLibraryScanGeneration,
            result: .success(typed), libraryRoot: filtered.steamDownloadLibraryRootURL)
        let filteredSnapshot = try JSONDecoder().decode(SteamWorkshopInstalledLibrarySnapshot.self,
            from: Data(contentsOf: filtered.installedLibrarySnapshotURL))
        precondition(filteredSnapshot.records == [ready], "only local ready rows belong to the display snapshot")
        let filteredReopen = SteamWorkshopService(libraryRoot: filtered.steamDownloadLibraryRootURL)
        precondition(filteredReopen.downloads.map(\.id) == [ready.id]
            && filteredReopen.downloads.first?.browserItem == ready.browserItem
            && filteredReopen.downloads.first?.isStartupSnapshot == true && !filteredReopen.hasCompletedInstalledLibraryLoad)

        let racing = SteamWorkshopService(libraryRoot: base.appendingPathComponent("racing-library"))
        let obsolete = fixtureRecord(fixtureItem("old", "Old"), root: racing.steamDownloadLibraryRootURL)
        let current = fixtureRecord(fixtureItem("new", "New"), root: racing.steamDownloadLibraryRootURL)
        let heldBeforeDeletion = ScanGate.gate { ScanGate.holdSnapshotWrite = true; return ScanGate.snapshotWritesHeld }
        let deletionGeneration = racing.installedLibraryScanGeneration
        let preDeletionWrite = Task { await racing.finishInstalledLibraryScan(generation: deletionGeneration,
            result: .success([obsolete]), libraryRoot: racing.steamDownloadLibraryRootURL) }
        try await waitUntil("actual snapshot staged before deletion") { ScanGate.gate { ScanGate.snapshotWritesHeld > heldBeforeDeletion } }
        racing.installedLibraryScanGeneration += 1
        racing.removingDownloadIDs.insert(obsolete.id)
        racing.downloads = []
        racing.invalidateInstalledLibrarySnapshot()
        ScanGate.snapshotWriteRelease.signal()
        await preDeletionWrite.value
        let deletionResidue = try fm.contentsOfDirectory(atPath: racing.cacheDirectoryURL.path)
        precondition(racing.downloads.isEmpty && !fm.fileExists(atPath: racing.installedLibrarySnapshotURL.path)
            && !deletionResidue.contains { $0.hasPrefix(".installed-records-") }, "a pre-deletion write cannot recreate the snapshot")

        racing.removingDownloadIDs.removeAll()
        racing.installedLibraryScanGeneration += 1
        let oldGeneration = racing.installedLibraryScanGeneration
        let heldBeforePublication = ScanGate.gate { ScanGate.holdSnapshotWrite = true; return ScanGate.snapshotWritesHeld }
        let oldWrite = Task { await racing.finishInstalledLibraryScan(generation: oldGeneration,
            result: .success([obsolete]), libraryRoot: racing.steamDownloadLibraryRootURL) }
        try await waitUntil("actual old snapshot staged before new publication") { ScanGate.gate { ScanGate.snapshotWritesHeld > heldBeforePublication } }
        racing.installedLibraryScanGeneration += 1
        await racing.finishInstalledLibraryScan(generation: racing.installedLibraryScanGeneration,
            result: .success([current]), libraryRoot: racing.steamDownloadLibraryRootURL)
        ScanGate.snapshotWriteRelease.signal()
        await oldWrite.value
        let latestSnapshot = try JSONDecoder().decode(SteamWorkshopInstalledLibrarySnapshot.self,
            from: Data(contentsOf: racing.installedLibrarySnapshotURL))
        let publicationResidue = try fm.contentsOfDirectory(atPath: racing.cacheDirectoryURL.path)
        precondition(racing.downloads == [current] && latestSnapshot.records == [current]
            && !publicationResidue.contains { $0.hasPrefix(".installed-records-") }, "a late older write cannot replace the newest publication")

        let unwritable = SteamWorkshopService(libraryRoot: base.appendingPathComponent("unwritable-cache-library"))
        try fm.createDirectory(at: unwritable.steamDownloadLibraryRootURL, withIntermediateDirectories: true)
        let blocker = Data("a file blocks the optional cache directory".utf8)
        try blocker.write(to: unwritable.cacheDirectoryURL)
        let accepted = fixtureRecord(fixtureItem("accepted", "Accepted"), root: unwritable.steamDownloadLibraryRootURL)
        await unwritable.finishInstalledLibraryScan(generation: unwritable.installedLibraryScanGeneration,
            result: .success([accepted]), libraryRoot: unwritable.steamDownloadLibraryRootURL)
        let unchangedBlocker = try Data(contentsOf: unwritable.cacheDirectoryURL)
        precondition(unwritable.downloads == [accepted] && unwritable.hasCompletedInstalledLibraryLoad && unchangedBlocker == blocker,
            "an optional snapshot write failure cannot roll back successful source publication")
        print("INSTALLED SNAPSHOT PASS: warm/root/corrupt/empty/failure/Codable/stale-deletion/stale-publication/write-failure")
    }
}
'''
        harness_path = folder / 'Harness.swift'
        harness_path.write_text(harness)
        cls.binary = folder / 'coalescing'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, [*SOURCES, *model_sources]), str(harness_path),
                        '-o', str(cls.binary)], check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_overlapping_reloads_coalesce_into_one_catch_up_scan(self):
        with tempfile.TemporaryDirectory(prefix='mwx-reload-coalescing-', dir='/private/tmp') as directory:
            result = subprocess.run([str(self.binary), directory], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('RELOAD COALESCING PASS: scans=', result.stdout)
            self.assertIn('CACHE CLEAR REFRESH PASS: one explicit scan; auth/jobs preserved', result.stdout)
            self.assertIn('INSTALLED SNAPSHOT PASS:', result.stdout)
            self.assertEqual(self.input_hashes, {path: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
                                               for path in self.input_hashes})


if __name__ == '__main__':
    unittest.main()
