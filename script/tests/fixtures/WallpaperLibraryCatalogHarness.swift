import AppKit
import Combine
import Foundation
import ImageIO

// STATIC_IMAGE_MODEL
// CONTENT_RATING_SUPPORT
// CATALOG_VALUE
// JOB_STATE
// JOB_VALUE
// HISTORY_OUTCOME
// HISTORY_VALUE
// WEB_PROJECT_GENERAL
// WEB_PROJECT

@MainActor enum CatalogVisibleFilterProbe {
    static var videoScans: Int { CatalogFileProbe.shared.scans.visits["selection-videoLibrary", default: 0] }
    static var imageScans: Int { CatalogFileProbe.shared.scans.visits["selection-staticImageLibrary", default: 0] }
    static var unionBuilds = 0
    static var publishEntries = 0
    static var installEntries = 0
}

// Observe real file workers and pure visible scans. Barriers hold their
// actual entry without substituting results.
nonisolated final class CatalogFileProbe: @unchecked Sendable {
    static let shared = CatalogFileProbe()
    private let lock = NSLock()
    private var nextBarrier: DispatchSemaphore?
    private var recording = false
    private var active = 0
    private var maximum = 0
    private var total = 0
    private var stayedOffMain = true
    private var scanVisits: [String: Int] = [:]
    private var mainScans = Set<String>()
    private var nextScanBarrier: (String, DispatchSemaphore)?
    func holdScan(_ key: String) -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        let barrier = DispatchSemaphore(value: 0)
        nextScanBarrier = (key, barrier)
        return barrier
    }
    func noteScan(_ key: String) {
        lock.lock()
        scanVisits[key, default: 0] += 1
        if Thread.isMainThread { mainScans.insert(key) }
        let barrier = nextScanBarrier.flatMap { $0.0 == key ? $0.1 : nil }
        if barrier != nil { nextScanBarrier = nil }
        lock.unlock()
        barrier?.wait()
    }
    func resetScans(_ key: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let key { scanVisits[key] = 0; mainScans.remove(key) }
        else { scanVisits.removeAll(); mainScans.removeAll() }
    }
    var scans: (visits: [String: Int], onMain: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        return (scanVisits, mainScans)
    }
    func holdNext() -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        let barrier = DispatchSemaphore(value: 0)
        nextBarrier = barrier; recording = true; maximum = 0; total = 0
        return barrier
    }
    func begin() -> Bool {
        lock.lock()
        guard recording else { lock.unlock(); return false }
        active += 1; total += 1; maximum = max(maximum, active)
        stayedOffMain = stayedOffMain && !Thread.isMainThread
        let barrier = nextBarrier; nextBarrier = nil
        lock.unlock()
        barrier?.wait()
        return true
    }
    func end(_ observed: Bool) {
        guard observed else { return }
        lock.lock(); active -= 1; lock.unlock()
    }
    var snapshot: (active: Int, maximum: Int, total: Int, offMain: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (active, maximum, total, stayedOffMain)
    }
    func stop() { lock.lock(); recording = false; lock.unlock() }
}

nonisolated final class CatalogSteamIOProbe: @unchecked Sendable {
    static let shared = CatalogSteamIOProbe()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func note(_ entry: String) { lock.lock(); counts[entry, default: 0] += 1; lock.unlock() }
    func reset() { lock.lock(); counts.removeAll(); lock.unlock() }
    var snapshot: [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
}

// Pure provider leaves only: no live singleton, network, UI or runtime starts.
nonisolated struct SteamWorkshopStagingLeaseIdentity: Codable, Equatable {}
nonisolated struct SteamWorkshopStagedReceipt: Codable, Equatable {}
nonisolated struct SteamWorkshopLibraryCommit: Codable, Equatable {}
final class WallpaperManager {
    @Published var wallpapers: [VideoWallpaper] = []
    @Published var didFinishInitialIndexLoad = false
    var wallpaperIndexSaveEpoch: UInt64 = 0
    // VIDEO_METADATA_RECEIPT
}
nonisolated let catalogHeaderReady = DispatchSemaphore(value: 0)
nonisolated let catalogHeaderRelease = DispatchSemaphore(value: 0)
final class SILService {
    @Published var wallpapers: [SILWallpaper] = []
    var persistenceURL = URL(fileURLWithPath: "/unused-catalog-index")
    var metadataLoadGeneration: UInt64 = 0
    func save() {}
    // IMAGE_METADATA_RECEIPT
}
final class PixabayService {
    @Published var downloadedContent = PixabayDownloadedContentSnapshot(revision: 0, entries: [], status: .initial)
    @Published var items: [PixabayVideoItem] = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    var refreshRequests = 0
    @discardableResult func refreshDownloadedContent() -> Task<Void, Never> {
        refreshRequests += 1
        return Task {}
    }
}
final class CatalogJobs {
    @Published var jobs: [SteamDownloadJob] = []
    @Published var history: [SteamDownloadHistoryEntry] = []
}
final class CatalogAuth { @Published var steamId: String? = "account-A" }
final class SteamWorkshopService {
    @Published var downloads: [SteamWorkshopDownloadRecord] = []
    @Published var hasCompletedInstalledLibraryLoad = false
    @Published var browserItems: [SteamWorkshopBrowserItem] = []
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { downloads.first { $0.id.utf8.elementsEqual(id.utf8) } }
    var replayRecords: [String: SteamWorkshopDownloadRecord] = [:]
    var replayReads: [String] = []
    func installedRecordForLaunchReplay(itemID: String) -> SteamWorkshopDownloadRecord? {
        replayReads.append(itemID)
        return replayRecords[itemID]
    }
    let downloadJobStore = CatalogJobs()
    let steamAuth = CatalogAuth()
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    // DOWNLOAD_EXCLUSION_FACTS
    // DOWNLOAD_FAILURE_HISTORY
    // DOWNLOAD_ACCOUNT
    // WEB_ENTRY_VALIDATION
    // DECLARED_WEB_ENTRY
    // LOAD_WEB_PROJECT
    // STEAM_LAUNCH_ADMISSION
    nonisolated func loadDecodedWebProject(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopProject? {
        Self.loadWorkshopProject(from: record.projectFileURL)
    }
}

// Scene rendering/preparation is outside this catalog fixture. The product
// consumes its existing launch predicate; these cases exercise video and Web.
extension SteamWorkshopDownloadRecord { var isSceneLaunchable: Bool { false } }

nonisolated private func onlineStatuses(_ status: WallpaperSourceScanStatus) -> [OnlineImageSource: WallpaperSourceScanStatus] {
    Dictionary(uniqueKeysWithValues: OnlineImageSource.allCases.map { ($0, status) })
}

@main struct WallpaperLibraryCatalogHarness {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sharedFile = root.appendingPathComponent("shared.mp4")
        try Data([1, 2, 3]).write(to: sharedFile)
        let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), pixabay = PixabayService()
        manager.wallpapers = [VideoWallpaper(id: "42", title: "same title", path: sharedFile.path)]
        images.wallpapers = [try image(id: "42", path: sharedFile.path)]
        steam.downloads = [record(id: "42", video: sharedFile), record(id: "video:offline", video: root.appendingPathComponent("missing.mp4"))]
        let immediate = steam.libraryContentItemForExplicitPlayback(id: "42")
        let rejectsMissing = steam.libraryContentItemForExplicitPlayback(id: "video:offline") == nil
        let rejectsUnknown = steam.libraryContentItemForExplicitPlayback(id: "not-published") == nil
        steam.replayRecords["replay-only"] = record(id: "replay-only", video: sharedFile)
        let replay = steam.libraryContentItemForExplicitPlayback(id: "replay-only")
        let initialBarrier = CatalogFileProbe.shared.holdNext()
        let controller = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, pixabay: pixabay)
        var checks: [String: Bool] = [:]
        checks["persisted-video-and-image-rows-project-before-file-workers-start"] =
            controller.catalog.videos.map(\.title) == ["same title"] && controller.catalog.images.map(\.title) == images.wallpapers.map(\.title)
            && controller.catalog.videos.count == 1 && controller.catalog.images.count == 1
            && (controller.catalog.videos + controller.catalog.images).allSatisfy { $0.publishedAvailability == .available && $0.capabilities.contains(.play) }
            && CatalogFileProbe.shared.snapshot.total == 0
        checks["index-first-rows-do-not-announce-fresh-provider-completion"] =
            !controller.catalog.loadedProviders.contains(.videoLibrary) && !controller.catalog.loadedProviders.contains(.staticImageLibrary)
        checks["explicit-user-action-can-resolve-a-validated-record-before-catalog-publication"] = immediate?.reference == .init(provider: .steamWorkshop, sourceID: "42")
            && immediate?.capabilities.contains(.play) == true
        checks["explicit-user-action-cannot-invent-a-missing-or-unpublished-resource"] = rejectsMissing && rejectsUnknown
        checks["explicit-launch-reuses-original-exact-published-record-fast-path-without-an-all-library-scan"] = replay?.reference == .init(provider: .steamWorkshop, sourceID: "replay-only")
            && replay?.capabilities.contains(.play) == true && steam.replayReads.last == "replay-only"
        func wait(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(3)) }
            return condition()
        }
        let initialWorkerStarted = await wait { CatalogFileProbe.shared.snapshot.active > 0 }
        checks["held-first-stat-keeps-the-initial-local-rows-visible"] = initialWorkerStarted
            && controller.catalog.videos.count == 1 && controller.catalog.images.count == 1
            && CatalogFileProbe.shared.snapshot.offMain
        initialBarrier.signal()
        await controller.videoTask?.value; await controller.imageTask?.value
        CatalogFileProbe.shared.stop()
        checks["three-real-source-subscriptions-publish-initial-values"] = await wait {
            controller.catalog.videos.count == 1 && controller.catalog.images.count == 1 && controller.catalog.downloads.count == 2
        }
        checks["unloaded-video-steam-and-online-initial-values-are-not-declared-empty-libraries"] =
            controller.catalog.loadedProviders == [.staticImageLibrary]
        let beforeReadiness = controller.catalog.revision
        manager.didFinishInitialIndexLoad = true
        steam.hasCompletedInstalledLibraryLoad = true
        pixabay.downloadedContent = .init(revision: 1, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        OnlineImageLibrary.shared.snapshot = .init(sourceStatuses: [.wallhaven: .init(phase: .ready(warnings: []), hasSuccessfulScan: true)], revision: 1)
        checks["one-image-source-completion-does-not-declare-unread-peer-ready"] = controller.catalog.loadedProviders.contains(.wallhaven)
            && !controller.catalog.loadedProviders.contains(.pixiv) && !OnlineImageLibrary.shared.snapshot.status.hasSuccessfulScan
        OnlineImageLibrary.shared.snapshot = .init(sourceStatuses: onlineStatuses(.init(phase: .ready(warnings: []), hasSuccessfulScan: true)), revision: 2)
        checks["source-completion-including-a-successfully-empty-online-library-publishes-one-consistent-value"] = await wait {
            controller.catalog.loadedProviders == Set(WallpaperProvider.allCases) && controller.catalog.revision > beforeReadiness
        }
        let afterReadiness = controller.catalog.revision
        pixabay.downloadedContent = .init(revision: 2, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        try await Task.sleep(for: .milliseconds(10))
        checks["unchanged-successful-source-refresh-does-not-invent-a-new-catalog-revision"] = controller.catalog.revision == afterReadiness
        let video = controller.catalog.videos[0], still = controller.catalog.images[0], downloaded = controller.catalog.downloads[0]
        checks["same-source-number-remains-distinct-across-three-providers"] = Set([video.reference, still.reference, downloaded.reference]).count == 3
        checks["available-facts-come-from-real-local-resources"] = [video, still, downloaded].allSatisfy {
            $0.publishedAvailability == .available && $0.capabilities.contains([.play, .organize])
        }
        checks["available-local-video-publishes-its-original-quick-look-capability"] = video.capabilities.contains(.quickLook)
        checks["no-alias-is-invented-from-equal-title-or-path"] = video.reference.provider == .videoLibrary
            && downloaded.reference.provider == .steamWorkshop && [video, still, downloaded].allSatisfy { $0.aliases.isEmpty }
        checks["offline-steam-opaque-video-id-retains-inspector-and-delete"] = controller.catalog.downloads[1].reference.sourceID == "video:offline"
            && controller.catalog.downloads[1].publishedAvailability == .unavailable
            && controller.catalog.downloads[1].capabilities.contains([.inspect, .delete])
            && !controller.catalog.downloads[1].capabilities.contains(.play)
        checks["unknown-video-created-date-is-not-fabricated"] = video.metadata.createdAt == nil
        checks["image-created-date-uses-persisted-metadata"] = still.metadata.createdAt == Date(timeIntervalSinceReferenceDate: 123)
        checks["steam-created-date-uses-persisted-publication-metadata"] = downloaded.metadata.createdAt == Date(timeIntervalSince1970: 20)

        steam.downloadJobStore.jobs = [job(state: .failed)]
        checks["old-published-steam-version-stays-playable-when-update-fails"] = await wait {
            let item = controller.catalog.downloads[0]
            return item.publishedAvailability == .available && item.update.phase == .failed
                && item.capabilities.contains([.play, .organize, .retryUpdate]) && item.acquisition == .idle
        }
        steam.steamAuth.steamId = "account-B"
        checks["another-account-failure-never-leaks-into-local-update-state"] = await wait { controller.catalog.downloads[0].update.phase == .idle }
        steam.steamAuth.steamId = "account-A"
        _ = await wait { controller.catalog.downloads[0].update.phase == .failed }
        let beforeBrowserRevision = controller.revisions[.steamWorkshop]
        steam.browserItems = [try browser("remote-only")]
        try? await Task.sleep(for: .milliseconds(20))
        checks["remote-browser-results-do-not-enter-local-catalog-or-trigger-validation"] = controller.catalog.downloads.count == 2
            && controller.revisions[.steamWorkshop] == beforeBrowserRevision
        steam.downloadProgressStore.begin(itemID: "42", jobKey: "progress-only", attempt: 1)
        _ = steam.downloadProgressStore.receiveHelperEvent(itemID: "42", jobKey: "progress-only", attempt: 1,
            sequence: 1, stage: "chunks", totalBytes: 100, verifiedBytes: 20)
        try? await Task.sleep(for: .milliseconds(20))
        checks["card-progress-counters-do-not-trigger-global-catalog-validation"] = controller.revisions[.steamWorkshop] == beforeBrowserRevision

        // Remove the file without a source publication. Metadata updates must
        // reuse prior availability, rather than perform hidden stat per tick.
        try FileManager.default.removeItem(at: sharedFile)
        manager.wallpapers = [VideoWallpaper(id: "42", title: "renamed", path: sharedFile.path)]
        var renamedImage = images.wallpapers[0]; renamedImage.title = "renamed image"; images.wallpapers = [renamedImage]
        steam.downloads = [record(id: "42", video: sharedFile, title: "renamed download"), steam.downloads[1]]
        checks["metadata-only-publisher-updates-reuse-existing-availability"] = await wait {
            controller.catalog.videos[0].title == "renamed" && controller.catalog.images[0].title == "renamed image"
                && controller.catalog.downloads[0].title == "renamed download"
                && [controller.catalog.videos[0], controller.catalog.images[0], controller.catalog.downloads[0]].allSatisfy { $0.publishedAvailability == .available }
        }
        var newerFailure = job(state: .failed)
        newerFailure.attempt = 3
        newerFailure.updatedAt = Date(timeIntervalSince1970: 60)
        steam.downloadJobStore.jobs = [newerFailure]
        checks["terminal-task-change-revalidates-only-its-source-publication"] = await wait {
            controller.catalog.downloads[0].publishedAvailability == .unavailable
                && controller.catalog.downloads[0].update.attempt == 3
                && controller.catalog.videos[0].publishedAvailability == .available
                && controller.catalog.images[0].publishedAvailability == .available
        }
        controller.refreshAvailability()
        checks["explicit-source-refresh-revokes-missing-resource-without-dropping-items"] = await wait {
            [controller.catalog.videos[0], controller.catalog.images[0], controller.catalog.downloads[0]].allSatisfy {
                $0.publishedAvailability == .unavailable && !$0.capabilities.contains(.play) && !$0.capabilities.contains(.organize)
            }
        }
        try Data([4]).write(to: sharedFile)
        controller.refreshAvailability()
        checks["source-refresh-restores-same-references-after-resource-recovery"] = await wait {
            [controller.catalog.videos[0], controller.catalog.images[0], controller.catalog.downloads[0]].allSatisfy { $0.publishedAvailability == .available }
        }
        // Visible local resources keep their prior grid behavior after those
        // grids retire. No page/query operation performs this filesystem work.
        let offscreen = root.appendingPathComponent("offscreen.mp4")
        try Data([2]).write(to: offscreen)
        manager.wallpapers.append(VideoWallpaper(id: "offscreen", title: "offscreen", path: offscreen.path))
        _ = await wait { controller.catalog.videos.count == 2 }
        await controller.videoTask?.value
        let videoToken = UUID(), imageToken = UUID()
        CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
        var visiblePreviewRepairs = 0
        let previewRepairs = controller.visibleLocalFactsRefreshed.sink { visiblePreviewRepairs += 1 }
        defer { previewRepairs.cancel() }
        controller.setVisibleReferences([video.providerReference], sourceToken: videoToken)
        controller.setVisibleReferences([still.providerReference], sourceToken: imageToken)
        try FileManager.default.removeItem(at: sharedFile)
        try FileManager.default.removeItem(at: offscreen)
        checks["visible-video-and-image-detect-external-delete-without-source-publication"] = await wait {
            controller.catalog.videos[0].publishedAvailability == .unavailable && controller.catalog.images[0].publishedAvailability == .unavailable
        }
        checks["mixed-visible-scope-traverses-both-providers-and-repairs-video-previews"] =
            CatalogVisibleFilterProbe.videoScans > 0 && CatalogVisibleFilterProbe.imageScans > 0 && visiblePreviewRepairs > 0
        checks["visible-check-does-not-probe-offscreen-resources-or-remove-source-models"] = controller.catalog.videos[1].publishedAvailability == .available
            && manager.wallpapers.count == 2 && images.wallpapers.count == 1
        try Data([3]).write(to: sharedFile)
        checks["visible-same-path-restore-recovers-play-and-organization"] = await wait {
            controller.catalog.videos[0].capabilities.contains([.play, .organize]) && controller.catalog.images[0].capabilities.contains([.play, .organize])
        }
        controller.setVisibleReferences([], sourceToken: videoToken)
        controller.setVisibleReferences([], sourceToken: imageToken)
        try FileManager.default.removeItem(at: sharedFile)
        try await Task.sleep(for: .milliseconds(2100))
        checks["hidden-or-closed-consumers-release-file-probe-demand"] = controller.visibleAvailabilityTask == nil
            && controller.catalog.videos[0].publishedAvailability == .available && controller.catalog.images[0].publishedAvailability == .available
        CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary"); visiblePreviewRepairs = 0
        await controller.refreshVisibleAvailability()
        checks["empty-visible-scope-skips-both-provider-arrays-and-preview-repair"] =
            CatalogVisibleFilterProbe.videoScans == 0 && CatalogVisibleFilterProbe.imageScans == 0 && visiblePreviewRepairs == 0
        controller.setVisibleReferences([still.providerReference], sourceToken: imageToken)
        checks["one-consumer-scope-never-refreshes-another-provider"] = await wait { controller.catalog.images[0].publishedAvailability == .unavailable }
            && controller.catalog.videos[0].publishedAvailability == .available
        checks["image-only-visible-scope-skips-video-array-and-preview-repair"] =
            CatalogVisibleFilterProbe.videoScans == 0 && CatalogVisibleFilterProbe.imageScans > 0 && visiblePreviewRepairs == 0
        CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
        controller.setVisibleReferences([video.providerReference], sourceToken: videoToken)
        controller.setVisibleReferences([], sourceToken: imageToken)
        checks["releasing-one-viewport-does-not-cancel-another-consumer"] = await wait { controller.catalog.videos[0].publishedAvailability == .unavailable }
            && controller.visibleAvailabilityTask != nil
        checks["video-only-visible-scope-skips-image-array-and-keeps-preview-repair"] =
            CatalogVisibleFilterProbe.videoScans > 0 && CatalogVisibleFilterProbe.imageScans == 0 && visiblePreviewRepairs > 0
        controller.setVisibleReferences([], sourceToken: videoToken)
        try Data([4]).write(to: sharedFile)
        controller.refreshAvailability()
        _ = await wait { controller.catalog.videos[0].publishedAvailability == .available }
        do {
            await controller.videoTask?.value; await controller.imageTask?.value; await controller.steamTask?.value
            await controller.visibleAvailabilityTask?.value
            controller.visibleReferences = [UUID(): [video.providerReference, still.providerReference]]
            let stable = controller.catalog
            visiblePreviewRepairs = 0; CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
            let beforePublish = CatalogVisibleFilterProbe.publishEntries, beforeInstall = CatalogVisibleFilterProbe.installEntries
            await controller.refreshVisibleAvailability()
            checks["unchanged-mixed-visible-refresh-still-delivers-video-repair-and-checks-images"] = visiblePreviewRepairs == 1
                && CatalogVisibleFilterProbe.videoScans > 0 && CatalogVisibleFilterProbe.imageScans > 0
            checks["unchanged-mixed-visible-refresh-preserves-catalog-content-and-revision"] = controller.catalog.videos == stable.videos
                && controller.catalog.images == stable.images && controller.catalog.revision == stable.revision
            checks["unchanged-mixed-visible-refresh-skips-publish-and-install"] = CatalogVisibleFilterProbe.publishEntries == beforePublish
                && CatalogVisibleFilterProbe.installEntries == beforeInstall
            let scans = CatalogFileProbe.shared.scans
            checks["visible-source-selection-runs-off-main"] = scans.visits["selection-videoLibrary", default: 0] > 0
                && scans.visits["selection-staticImageLibrary", default: 0] > 0
                && scans.onMain.isDisjoint(with: ["selection-videoLibrary", "selection-staticImageLibrary"])
            checks["visible-item-merge-runs-off-main"] = scans.visits["merge", default: 0] > 0 && !scans.onMain.contains("merge")
            let sourceRevision = controller.revisions[.videoLibrary]!
            let staleBarrier = CatalogFileProbe.shared.holdNext()
            defer { staleBarrier.signal(); CatalogFileProbe.shared.stop() }
            visiblePreviewRepairs = 0; CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
            let staleRefresh = Task { await controller.refreshVisibleAvailability() }
            let held = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
            controller.revisions[.videoLibrary] = sourceRevision &+ 1
            staleBarrier.signal()
            await staleRefresh.value
            checks["retired-video-visible-receipt-cannot-repair-or-replace-current-catalog"] = held && visiblePreviewRepairs == 0
                && controller.catalog.videos == stable.videos && controller.catalog.images == stable.images
                && controller.catalog.revision == stable.revision
            checks["retired-video-receipt-does-not-skip-independent-image-check"] = CatalogVisibleFilterProbe.imageScans > 0
            controller.revisions[.videoLibrary] = sourceRevision
            controller.visibleReferences = [:]
        }
        // Rapid viewport changes and hide/reopen during a slow source stat
        // must wait for its real completion, not merely cancel its parent Task.
        let held = CatalogFileProbe.shared.holdNext()
        let boundedToken = UUID()
        CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
        controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
        let firstVideoScans = CatalogVisibleFilterProbe.videoScans
        let stableGeneration = controller.visibleAvailabilityGeneration
        let remote = WallpaperReference(provider: .steamWorkshop, sourceID: "remote-viewport")
        CatalogVisibleFilterProbe.unionBuilds = 0
        for _ in 0..<8 {
            controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
            controller.setVisibleReferences([video.providerReference, remote], sourceToken: boundedToken)
        }
        checks["same-token-local-demand-and-remote-only-changes-skip-both-unions"] = CatalogVisibleFilterProbe.unionBuilds == 0
            && controller.visibleAvailabilityGeneration == stableGeneration && controller.visibleAvailabilityTask?.isCancelled == false
        let emptyToken = UUID()
        CatalogVisibleFilterProbe.unionBuilds = 0
        for _ in 0..<3 {
            controller.setVisibleReferences([], sourceToken: emptyToken)
            controller.setVisibleReferences([remote], sourceToken: emptyToken)
        }
        checks["repeated-empty-or-remote-only-token-skips-both-unions"] = CatalogVisibleFilterProbe.unionBuilds == 0
            && controller.visibleReferences[emptyToken] == nil && controller.visibleAvailabilityGeneration == stableGeneration
        let peerToken = UUID()
        controller.setVisibleReferences([video.providerReference], sourceToken: peerToken)
        checks["another-consumer-retains-the-same-reference-without-changing-generation"] =
            controller.visibleReferences[peerToken] == [video.providerReference] && controller.visibleAvailabilityGeneration == stableGeneration
        controller.setVisibleReferences([], sourceToken: boundedToken)
        checks["releasing-one-same-reference-consumer-keeps-the-other-worker-lease"] =
            controller.visibleReferences[boundedToken] == nil && controller.visibleReferences[peerToken] == [video.providerReference]
            && controller.visibleAvailabilityGeneration == stableGeneration && controller.visibleAvailabilityTask?.isCancelled == false
        controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
        controller.setVisibleReferences([], sourceToken: peerToken)
        controller.setVisibleReferences([], sourceToken: boundedToken)
        let releasedGeneration = controller.visibleAvailabilityGeneration
        checks["last-consumer-release-retires-the-original-worker-generation"] = controller.visibleReferences.isEmpty
            && releasedGeneration != stableGeneration && controller.visibleAvailabilityTask?.isCancelled == true
        controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
        checks["same-reference-reopen-waits-for-the-retained-cancelled-worker"] =
            controller.visibleReferences[boundedToken] == [video.providerReference] && controller.visibleAvailabilityGeneration != releasedGeneration
            && controller.visibleAvailabilityTask?.isCancelled == true && CatalogFileProbe.shared.snapshot.total == 1
        var mainQueueResponded = false
        DispatchQueue.main.async { mainQueueResponded = true }
        _ = await wait { mainQueueResponded }
        for index in 0..<30 {
            controller.setVisibleReferences(index.isMultiple(of: 2) ? [] : [still.providerReference], sourceToken: boundedToken)
        }
        controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
        try await Task.sleep(for: .milliseconds(35))
        let duringHold = CatalogFileProbe.shared.snapshot
        checks["slow-visible-source-stat-does-not-block-main-or-fan-out-on-hide-reopen"] = mainQueueResponded
            && duringHold.active == 1 && duringHold.maximum == 1 && duringHold.total == 1 && duringHold.offMain
        held.signal()
        checks["slow-source-finishes-before-exactly-one-current-scope-catchup"] = await wait {
            CatalogFileProbe.shared.snapshot.active == 0 && CatalogFileProbe.shared.snapshot.total == 2
        }
        checks["same-reference-reopen-rechecks-only-the-current-provider-array"] =
            CatalogVisibleFilterProbe.videoScans > firstVideoScans && CatalogVisibleFilterProbe.imageScans == 0
        checks["coalesced-catchup-keeps-single-flight-through-uninterruptible-worker"] = CatalogFileProbe.shared.snapshot.maximum == 1
        controller.setVisibleReferences([], sourceToken: boundedToken)
        _ = await wait { controller.visibleAvailabilityTask == nil }
        let beforeHidden = CatalogFileProbe.shared.snapshot.total
        CatalogFileProbe.shared.resetScans("selection-videoLibrary"); CatalogFileProbe.shared.resetScans("selection-staticImageLibrary")
        try await Task.sleep(for: .milliseconds(50))
        checks["empty-scope-never-restarts-a-retired-slow-file-worker"] = CatalogFileProbe.shared.snapshot.total == beforeHidden
            && controller.visibleAvailabilityTask == nil
        checks["closed-visible-scope-never-traverses-either-provider-array"] =
            CatalogVisibleFilterProbe.videoScans == 0 && CatalogVisibleFilterProbe.imageScans == 0
        CatalogFileProbe.shared.stop()

        let projectionBarrier = CatalogFileProbe.shared.holdNext()
        controller.refreshAvailability()
        _ = await wait { CatalogFileProbe.shared.snapshot.active > 0 }
        let originalProjection = controller.videoTask!
        manager.wallpapers[0] = VideoWallpaper(id: "42", title: "refresh newest source", path: sharedFile.path)
        let replacementProjection = controller.videoTask!
        checks["explicit-resource-refresh-can-be-replaced-by-the-current-source-publication"] =
            originalProjection.isCancelled && !replacementProjection.isCancelled && CatalogFileProbe.shared.snapshot.active > 0
        projectionBarrier.signal()
        await originalProjection.value; await replacementProjection.value
        checks["latest-source-projection-publishes-current-availability-after-a-refresh-replacement"] =
            controller.catalog.videos.first?.title == "refresh newest source"
            && controller.catalog.videos.first?.publishedAvailability == .available
        CatalogFileProbe.shared.stop()

        let retiredFile = root.appendingPathComponent("retired-refresh.mp4"), successorFile = root.appendingPathComponent("successor-refresh.mp4")
        try Data([1]).write(to: retiredFile); try Data([2]).write(to: successorFile)
        let retiredBarrier = CatalogFileProbe.shared.holdNext()
        manager.wallpapers[0] = VideoWallpaper(id: "42", title: "retired refresh source", path: retiredFile.path)
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
        let retainedProjection = controller.videoTask!
        let successorBarrier = CatalogFileProbe.shared.holdNext()
        manager.wallpapers[0] = VideoWallpaper(id: "42", title: "successor refresh source", path: successorFile.path)
        let successorProjection = controller.videoTask!
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 2 }
        checks["replacing-a-held-source-cancels-only-the-original-projection"] = retainedProjection.isCancelled && !successorProjection.isCancelled
        retiredBarrier.signal(); await retainedProjection.value
        checks["retired-source-completion-cannot-publish-over-a-held-successor"] = !successorProjection.isCancelled
            && controller.catalog.videos.first?.title != "retired refresh source" && controller.catalog.videos.first?.title == "successor refresh source"
        successorBarrier.signal(); await successorProjection.value
        checks["successor-source-keeps-its-real-publication-after-the-retired-worker-exits"] = !successorProjection.isCancelled
            && controller.catalog.videos.first?.title == "successor refresh source"
            && controller.catalog.videos.first?.publishedAvailability == .available
        CatalogFileProbe.shared.stop()

        let savedVideos = manager.wallpapers, savedImages = images.wallpapers
        let metadataDirectory = root.appendingPathComponent("metadata-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        let metadataPNG = root.appendingPathComponent("metadata.png"), metadataIndex = root.appendingPathComponent("metadata.json")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 12, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: metadataPNG)
        var metadataImage = try image(id: "42", path: metadataPNG.path)
        metadataImage.pixelWidth = nil; metadataImage.pixelHeight = nil
        try JSONEncoder().encode([metadataImage]).write(to: metadataIndex)
        let firstVideoStat = CatalogFileProbe.shared.holdNext()
        manager.wallpapers = [VideoWallpaper(id: "42", title: "metadata video", path: metadataDirectory.path)]
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
        let firstVideoProjection = controller.videoTask!
        let firstImageStat = CatalogFileProbe.shared.holdNext()
        images.persistenceURL = metadataIndex; images.load()
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 2 }
        let firstImageProjection = controller.imageTask!
        precondition(catalogHeaderReady.wait(timeout: .now() + 3) == .success)
        try FileManager.default.removeItem(at: metadataPNG)
        let metadataVideoStat = CatalogFileProbe.shared.holdNext()
        manager.scheduleInitialIndexFileSizes(manager.wallpapers)
        let videoMetadataPublished = await wait { manager.wallpapers.first?.fileSize != nil && CatalogFileProbe.shared.snapshot.active == 3 }
        let metadataVideoProjection = controller.videoTask!
        let metadataImageStat = CatalogFileProbe.shared.holdNext()
        catalogHeaderRelease.signal()
        let imageMetadataPublished = await wait { images.wallpapers.first?.pixelHeight == 12 && CatalogFileProbe.shared.snapshot.active == 4 }
        let metadataImageProjection = controller.imageTask!
        checks["real-size-and-header-completions-republish-the-same-held-resource-paths"] = videoMetadataPublished && imageMetadataPublished
            && manager.wallpapers.first?.path == metadataDirectory.path && images.wallpapers.first?.path == metadataPNG.path
            && controller.catalog.videos.first?.metadata.fileSizeBytes == manager.wallpapers.first?.fileSize
            && controller.catalog.images.first?.metadata.resolutionText == "8×12"
        checks["metadata-publications-keep-warm-rows-before-fresh-file-facts"] =
            controller.catalog.videos.first?.publishedAvailability == .available && controller.catalog.images.first?.publishedAvailability == .available
        firstVideoStat.signal(); firstImageStat.signal()
        await firstVideoProjection.value; await firstImageProjection.value
        checks["retired-file-receipts-cannot-overwrite-held-metadata-successors"] = firstVideoProjection.isCancelled && firstImageProjection.isCancelled
            && !metadataVideoProjection.isCancelled && !metadataImageProjection.isCancelled
            && controller.catalog.videos.first?.publishedAvailability == .available && controller.catalog.images.first?.publishedAvailability == .available
        metadataVideoStat.signal(); metadataImageStat.signal()
        await metadataVideoProjection.value; await metadataImageProjection.value
        checks["warm-same-path-metadata-is-never-reused-as-verified-availability"] =
            controller.catalog.videos.first?.publishedAvailability == .unavailable && controller.catalog.images.first?.publishedAvailability == .unavailable
            && controller.catalog.videos.first?.capabilities.contains(.play) == false && controller.catalog.images.first?.capabilities.contains(.play) == false
        CatalogFileProbe.shared.stop()
        manager.wallpapers = savedVideos; images.wallpapers = savedImages
        await controller.videoTask?.value; await controller.imageTask?.value

        var transient: WallpaperLibraryCatalogController? = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, pixabay: pixabay)
        transient?.setVisibleReferences([video.providerReference], sourceToken: UUID())
        weak let weakTransient = transient
        transient = nil
        checks["visible-cadence-does-not-retain-retired-catalog-owner"] = weakTransient == nil

        let oldRevision = controller.revisions[.videoLibrary]!
        manager.wallpapers = [VideoWallpaper(id: "new", title: "newer source", path: sharedFile.path)]
        checks["new-source-generation-replaces-current-video-content"] = await wait { controller.catalog.videos.first?.reference.sourceID == "new" }
        checks["late-old-source-completion-cannot-overwrite-new-catalog"] = !controller.publish([video], provider: .videoLibrary, revision: oldRevision)
            && controller.catalog.videos.first?.reference.sourceID == "new"
        await controller.mergeVisibleAvailability([video], provider: .videoLibrary, revision: oldRevision, generation: controller.visibleAvailabilityGeneration)
        checks["late-visible-file-result-cannot-revive-replaced-source-generation"] = controller.catalog.videos.first?.reference.sourceID == "new"
        let nfc = "Caf\u{00E9}", nfd = "Cafe\u{0301}"
        manager.wallpapers = [VideoWallpaper(id: nfc, title: "one", path: sharedFile.path), VideoWallpaper(id: nfd, title: "two", path: sharedFile.path)]
        images.wallpapers = [try image(id: nfc, path: sharedFile.path), try image(id: nfd, path: sharedFile.path)]
        steam.downloads = [record(id: nfc, video: sharedFile), record(id: nfd, video: sharedFile)]
        checks["opaque-unicode-source-id-bytes-stay-distinct"] = await wait {
            Set(controller.catalog.videos.map(\.reference)).count == 2
                && Set(controller.catalog.images.map(\.reference)).count == 2
                && Set(controller.catalog.downloads.map(\.reference)).count == 2
        }
        manager.wallpapers = [VideoWallpaper(id: nfc, title: "same", path: sharedFile.path)]
        images.wallpapers = [try image(id: nfc, path: sharedFile.path)]
        steam.downloads = [record(id: nfc, video: sharedFile)]
        _ = await wait {
            controller.catalog.videos.count == 1 && controller.catalog.videos[0].reference.sourceID.utf8.elementsEqual(nfc.utf8)
                && controller.catalog.images[0].reference.sourceID.utf8.elementsEqual(nfc.utf8)
                && controller.catalog.downloads.count == 1 && controller.catalog.downloads[0].reference.sourceID.utf8.elementsEqual(nfc.utf8)
        }
        manager.wallpapers = [VideoWallpaper(id: nfd, title: "same", path: sharedFile.path)]
        images.wallpapers = [try image(id: nfd, path: sharedFile.path)]
        steam.downloads = [record(id: nfd, video: sharedFile)]
        checks["publisher-dedup-does-not-swallow-byte-distinct-unicode-identity-replacement"] = await wait {
            controller.catalog.videos[0].reference.sourceID.utf8.elementsEqual(nfd.utf8)
                && controller.catalog.images[0].reference.sourceID.utf8.elementsEqual(nfd.utf8)
                && controller.catalog.downloads[0].reference.sourceID.utf8.elementsEqual(nfd.utf8)
        }
        manager.wallpapers = [VideoWallpaper(id: "42", title: "invalid directory", path: root.path)]
        images.wallpapers = [try image(id: "42", path: root.path)]
        checks["a-directory-is-not-advertised-as-a-playable-local-media-file"] = await wait {
            controller.catalog.videos.first?.publishedAvailability == .unavailable
                && controller.catalog.images.first?.publishedAvailability == .unavailable
        }
        manager.wallpapers = [VideoWallpaper(id: "42", title: "new resource", path: sharedFile.path)]
        images.wallpapers = [try image(id: "42", path: sharedFile.path)]
        checks["same-reference-resource-path-change-reresolves-availability"] = await wait {
            controller.catalog.videos.first?.publishedAvailability == .available
                && controller.catalog.images.first?.publishedAvailability == .available
        }
        checks["pixabay-has-no-fake-published-entry-before-source-publication"] = controller.catalog.downloads.allSatisfy { $0.reference.provider == .steamWorkshop }
        let webRoot = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: webRoot, withIntermediateDirectories: true)
        let project = webRoot.appendingPathComponent("project.json"), entry = webRoot.appendingPathComponent("resolved.html")
        try Data("{\"type\":\"web\",\"file\":\"declared.html\"}".utf8).write(to: project)
        try Data("<html></html>".utf8).write(to: entry)
        let web = SteamWorkshopDownloadRecord(id: "web-local", title: "Web", description: "", tags: [], folderURL: webRoot,
            projectFileURL: project, ownEntryHTMLURL: entry, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
            entryHTMLURL: entry, resolvedWebRootURL: webRoot, previewURL: nil, sourceVideoURL: nil, exportedVideoURL: nil,
            updatedAt: Date(), sizeText: "", status: .ready, browserItem: nil, contentType: .web,
            dependencyItemID: nil, dependencyStatus: .none)
        let selectedWeb = await steam.libraryContentItems(from: [web], jobs: [], account: nil, reusing: [], previousRecords: [])
        checks["web-admission-uses-existing-selected-entry-without-rediscovering-declaration"] = selectedWeb[0].publishedAvailability == .available
            && selectedWeb[0].capabilities.contains(.play)
        try FileManager.default.removeItem(at: entry)
        try Data("<html>declared</html>".utf8).write(to: webRoot.appendingPathComponent("declared.html"))
        let missingWeb = await steam.libraryContentItems(from: [web], jobs: [], account: nil, reusing: selectedWeb,
                                                        previousRecords: [web], refreshAll: true)
        checks["web-admission-rejects-missing-selected-entry-despite-other-html"] = missingWeb[0].publishedAvailability == .unavailable
            && !missingWeb[0].capabilities.contains(.play)
        try Data("<html>selected</html>".utf8).write(to: entry)
        let validWeb = await steam.libraryContentItems(from: [web], jobs: [], account: nil, reusing: missingWeb,
                                                      previousRecords: [web], refreshAll: true)
        checks["valid-web-remains-playable-through-original-provider-admission"] = validWeb[0].kind == .web
            && validWeb[0].capabilities.contains([.play, .organize])
        let failed = record(id: "failed-local-intent", video: root.appendingPathComponent("not-published.mp4"), status: .failed("failed"))
        let failedItems = await steam.libraryContentItems(from: [failed], jobs: [], account: nil, reusing: [], previousRecords: [])
        checks["failed-initial-intent-retains-original-owner-discard-without-fake-media"] = failedItems[0].publishedAvailability == .remote
            && failedItems[0].capabilities.contains([.delete, .retryDownload]) && !failedItems[0].capabilities.contains(.play)
        // The fourth provider consumes actual source facts, with no probing of
        // the supplied path by the catalog or false aliases to a Video row.
        let pixabayDate = Date(timeIntervalSince1970: 900)
        let pixabayEntry = PixabayDownloadedEntry(id: 42, localURL: sharedFile, fileSize: 1, duration: 8,
            resolutionString: "10×20", thumbnailSourceKey: "published-42", creationDate: pixabayDate,
            modificationDate: Date(timeIntervalSince1970: 901))
        steam.downloads = [record(id: "42", video: sharedFile)]
        _ = await wait { controller.catalog.downloads.first?.reference.sourceID == "42" }
        pixabay.downloadedContent = .init(revision: 1, entries: [pixabayEntry], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        checks["fourth-source-keeps-same-number-provider-identities-and-local-facts"] = await wait {
            controller.catalog.downloads.count == 2
                && Set([controller.catalog.videos[0].reference, controller.catalog.images[0].reference]
                    + controller.catalog.downloads.map(\.reference)).count == 4
                && controller.catalog.downloads.contains {
                $0.reference == WallpaperReference(provider: .pixabay, sourceID: "42")
                    && $0.publishedAvailability == .available && $0.capabilities.contains([.play, .organize, .delete])
                    && $0.aliases.isEmpty && $0.metadata.createdAt == pixabayDate && $0.metadata.modifiedAt != nil
            }
        }
        let pixabayRevision = controller.revisions[.pixabay]
        pixabay.downloadProgressByID = [42: 0.4]
        pixabay.items = [PixabayVideoItem(id: 99, pageURL: "https://fixture.invalid", tags: "remote", duration: 1,
            user: "remote", videos: .init(large: nil, medium: nil, small: nil, tiny: nil))]
        checks["pixabay-progress-and-browser-results-never-scan-or-enter-local-catalog"] = controller.revisions[.pixabay] == pixabayRevision
            && controller.catalog.downloads.count == 2
        var unavailable = pixabayEntry; unavailable.isAvailable = false
        pixabay.downloadedContent = .init(revision: 2, entries: [unavailable], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        checks["pixabay-unavailable-source-fact-retains-target-without-fake-play-or-organization"] = controller.catalog.downloads.last?.publishedAvailability == .unavailable
            && controller.catalog.downloads.last?.capabilities.contains(.delete) == true
            && controller.catalog.downloads.last?.capabilities.contains(.play) == false
            && controller.catalog.downloads.last?.capabilities.contains(.organize) == false
        steam.downloads = [record(id: "fresh-steam", video: sharedFile)]
        checks["steam-refresh-does-not-overwrite-pixabay-local-publications"] = await wait {
            controller.catalog.downloads.count == 2 && controller.catalog.downloads.first?.reference.sourceID == "fresh-steam"
                && controller.catalog.downloads.last?.reference.provider == .pixabay
        }
        pixabay.downloadedContent = .init(revision: 3, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        checks["pixabay-removal-does-not-overwrite-steam-publications"] = controller.catalog.downloads.count == 1
            && controller.catalog.downloads[0].reference.provider == .steamWorkshop
        var adultRecord = record(id: "adult", video: sharedFile)
        adultRecord.browserItem = try browser("adult", adult: true)
        var taggedRecord = record(id: "tagged", video: sharedFile)
        taggedRecord.browserItem = try browser("tagged", tags: ["  Mature  "])
        var unmarkedRecord = record(id: "ordinary", video: sharedFile, title: "nudity title is not official rating")
        unmarkedRecord.browserItem = try browser("ordinary", tags: ["nature"])
        steam.downloads = [adultRecord, taggedRecord, unmarkedRecord]
        _ = await wait { controller.catalog.downloads.count == 3 }
        let ratings = Dictionary(uniqueKeysWithValues: controller.catalog.downloads.map { ($0.reference.sourceID, $0.metadata.contentRating ?? .unknown) })
        checks["original-rating-marker-and-official-tags-project-adult-facts-without-dropping-publications"] = controller.catalog.downloads.count == 3
            && ratings["adult"] == .adult && ratings["tagged"] == .adult && controller.catalog.excludedDownloadReferences.isEmpty
        checks["download-rating-never-classifies-a-title-or-adds-another-source-visibility-owner"] = ratings["ordinary"] != .adult
            && controller.catalog.excludedDownloadReferences.isEmpty
        let queued = record(id: "queue-only", video: sharedFile, status: .queued)
        steam.downloads.append(queued)
        _ = await wait { controller.catalog.downloads.count == 4 }
        let queuedRef = WallpaperReference(provider: .steamWorkshop, sourceID: "queue-only")
        checks["first-acquisition-stays-in-task-popover-and-full-facts-not-page-membership"] = controller.catalog.excludedDownloadReferences.contains(queuedRef)
            && controller.catalog.downloads.contains { $0.providerReference == queuedRef }
        let beforeHistory = controller.revisions[.steamWorkshop]
        steam.downloadJobStore.history = [.init(jobID: "prior-failure", workshopItemId: "queue-only", title: "queued", accountSteamId: "account-A",
            attempt: 1, outcome: .failed, failureMessage: "old", recordID: nil, terminalAt: Date(timeIntervalSince1970: 1))]
        checks["history-only-publisher-restores-failed-retry-without-resource-revalidation"] = await wait {
            !controller.catalog.excludedDownloadReferences.contains(queuedRef)
        } && controller.revisions[.steamWorkshop] == beforeHistory
        steam.steamAuth.steamId = "account-B"
        checks["account-willset-uses-new-account-instead-of-borrowing-old-failure-history"] = controller.catalog.excludedDownloadReferences.contains(queuedRef)
        steam.steamAuth.steamId = nil
        checks["signed-out-willset-never-reuses-previous-account-history"] = controller.catalog.excludedDownloadReferences.contains(queuedRef)
        steam.steamAuth.steamId = "account-A"
        checks["returning-original-account-restores-qualified-retry"] = !controller.catalog.excludedDownloadReferences.contains(queuedRef)
        steam.downloadJobStore.history = []
        checks["clearing-history-without-jobs-change-removes-retry-from-downloads-page-only"] = await wait {
            controller.catalog.excludedDownloadReferences.contains(queuedRef)
        } && controller.catalog.downloads.contains { $0.providerReference == queuedRef }
        let refreshes = pixabay.refreshRequests
        controller.refreshAvailability()
        checks["explicit-catalog-refresh-delegates-once-to-existing-online-source"] = pixabay.refreshRequests == refreshes + 1
        var accountIntent = record(id: "account-intent", video: sharedFile, title: "A private failure", status: .failed("A error"))
        accountIntent.intentAccountSteamID = "account-A"
        let ownIntent = await steam.libraryContentItems(from: [accountIntent], jobs: [], account: "account-A", reusing: [], previousRecords: [])
        checks["typed-task-provenance-retains-current-account-metadata"] = ownIntent.first?.title == "A private failure"
            && ownIntent.first?.acquisition.failureMessage == "A error"
        for account in [String?.none, "", "account-B"] {
            let foreignItems = await steam.libraryContentItems(from: [accountIntent], jobs: [], account: account, reusing: ownIntent, previousRecords: [accountIntent])
            checks["typed-task-provenance-rejects-foreign-source-facts-\(account ?? "nil")"] = foreignItems.isEmpty
        }
        steam.steamAuth.steamId = "account-A"
        steam.downloads = [accountIntent]
        _ = await wait { controller.catalog.downloads.first?.title == "A private failure" }
        steam.steamAuth.steamId = "account-B"
        checks["account-willset-synchronously-revokes-foreign-facts-for-all-relationship-pages"] = controller.catalog.downloads.isEmpty
        _ = await wait { controller.steamTask?.isCancelled != true }
        steam.steamAuth.steamId = "account-A"
        checks["return-to-task-account-reprojects-original-failure"] = await wait {
            controller.catalog.downloads.first?.title == "A private failure"
        }
        steam.steamAuth.steamId = nil
        checks["logout-synchronously-revokes-derived-facts"] = controller.catalog.downloads.isEmpty
        let publishedSameID = record(id: "account-intent", video: sharedFile, title: "shared published")
        let sharedItems = await steam.libraryContentItems(from: [accountIntent, publishedSameID], jobs: [], account: "account-B", reusing: [], previousRecords: [])
        checks["foreign-task-with-same-id-cannot-hide-real-shared-publication"] = sharedItems.count == 1
            && sharedItems.first?.title == "shared published" && sharedItems.first?.capabilities.contains(.play) == true
        steam.downloads = [publishedSameID]
        _ = await wait { controller.catalog.downloads.first?.title == "shared published" }
        steam.downloads = [accountIntent, publishedSameID]
        checks["synchronous-revocation-preserves-same-id-untagged-publication"] = controller.catalog.downloads.first?.title == "shared published"

        // Source revision alone never proves that its first full scan worked.
        // The actual Combine subscription consumes each supplied snapshot even
        // though @Published delivers it before the source getter is replaced.
        let statusSource = PixabayService()
        statusSource.downloadedContent = .init(revision: 1, entries: [pixabayEntry], status: .initial)
        let statusCatalog = WallpaperLibraryCatalogController(manager: WallpaperManager(), images: SILService(),
            steam: SteamWorkshopService(), pixabay: statusSource)
        let initialOnlineItems = statusCatalog.catalog.downloads
        checks["entry-only-content-revision-is-playable-but-does-not-claim-a-successful-source-scan"] =
            initialOnlineItems.count == 1 && initialOnlineItems[0].capabilities.contains(.play)
            && !statusCatalog.catalog.loadedProviders.contains(.pixabay)
            && statusCatalog.catalog.sourceScanStatuses[.pixabay] == .initial
        let coldError = WallpaperSourceScanStatus(phase: .failed(message: "Cold source failure"), hasSuccessfulScan: false)
        let beforeColdFailure = statusCatalog.catalog.revision
        statusSource.downloadedContent = .init(revision: 1, entries: [pixabayEntry], status: coldError)
        checks["phase-only-cold-failure-reaches-catalog-without-hiding-direct-local-entries"] =
            statusCatalog.catalog.revision > beforeColdFailure && statusCatalog.catalog.downloads == initialOnlineItems
            && !statusCatalog.catalog.loadedProviders.contains(.pixabay)
            && statusCatalog.catalog.sourceScanStatuses[.pixabay] == coldError
        let readyWarnings = WallpaperSourceScanStatus(phase: .ready(warnings: ["Duplicate local filename"]), hasSuccessfulScan: true)
        statusSource.downloadedContent = .init(revision: 1, entries: [pixabayEntry], status: readyWarnings)
        checks["phase-only-first-success-publishes-warnings-and-real-readiness-without-new-content"] =
            statusCatalog.catalog.downloads == initialOnlineItems && statusCatalog.catalog.loadedProviders.contains(.pixabay)
            && statusCatalog.catalog.sourceScanStatuses[.pixabay] == readyWarnings
        let warmLoading = WallpaperSourceScanStatus(phase: .loading, hasSuccessfulScan: true)
        let beforeWarmLoading = statusCatalog.catalog.revision
        statusSource.downloadedContent = .init(revision: 1, entries: [pixabayEntry], status: warmLoading)
        checks["warm-loading-remains-playable-and-publishes-a-phase-only-catalog-revision"] =
            statusCatalog.catalog.revision > beforeWarmLoading && statusCatalog.catalog.downloads == initialOnlineItems
            && statusCatalog.catalog.loadedProviders.contains(.pixabay)
            && statusCatalog.catalog.sourceScanStatuses[.pixabay] == warmLoading
        let beforeDuplicate = statusCatalog.catalog.revision, beforeDuplicateSource = statusCatalog.revisions[.pixabay]
        statusSource.downloadedContent = .init(revision: 2, entries: [pixabayEntry], status: warmLoading)
        checks["identical-scan-state-and-content-do-not-repeat-projection-or-catalog-publication"] =
            statusCatalog.catalog.revision == beforeDuplicate && statusCatalog.revisions[.pixabay] == beforeDuplicateSource
        let warmError = WallpaperSourceScanStatus(phase: .failed(message: "Warm source failure"), hasSuccessfulScan: true)
        statusSource.downloadedContent = .init(revision: 2, entries: [pixabayEntry], status: warmError)
        checks["warm-failure-retains-real-success-readiness-and-original-playable-content"] =
            statusCatalog.catalog.downloads == initialOnlineItems && statusCatalog.catalog.loadedProviders.contains(.pixabay)
            && statusCatalog.catalog.sourceScanStatuses[.pixabay] == warmError
        statusSource.downloadedContent = .init(revision: 2, entries: [pixabayEntry],
            status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        checks["retry-ready-clears-prior-warning-or-failure-through-the-single-snapshot"] =
            statusCatalog.catalog.sourceScanStatuses[.pixabay] == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)
            && statusCatalog.catalog.downloads == initialOnlineItems && statusSource.refreshRequests == 0
        let warmSource = PixabayService()
        warmSource.downloadedContent = .init(revision: 9, entries: [pixabayEntry], status: warmLoading)
        let lateSubscriber = WallpaperLibraryCatalogController(manager: WallpaperManager(), images: SILService(),
            steam: SteamWorkshopService(), pixabay: warmSource)
        checks["initial-subscription-to-a-warm-refresh-preserves-real-success-without-waiting-for-next-scan"] =
            lateSubscriber.catalog.loadedProviders.contains(.pixabay)
            && lateSubscriber.catalog.sourceScanStatuses[.pixabay] == warmLoading
            && lateSubscriber.catalog.downloads.count == 1
        func onlineRecord(_ source: OnlineImageSource, page: Int = 0) -> OnlineImageLocalRecord {
            .init(assetID: .init(source: source, artworkID: "42", pageIndex: page), title: "Same online title",
                sourceURL: URL(string: "https://example.org/42")!, author: nil, authorID: nil, tags: [],
                relativePath: source.rawValue + "/fixture.png", pixelWidth: 40, pixelHeight: 30,
                fileSizeBytes: 3, firstDownloadedAt: Date(timeIntervalSince1970: 9), revision: UUID())
        }
        let wallhaven = onlineRecord(.wallhaven), pixiv = onlineRecord(.pixiv, page: 2)
        await controller.videoTask?.value; await controller.imageTask?.value; await controller.steamTask?.value
        var imagePublications: [WallpaperLibraryCatalog] = []
        let imagePublicationObserver = controller.$catalog.dropFirst().sink { imagePublications.append($0) }
        let earlierDownloads = Set(controller.catalog.downloads.map(\.reference))
        OnlineImageLibrary.shared.snapshot = .init(records: [wallhaven, pixiv], unavailable: [pixiv.id],
            sourceStatuses: onlineStatuses(.init(phase: .ready(warnings: []), hasSuccessfulScan: true)), revision: 2)
        checks["online-image-snapshot-publishes-each-provider-without-dropping-existing-downloads"] =
            earlierDownloads.isSubset(of: Set(controller.catalog.downloads.map(\.reference)))
            && controller.catalog.downloads.contains { $0.reference == wallhaven.id.reference && $0.kind == .image && $0.capabilities.contains(.play) }
            && controller.catalog.downloads.contains { $0.reference == pixiv.id.reference && $0.publishedAvailability == .unavailable && !$0.capabilities.contains(.play) }
            && controller.catalog.loadedProviders.isSuperset(of: [.wallhaven, .pixiv])
        checks["first-online-image-scan-publishes-both-complete-provider-subsets-together"] = imagePublications.count == 1
            && imagePublications.first?.downloads == controller.catalog.downloads
            && imagePublications.first?.loadedProviders.isSuperset(of: [.wallhaven, .pixiv]) == true
            && imagePublications.first?.sourceScanStatuses[.wallhaven] == .init(phase: .ready(warnings: []), hasSuccessfulScan: true)
            && imagePublications.first?.sourceScanStatuses[.pixiv] == imagePublications.first?.sourceScanStatuses[.wallhaven]
        steam.downloads = []
        _ = await wait { controller.catalog.downloads.allSatisfy { $0.reference.provider != .steamWorkshop } }
        checks["later-steam-and-pixabay-publications-preserve-new-image-provider-subsets"] = controller.catalog.downloads.contains { $0.reference == wallhaven.id.reference }
            && controller.catalog.downloads.contains { $0.reference == pixiv.id.reference }
        let otherProviders = controller.catalog.downloads.filter { $0.reference.provider != .wallhaven && $0.reference.provider != .pixiv }
        OnlineImageLibrary.shared.snapshot = .init(sourceStatuses: onlineStatuses(.init(phase: .ready(warnings: []), hasSuccessfulScan: true)), revision: 3)
        checks["successful-empty-image-scan-clears-only-image-subsets-without-network-readiness"] = controller.catalog.downloads == otherProviders
            && controller.catalog.loadedProviders.isSuperset(of: [.wallhaven, .pixiv])
        await controller.steamTask?.value
        await controller.videoTask?.value; await controller.imageTask?.value
        let preservedVideos = controller.catalog.videos, preservedImages = controller.catalog.images
        var imageSnapshot = OnlineImageLocalSnapshot(records: [pixiv, wallhaven], unavailable: [pixiv.id],
            sourceStatuses: onlineStatuses(.init(phase: .ready(warnings: []), hasSuccessfulScan: true)), revision: 4)
        imagePublications.removeAll()
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["two-image-provider-replacements-publish-once-in-the-original-source-order"] = imagePublications.count == 1
            && imagePublications.first?.downloads.map(\.reference) == otherProviders.map(\.reference) + [wallhaven.id.reference, pixiv.id.reference]
            && imagePublications.first?.downloads == controller.catalog.downloads
        let imageDownloads = controller.catalog.downloads
        imagePublications.removeAll()
        imageSnapshot.sourceStatuses = onlineStatuses(.init(phase: .failed(message: "Shared image scan failed"), hasSuccessfulScan: true))
        imageSnapshot.revision += 1
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["shared-image-scan-failure-publishes-one-complete-status-without-losing-content-or-readiness"] = imagePublications.count == 1
            && imagePublications.first?.downloads == imageDownloads
            && imagePublications.first?.loadedProviders.isSuperset(of: [.wallhaven, .pixiv]) == true
            && imagePublications.first?.sourceScanStatuses[.wallhaven] == imageSnapshot.status
            && imagePublications.first?.sourceScanStatuses[.pixiv] == imageSnapshot.status
        imagePublications.removeAll()
        imageSnapshot.unavailable = [wallhaven.id]
        imageSnapshot.revision += 1
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["both-image-availability-changes-arrive-in-one-catalog-value"] = imagePublications.count == 1
            && imagePublications.first?.downloads.first { $0.reference == wallhaven.id.reference }?.publishedAvailability == .unavailable
            && imagePublications.first?.downloads.first { $0.reference == pixiv.id.reference }?.publishedAvailability == .available
        imagePublications.removeAll()
        imageSnapshot.records.removeFirst()
        imageSnapshot.revision += 1
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["single-image-provider-removal-preserves-the-other-provider-and-download-subsets"] = imagePublications.count == 1
            && imagePublications.first?.downloads.map(\.reference) == otherProviders.map(\.reference) + [wallhaven.id.reference]
            && imagePublications.first?.downloads.first { $0.reference == wallhaven.id.reference }?.publishedAvailability == .unavailable
        imagePublications.removeAll()
        let imageRevisions = controller.revisions
        imageSnapshot.revision += 1
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["identical-image-rescan-does-not-publish-but-advances-both-source-receipts"] = imagePublications.isEmpty
            && OnlineImageSource.allCases.allSatisfy { source in
                controller.revisions[source.provider] == (imageRevisions[source.provider] ?? 0) &+ 1
                    && controller.publishedRevisions[source.provider] == controller.revisions[source.provider]
            }
        imagePublications.removeAll()
        imageSnapshot.records = []; imageSnapshot.unavailable = []
        imageSnapshot.sourceStatuses = onlineStatuses(.init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        imageSnapshot.revision += 1
        OnlineImageLibrary.shared.snapshot = imageSnapshot
        checks["successful-empty-image-rescan-publishes-both-ready-subsets-once-and-preserves-other-sources"] = imagePublications.count == 1
            && imagePublications.first?.downloads == otherProviders
            && imagePublications.first?.videos == preservedVideos && imagePublications.first?.images == preservedImages
            && imagePublications.first?.loadedProviders.isSuperset(of: [.wallhaven, .pixiv]) == true
            && imagePublications.first?.sourceScanStatuses[.wallhaven] == imageSnapshot.status
            && imagePublications.first?.sourceScanStatuses[.pixiv] == imageSnapshot.status
        imagePublicationObserver.cancel()
        do {
            let warmRoot = root.appendingPathComponent("steam-warm", isDirectory: true)
            try FileManager.default.createDirectory(at: warmRoot, withIntermediateDirectories: true)
            let warmVideo = warmRoot.appendingPathComponent("last.mp4"), entry = warmRoot.appendingPathComponent("index.html")
            try Data([7]).write(to: warmVideo); try Data("<html></html>".utf8).write(to: entry)
            let source = SteamWorkshopService()
            var videoRow = record(id: "warm-video", video: warmVideo)
            videoRow.isStartupSnapshot = true
            source.downloads = [videoRow, record(id: "warm-web", video: entry, type: .web, entry: entry),
                record(id: "warm-scene", video: warmRoot.appendingPathComponent("scene.json"), type: .scene),
                record(id: "42", video: warmVideo, status: .downloading, owner: "account-A"),
                record(id: "foreign", video: warmVideo, status: .downloading, owner: "account-B")]
            source.downloadJobStore.jobs = [job(state: .running)]
            CatalogSteamIOProbe.shared.reset()
            let warm = WallpaperLibraryCatalogController(manager: WallpaperManager(), images: SILService(), steam: source, pixabay: PixabayService())
            let local = warm.catalog.downloads.filter { $0.acquisition == .idle }
            checks["steam-stored-video-web-scene-publish-synchronously-with-inspect-only"] = local.count == 3
                && Set(local.map(\.kind)) == [.video, .web, .scene] && local.allSatisfy { $0.capabilities == [.inspect] }
            checks["steam-warm-source-retains-real-current-account-transfer-cancel"] = warm.catalog.downloads.count == 4
                && warm.catalog.downloads.first { $0.reference.sourceID == "42" }?.capabilities.contains(.cancelDownload) == true
                && warm.catalog.downloads.first { $0.reference.sourceID == "42" }?.acquisition.phase == .transferring
            source.steamAuth.steamId = "account-B"
            checks["steam-warm-account-switch-revokes-old-private-intent-synchronously"] =
                !warm.catalog.downloads.contains { $0.reference.sourceID == "42" }
                && warm.catalog.downloads.contains { $0.reference.sourceID == "foreign" }
            source.steamAuth.steamId = "account-A"
            try await Task.sleep(for: .milliseconds(20))
            checks["steam-warm-never-enters-cold-file-or-launch-consumers"] = CatalogSteamIOProbe.shared.snapshot.isEmpty
                && warm.steamTask == nil
            checks["steam-warm-does-not-announce-full-readiness-or-checked-facts"] = !source.hasCompletedInstalledLibraryLoad
                && !warm.catalog.loadedProviders.contains(.steamWorkshop) && warm.publishedRevisions[.steamWorkshop] == nil
            try FileManager.default.removeItem(at: warmVideo)
            source.hasCompletedInstalledLibraryLoad = true
            await warm.steamTask?.value
            let reads = CatalogSteamIOProbe.shared.snapshot
            checks["steam-fresh-enters-original-video-web-and-scene-consumers"] = reads["video:warm-video", default: 0] > 0
                && reads["web:warm-web", default: 0] > 0 && reads["launch:warm-scene", default: 0] > 0
            checks["steam-fresh-does-not-reuse-unchecked-warm-availability"] = warm.catalog.loadedProviders.contains(.steamWorkshop)
                && warm.publishedRevisions[.steamWorkshop] == warm.revisions[.steamWorkshop]
                && warm.catalog.downloads.first { $0.reference.sourceID == "warm-video" }?.publishedAvailability == .unavailable
        }
        do {
            func row(_ provider: WallpaperProvider, _ id: String, size: Int64 = 3,
                     availability: WallpaperPublishedAvailability = .available,
                     capabilities: WallpaperContentCapabilities = [.inspect, .play, .organize]) -> WallpaperContentItem {
                let reference = WallpaperReference(provider: provider, sourceID: id)
                return .init(reference: reference, providerReference: reference,
                    locator: .init(path: sharedFile.path, titleHint: id, mediaKind: provider == .videoLibrary ? .video : .image),
                    title: id, kind: provider == .videoLibrary ? .video : .image, publishedAvailability: availability,
                    capabilities: capabilities, metadata: .init(fileSizeBytes: size), acquisition: .idle, update: .idle, aliases: [])
            }
            for provider in [WallpaperProvider.videoLibrary, .staticImageLibrary] {
                var rows = (0..<4999).map { row(provider, "large-\($0)") }
                rows.append(rows[3])
                let revision: UInt64 = 777
                controller.revisions[provider] = revision; controller.publishedRevisions[provider] = revision
                var initial = controller.catalog
                if provider == .videoLibrary { initial.videos = rows } else { initial.images = rows }
                controller.install(initial)
                let original = controller.catalog, originalRevisions = controller.revisions
                var beforePublish = CatalogVisibleFilterProbe.publishEntries, beforeInstall = CatalogVisibleFilterProbe.installEntries
                await controller.mergeVisibleAvailability([rows[3], rows[4000], row(provider, "not-in-source")], provider: provider, revision: revision, generation: controller.visibleAvailabilityGeneration)
                checks["large-\(provider)-unchanged-or-unmatched-updates-preserve-full-catalog-and-source-facts"] =
                    controller.catalog.videos == original.videos && controller.catalog.images == original.images
                    && controller.catalog.downloads == original.downloads && controller.catalog.revision == original.revision
                    && controller.catalog.loadedProviders == original.loadedProviders && controller.catalog.sourceScanStatuses == original.sourceScanStatuses
                    && controller.revisions == originalRevisions && controller.publishedRevisions[provider] == revision
                checks["large-\(provider)-unchanged-or-unmatched-updates-skip-publish-and-install"] =
                    CatalogVisibleFilterProbe.publishEntries == beforePublish && CatalogVisibleFilterProbe.installEntries == beforeInstall
                let metadata = row(provider, "large-3", size: 123), ignoredDuplicate = row(provider, "large-3", size: 999)
                var expected = rows
                expected[3] = metadata; expected[4999] = metadata
                beforePublish = CatalogVisibleFilterProbe.publishEntries; beforeInstall = CatalogVisibleFilterProbe.installEntries
                await controller.mergeVisibleAvailability([metadata, ignoredDuplicate], provider: provider, revision: revision, generation: controller.visibleAvailabilityGeneration)
                let changed = provider == .videoLibrary ? controller.catalog.videos : controller.catalog.images
                checks["large-\(provider)-metadata-only-change-keeps-first-update-replaces-all-duplicate-rows-and-order"] = changed == expected
                    && controller.catalog.revision == original.revision &+ 1 && controller.revisions == originalRevisions
                checks["large-\(provider)-metadata-change-uses-original-single-publication-chain"] =
                    CatalogVisibleFilterProbe.publishEntries == beforePublish + 1 && CatalogVisibleFilterProbe.installEntries == beforeInstall + 1
                let unavailable = row(provider, "large-4000", availability: .unavailable, capabilities: [.inspect])
                expected[4000] = unavailable
                beforePublish = CatalogVisibleFilterProbe.publishEntries; beforeInstall = CatalogVisibleFilterProbe.installEntries
                await controller.mergeVisibleAvailability([unavailable], provider: provider, revision: revision, generation: controller.visibleAvailabilityGeneration)
                checks["large-\(provider)-availability-and-capabilities-change-retains-complete-other-rows"] =
                    (provider == .videoLibrary ? controller.catalog.videos : controller.catalog.images) == expected
                    && controller.catalog.revision == original.revision &+ 2 && controller.revisions == originalRevisions
                checks["large-\(provider)-availability-change-uses-original-single-publication-chain"] =
                    CatalogVisibleFilterProbe.publishEntries == beforePublish + 1 && CatalogVisibleFilterProbe.installEntries == beforeInstall + 1
                let rejected: [(String, UInt64?, UInt64)] = [
                    ("nil", nil, revision), ("stale", revision - 1, revision), ("not-yet-published", revision, revision - 1)]
                for (name, receipt, published) in rejected {
                    controller.publishedRevisions[provider] = published
                    beforePublish = CatalogVisibleFilterProbe.publishEntries; beforeInstall = CatalogVisibleFilterProbe.installEntries
                    await controller.mergeVisibleAvailability([rows[4000]], provider: provider, revision: receipt, generation: controller.visibleAvailabilityGeneration)
                    checks["large-\(provider)-\(name)-revision-cannot-enter-publication-or-replace-rows"] =
                        (provider == .videoLibrary ? controller.catalog.videos : controller.catalog.images) == expected
                        && controller.catalog.revision == original.revision &+ 2
                        && CatalogVisibleFilterProbe.publishEntries == beforePublish && CatalogVisibleFilterProbe.installEntries == beforeInstall
                }
                controller.publishedRevisions[provider] = revision
            }
        }
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }

    static func image(id: String, path: String) throws -> SILWallpaper {
        try JSONDecoder().decode(SILWallpaper.self, from: JSONSerialization.data(withJSONObject: [
            "id": id, "path": path, "title": "same title", "tags": [], "lastUsed": 0, "addedAt": 123,
            "pixelWidth": 40, "pixelHeight": 30]))
    }
    static func browser(_ id: String, tags: [String] = [], adult: Bool = false) throws -> SteamWorkshopBrowserItem {
        try JSONDecoder().decode(SteamWorkshopBrowserItem.self, from: JSONSerialization.data(withJSONObject: [
            "id": id, "title": "remote", "author": "fixture", "summary": "", "tags": tags,
            "hasAdultContent": adult, "descriptionText": "", "dependencyIDs": [],
            "previewAssetKind": "stillImage", "workshopTypeText": "video", "detailFields": [],
            "detailURL": "https://fixture.invalid/\(id)"]))
    }
    static func record(id: String, video: URL, title: String = "same title", status: SteamWorkshopDownloadRecord.Status = .ready,
                       type: SteamWorkshopDownloadContentType = .video, entry: URL? = nil, owner: String? = nil) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(id: id, title: title, description: "", tags: [], folderURL: video.deletingLastPathComponent(),
            projectFileURL: nil, ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
            entryHTMLURL: entry, resolvedWebRootURL: entry?.deletingLastPathComponent(), previewURL: nil,
            sourceVideoURL: type == .video ? video : nil, exportedVideoURL: nil,
            updatedAt: Date(timeIntervalSince1970: 30), sizeText: "", status: status, browserItem: nil,
            contentType: type, dependencyItemID: nil, dependencyStatus: .none,
            createdAt: Date(timeIntervalSince1970: 20), sizeBytes: nil, intentAccountSteamID: owner)
    }
    static func job(state: SteamDownloadJobState) -> SteamDownloadJob {
        SteamDownloadJob(id: "job-1", workshopItemId: "42", title: "download", state: state,
            attempt: 2, queueOrdinal: 0, accountSteamId: "account-A", stagingPath: nil,
            failureMessage: "replacement failed", createdAt: Date(timeIntervalSince1970: 40), updatedAt: Date(timeIntervalSince1970: 50))
    }
}
