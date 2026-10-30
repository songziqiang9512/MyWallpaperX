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
    static var videoVisits = 0
    static var imageVisits = 0
}

// Instrument only the original detached file worker. FileManager and both
// production projection bodies still execute; a barrier models one slow stat.
nonisolated final class CatalogFileProbe: @unchecked Sendable {
    static let shared = CatalogFileProbe()
    private let lock = NSLock()
    private var nextBarrier: DispatchSemaphore?
    private var recording = false
    private var active = 0
    private var maximum = 0
    private var total = 0
    private var stayedOffMain = true
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

// Pure provider leaves only: no live singleton, network, UI or runtime starts.
nonisolated struct SteamWorkshopStagingLeaseIdentity: Codable, Equatable {}
nonisolated struct SteamWorkshopStagedReceipt: Codable, Equatable {}
nonisolated struct SteamWorkshopLibraryCommit: Codable, Equatable {}
final class WallpaperManager {
    @Published var wallpapers: [VideoWallpaper] = []
    @Published var didFinishInitialIndexLoad = false
}
final class SILService { @Published var wallpapers: [SILWallpaper] = [] }
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
        let controller = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, pixabay: pixabay)
        var checks: [String: Bool] = [:]
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
        checks["three-real-source-subscriptions-publish-initial-values"] = await wait {
            controller.catalog.videos.count == 1 && controller.catalog.images.count == 1 && controller.catalog.downloads.count == 2
        }
        checks["unloaded-video-steam-and-online-initial-values-are-not-declared-empty-libraries"] =
            controller.catalog.loadedProviders == [.staticImageLibrary]
        let beforeReadiness = controller.catalog.revision
        manager.didFinishInitialIndexLoad = true
        steam.hasCompletedInstalledLibraryLoad = true
        pixabay.downloadedContent = .init(revision: 1, entries: [], status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true))
        OnlineImageLibrary.shared.snapshot = .init(status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true), revision: 1)
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
        let videoToken = UUID(), imageToken = UUID()
        CatalogVisibleFilterProbe.videoVisits = 0; CatalogVisibleFilterProbe.imageVisits = 0
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
            CatalogVisibleFilterProbe.videoVisits > 0 && CatalogVisibleFilterProbe.imageVisits > 0 && visiblePreviewRepairs > 0
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
        CatalogVisibleFilterProbe.videoVisits = 0; CatalogVisibleFilterProbe.imageVisits = 0; visiblePreviewRepairs = 0
        await controller.refreshVisibleAvailability()
        checks["empty-visible-scope-skips-both-provider-arrays-and-preview-repair"] =
            CatalogVisibleFilterProbe.videoVisits == 0 && CatalogVisibleFilterProbe.imageVisits == 0 && visiblePreviewRepairs == 0
        controller.setVisibleReferences([still.providerReference], sourceToken: imageToken)
        checks["one-consumer-scope-never-refreshes-another-provider"] = await wait { controller.catalog.images[0].publishedAvailability == .unavailable }
            && controller.catalog.videos[0].publishedAvailability == .available
        checks["image-only-visible-scope-skips-video-array-and-preview-repair"] =
            CatalogVisibleFilterProbe.videoVisits == 0 && CatalogVisibleFilterProbe.imageVisits > 0 && visiblePreviewRepairs == 0
        CatalogVisibleFilterProbe.videoVisits = 0; CatalogVisibleFilterProbe.imageVisits = 0
        controller.setVisibleReferences([video.providerReference], sourceToken: videoToken)
        controller.setVisibleReferences([], sourceToken: imageToken)
        checks["releasing-one-viewport-does-not-cancel-another-consumer"] = await wait { controller.catalog.videos[0].publishedAvailability == .unavailable }
            && controller.visibleAvailabilityTask != nil
        checks["video-only-visible-scope-skips-image-array-and-keeps-preview-repair"] =
            CatalogVisibleFilterProbe.videoVisits > 0 && CatalogVisibleFilterProbe.imageVisits == 0 && visiblePreviewRepairs > 0
        controller.setVisibleReferences([], sourceToken: videoToken)
        try Data([4]).write(to: sharedFile)
        controller.refreshAvailability()
        _ = await wait { controller.catalog.videos[0].publishedAvailability == .available }
        // Rapid viewport changes and hide/reopen during a slow source stat
        // must wait for its real completion, not merely cancel its parent Task.
        let held = CatalogFileProbe.shared.holdNext()
        let boundedToken = UUID()
        CatalogVisibleFilterProbe.videoVisits = 0; CatalogVisibleFilterProbe.imageVisits = 0
        controller.setVisibleReferences([video.providerReference], sourceToken: boundedToken)
        _ = await wait { CatalogFileProbe.shared.snapshot.active == 1 }
        let firstVideoVisits = CatalogVisibleFilterProbe.videoVisits
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
            CatalogVisibleFilterProbe.videoVisits > firstVideoVisits && CatalogVisibleFilterProbe.imageVisits == 0
        checks["coalesced-catchup-keeps-single-flight-through-uninterruptible-worker"] = CatalogFileProbe.shared.snapshot.maximum == 1
        controller.setVisibleReferences([], sourceToken: boundedToken)
        _ = await wait { controller.visibleAvailabilityTask == nil }
        let beforeHidden = CatalogFileProbe.shared.snapshot.total
        CatalogVisibleFilterProbe.videoVisits = 0; CatalogVisibleFilterProbe.imageVisits = 0
        try await Task.sleep(for: .milliseconds(50))
        checks["empty-scope-never-restarts-a-retired-slow-file-worker"] = CatalogFileProbe.shared.snapshot.total == beforeHidden
            && controller.visibleAvailabilityTask == nil
        checks["closed-visible-scope-never-traverses-either-provider-array"] =
            CatalogVisibleFilterProbe.videoVisits == 0 && CatalogVisibleFilterProbe.imageVisits == 0
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
            && controller.catalog.videos.first?.title != "retired refresh source" && controller.catalog.videos.first?.title != "successor refresh source"
        successorBarrier.signal(); await successorProjection.value
        checks["successor-source-keeps-its-real-publication-after-the-retired-worker-exits"] = !successorProjection.isCancelled
            && controller.catalog.videos.first?.title == "successor refresh source"
            && controller.catalog.videos.first?.publishedAvailability == .available
        CatalogFileProbe.shared.stop()

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
        controller.mergeVisibleAvailability([video], provider: .videoLibrary, revision: oldRevision)
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
        let earlierDownloads = Set(controller.catalog.downloads.map(\.reference))
        OnlineImageLibrary.shared.snapshot = .init(records: [wallhaven, pixiv], unavailable: [pixiv.id],
            status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true), revision: 2)
        checks["online-image-snapshot-publishes-each-provider-without-dropping-existing-downloads"] =
            earlierDownloads.isSubset(of: Set(controller.catalog.downloads.map(\.reference)))
            && controller.catalog.downloads.contains { $0.reference == wallhaven.id.reference && $0.kind == .image && $0.capabilities.contains(.play) }
            && controller.catalog.downloads.contains { $0.reference == pixiv.id.reference && $0.publishedAvailability == .unavailable && !$0.capabilities.contains(.play) }
            && controller.catalog.loadedProviders.isSuperset(of: [.wallhaven, .pixiv])
        steam.downloads = []
        _ = await wait { controller.catalog.downloads.allSatisfy { $0.reference.provider != .steamWorkshop } }
        checks["later-steam-and-pixabay-publications-preserve-new-image-provider-subsets"] = controller.catalog.downloads.contains { $0.reference == wallhaven.id.reference }
            && controller.catalog.downloads.contains { $0.reference == pixiv.id.reference }
        let otherProviders = controller.catalog.downloads.filter { $0.reference.provider != .wallhaven && $0.reference.provider != .pixiv }
        OnlineImageLibrary.shared.snapshot = .init(status: .init(phase: .ready(warnings: []), hasSuccessfulScan: true), revision: 3)
        checks["successful-empty-image-scan-clears-only-image-subsets-without-network-readiness"] = controller.catalog.downloads == otherProviders
            && controller.catalog.loadedProviders.isSuperset(of: [.wallhaven, .pixiv])
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
    static func record(id: String, video: URL, title: String = "same title", status: SteamWorkshopDownloadRecord.Status = .ready) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(id: id, title: title, description: "", tags: [], folderURL: video.deletingLastPathComponent(),
            projectFileURL: nil, ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
            entryHTMLURL: nil, resolvedWebRootURL: nil, previewURL: nil, sourceVideoURL: video, exportedVideoURL: nil,
            updatedAt: Date(timeIntervalSince1970: 30), sizeText: "", status: status, browserItem: nil,
            contentType: .video, dependencyItemID: nil, dependencyStatus: .none,
            createdAt: Date(timeIntervalSince1970: 20), sizeBytes: nil)
    }
    static func job(state: SteamDownloadJobState) -> SteamDownloadJob {
        SteamDownloadJob(id: "job-1", workshopItemId: "42", title: "download", state: state,
            attempt: 2, queueOrdinal: 0, accountSteamId: "account-A", stagingPath: nil,
            failureMessage: "replacement failed", createdAt: Date(timeIntervalSince1970: 40), updatedAt: Date(timeIntervalSince1970: 50))
    }
}
