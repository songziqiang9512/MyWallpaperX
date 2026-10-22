import AppKit
import Combine

struct BrowserMetadata: Equatable {
    var author = "Author"
    var hasAdultContent = false
    var tags: [String] = []
}
struct SteamWorkshopDownloadRecord: Equatable {
    enum Status: Equatable { case ready, failed(String), queued, downloading }
    enum ContentType { case video, web, scene, unknown }
    let id: String
    var title = "Wallpaper"
    var description = ""
    var tags: [String] = []
    var browserItem: BrowserMetadata?
    var status = Status.ready
    var contentType = ContentType.video
    var updatedAt = Date(timeIntervalSince1970: 1)
    var createdAt: Date? = nil
    var sizeBytes: Int64? = nil
    var sizeText = "10"
}
enum SteamDownloadJobState { case failed, queued, running, staged, committing, cancelled, completed }
struct SteamDownloadJob {
    let accountSteamId: String
    let workshopItemId: String
    var state: SteamDownloadJobState
}
struct IntentHistory {
    enum Outcome { case failed, completed, cancelled }
    let accountSteamId: String
    let workshopItemId: String
    let outcome: Outcome
}
final class IntentStore {
    var jobs: [SteamDownloadJob] = []
    private var storedHistory = [IntentHistory(accountSteamId: "A", workshopItemId: "retry", outcome: .failed)]
    private(set) var historyReadCount = 0
    var history: [IntentHistory] {
        get { historyReadCount += 1; return storedHistory }
        set { storedHistory = newValue }
    }
}
final class IntentAuth { var steamId: String? = "A" }
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    // DOWNLOADS_PROPERTY
    @Published var displayedDownloads: [SteamWorkshopDownloadRecord] = []
    var downloadsDisplayMode = SteamWorkshopDownloadsDisplayMode.all
    var downloadsSortMode = SteamWorkshopDownloadsSortMode.createdAt
    var downloadsSortAscending = false
    var downloadsQuery = ""
    var isDownloadsMultiSelectMode = false
    var selectedDownloadID: String?
    var selectedDownloadIDs: Set<String> = []
    var removingDownloadIDs: Set<String> = []
    var deleteRequests: [Set<String>] = []
    var downloadSelectionPublicationVersion = 0
    func syncDownloadsInspectorSelectionIfNeeded() {}
    func deleteDownloads(itemIDs: [String]) { deleteRequests.append(Set(itemIDs)) }
    var mergeCalls = 0
    let downloadJobStore = IntentStore()
    let steamAuth = IntentAuth()
    // Record-construction leaves adapt the real intent projection to the small
    // value model above; account/history/dedup and publication bodies are real.
    func synthesizedFailedIntentRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        .init(id: job.workshopItemId, status: .failed("fixture"), contentType: .unknown)
    }
    func synthesizedActiveRetryRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        .init(id: job.workshopItemId, status: job.state == .queued ? .queued : .downloading, contentType: .unknown)
    }
    static func parseByteCount(from text: String) -> Int64? { Int64(text) }
    static func workshopItemIDSearchID(from query: String) -> String? { nil }
    // STEAM_METHODS
}
struct OnlineEntry {
    let id: Int
    var localURL: URL { URL(fileURLWithPath: "/fixture/online_\(id).mp4") }
}
@MainActor final class OnlineDownloadsBridge {
    static let shared = OnlineDownloadsBridge()
    func refreshToolbar() {}
}
enum ProbeSection: Hashable { case main }
@MainActor final class HeldSnapshotDataSource {
    var completions: [() -> Void] = []
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<ProbeSection, Int>, animatingDifferences: Bool,
               completion: @escaping () -> Void) { completions.append(completion) }
    func release() { let callbacks = completions; completions = []; callbacks.forEach { $0() } }
}
@MainActor final class OnlineLibraryService {
    static let shared = OnlineLibraryService()
    var deletedURLs: [URL] = []
    func deleteLocalFile(at url: URL) { deletedURLs.append(url) }
}
@MainActor final class OnlineProbe {
    var entries: [OnlineEntry] = [.init(id: 1), .init(id: 2), .init(id: 3)]
    var entriesByID: [Int: OnlineEntry] { Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }) }
    var selectedIDs: Set<Int> = [1, 2]
    var selectedAnchorID: Int? = 1
    var isMultiSelectMode = true
    let collectionView = NSCollectionView()
    var pendingPostDeletionSelectionIndex: Int?
    var pendingPostDeletionSelectionGeneration: Int?
    var orderedIDs = [1, 2, 3]
    var orderedIndexByID: [Int: Int] { Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) }) }
    var lastAppliedSnapshotIDs: [Int] = []
    typealias Section = ProbeSection
    let dataSource = HeldSnapshotDataSource()
    var reloadEntriesGeneration = 0
    var deletionBatchReloadGeneration: Int?
    var reloads = 0
    var thumbnailDemandSchedules = 0
    func reloadEntries() {
        reloads += 1; reloadEntriesGeneration += 1
        if pendingPostDeletionSelectionIndex != nil { pendingPostDeletionSelectionGeneration = reloadEntriesGeneration }
    }
    func refreshVisiblePlaybackItems(forceReload: Bool = false) {}
    func scrollToSelectedItemIfNeeded() {}
    func reloadVisibleSelectionItems(forceReload: Bool = false) {}
    func syncInspectorSelectionIfNeeded() {}
    func scheduleThumbnailDemand() { thumbnailDemandSchedules += 1 }
    // ONLINE_METHODS
}
struct SILWallpaper { let id: String; var tags = ["tag"] }
@MainActor final class SILProbe {
    var wallpapers = [SILWallpaper(id: "a"), SILWallpaper(id: "b")]
    var sortedWallpapers: [SILWallpaper] { wallpapers }
    var selectedIDs: Set<String> = ["a"]
    var selectedID: String?
    var isMultiSelectMode = true
    func syncSelectedWallpaperInspectorIfNeeded() {}
    func save() {}
    // SIL_METHODS
}
struct VideoWallpaper { let id: String; var path: String { id } }
struct WallpaperDeletionFailure {}
struct WallpaperDeletionSummary {
    let requestedCount: Int; let removedCount: Int; let failures: [WallpaperDeletionFailure]
    var hasFailures: Bool { !failures.isEmpty }
    var informativeText: String { "fixture" }
}
enum WallpaperRemovalScope { case library, recentlyUsed, favorites, tag(String) }
@MainActor final class VideoProbe {
    struct RemovalRecord { let id: String; var path: String { id } }
    var pendingDeletions: [() -> Void] = []
    var libraryRecords = [VideoWallpaper(id: "a"), VideoWallpaper(id: "b")]
    func enqueueDeletionTask(_ task: @escaping () -> Void) { pendingDeletions.append(task) }
    func removalRecord(for wallpaper: VideoWallpaper) -> RemovalRecord { .init(id: wallpaper.id) }
    func deduplicatedWallpapers(_ items: [VideoWallpaper]) -> [VideoWallpaper] { items }
    func removeDerivedAssets(for record: RemovalRecord) -> [WallpaperDeletionFailure] { [] }
    func applyLibraryRemoval(paths: Set<String>, removedIDs: Set<String>) {
        libraryRecords.removeAll { removedIDs.contains($0.id) }
        clearSelectionAndPendingState(removedIDs)
    }
    func removeRecentlyUsedWallpapers(_ items: [VideoWallpaper]) { clearSelectionState() }
    func removeFavoriteReferences(_ items: [VideoWallpaper]) { clearSelectionState() }
    func removeTagReferences(_ items: [VideoWallpaper], tag: String) { clearSelectionState() }
    var selectedWallpaperId: String?
    var selectedWallpaperIds: Set<String> = ["a", "b"]
    var isMultiSelectMode = true
    // VIDEO_METHODS
}
@MainActor final class SteamWorkshopToolbarController: NSObject {
    let menuPopover = ToolbarMenuPopoverPresenter()
    func configureDownloadsSortItem() {}
    // SORT_ACTION
}
typealias WallpaperManager = VideoProbe
@MainActor struct WallpaperSelectionContext {
    var deletionScope: WallpaperRemovalScope? = .library
    func sourceWallpapers(from manager: WallpaperManager) -> [VideoWallpaper] { manager.libraryRecords }
}
@MainActor enum AlertProbe { static var completion: ((NSApplication.ModalResponse) -> Void)? }
@MainActor func appModalHostWindow() -> NSWindow? { nil }
@MainActor func makeAppAlert(title: String, message: String, style: NSAlert.Style, buttons: [String]) -> NSAlert { NSAlert() }
@MainActor func presentAppAlert(_ alert: NSAlert, in window: NSWindow?,
                              completion: ((NSApplication.ModalResponse) -> Void)? = nil) { AlertProbe.completion = completion }
@MainActor enum UIActionHelper {
    // VIDEO_UI_HELPER
}
final class DimmingSurface: NSView, ToolbarGridScrollDismissalSurface {}

@main struct LibraryToolbarBehaviorHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        let service = SteamWorkshopService.shared
        service.isDownloadsMultiSelectMode = true
        service.selectedDownloadIDs = ["a", "b"]
        service.selectedDownloadID = "a"
        service.deleteSelectedDownload()
        checks["steamBulkCommandCapturesTargetsAndExitsMode"] = service.deleteRequests == [["a", "b"]]
            && !service.isDownloadsMultiSelectMode && service.selectedDownloadIDs.isEmpty && service.selectedDownloadID == nil
        service.isDownloadsMultiSelectMode = true
        service.selectedDownloadIDs = []
        service.deleteSelectedDownload()
        checks["emptyBulkCommandKeepsMode"] = service.isDownloadsMultiSelectMode && service.deleteRequests.count == 1
        service.selectedDownloadIDs = ["a"]; service.removingDownloadIDs = ["a"]
        service.deleteSelectedDownload()
        checks["duplicatePendingDeleteDoesNotExitNewMode"] = service.isDownloadsMultiSelectMode && service.deleteRequests.count == 1
        let online = OnlineProbe()
        online.collectionView.allowsMultipleSelection = true
        online.deleteSelected()
        checks["onlineBulkDeleteExitsModeAndUpdatesNativeSelection"] = !online.isMultiSelectMode
            && !online.collectionView.allowsMultipleSelection && online.selectedIDs.isEmpty && online.reloads == 1
            && OnlineLibraryService.shared.deletedURLs.count == 2
        checks["onlineBulkDeleteTargetsSelectedURLsOnly"] = Set(OnlineLibraryService.shared.deletedURLs)
            == Set([URL(fileURLWithPath: "/fixture/online_1.mp4"), URL(fileURLWithPath: "/fixture/online_2.mp4")])
        let sil = SILProbe(); sil.remove(ids: ["a"])
        checks["staticImageLibraryAlreadyExitsBulkMode"] = !sil.isMultiSelectMode && sil.wallpapers.map(\.id) == ["b"]
        let tag = SILProbe(); tag.removeFromSILTag("tag", ids: ["a"])
        checks["staticImageTagRemovalExitsBulkMode"] = !tag.isMultiSelectMode && tag.selectedIDs.isEmpty
            && tag.wallpapers.count == 2 && tag.wallpapers[0].tags.isEmpty
        let video = VideoProbe()
        video.removeWallpapers([VideoWallpaper(id: "a")], in: .library)
        checks["videoBulkCommandExitsBeforeQueuedCleanup"] = !video.isMultiSelectMode && video.selectedWallpaperIds.isEmpty
        video.isMultiSelectMode = true; video.selectedWallpaperIds = ["b"]
        video.pendingDeletions.forEach { $0() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["oldVideoDeletionPreservesNewMultiSelectSession"] = video.isMultiSelectMode && video.selectedWallpaperIds == ["b"]
        let confirming = VideoProbe()
        confirming.selectedWallpaperIds = ["a"]
        confirming.removeWallpapers([VideoWallpaper(id: "a")], in: .library)
        confirming.isMultiSelectMode = true; confirming.selectedWallpaperIds = ["a"]
        UIActionHelper.performDelete(manager: confirming, selection: WallpaperSelectionContext(), window: nil)
        let confirmation = AlertProbe.completion
        confirming.pendingDeletions.forEach { $0() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        confirmation?(.alertFirstButtonReturn)
        checks["vanishedConfirmationTargetsDoNotExitNewMode"] = confirming.isMultiSelectMode
            && confirming.selectedWallpaperIds.isEmpty && confirming.pendingDeletions.count == 1
        let canceled = VideoProbe()
        UIActionHelper.performDelete(manager: canceled, selection: WallpaperSelectionContext(), window: nil)
        AlertProbe.completion?(.alertSecondButtonReturn)
        checks["cancelingVideoDeleteKeepsSelectionModeAndTargets"] = canceled.isMultiSelectMode
            && canceled.selectedWallpaperIds == ["a", "b"] && canceled.pendingDeletions.isEmpty
        // Both delayed callbacks run production snapshot completion/resolution.
        // An older snapshot cannot consume the newer deletion's index; explicit
        // selection then cancels it even if a later scan completes afterwards.
        let queued = OnlineProbe()
        queued.applySnapshot(ids: [1, 2, 3])
        let thumbnailDemandBeforeCompletion = queued.thumbnailDemandSchedules
        queued.deleteSelected()
        queued.dataSource.release()
        checks["olderOnlineSnapshotCannotConsumeDeletionRestore"] = queued.pendingPostDeletionSelectionIndex != nil
        checks["onlineSnapshotSchedulesThumbnailDemandOnlyAfterCompletion"] = thumbnailDemandBeforeCompletion == 0
            && queued.thumbnailDemandSchedules == 1
        queued.toggleMultiSelect(); queued.orderedIDs = [3, 4]; queued.selectAll()
        queued.applySnapshot(ids: [3, 4])
        DispatchQueue.main.async { queued.dataSource.release() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["oldOnlineDeletionPreservesNewMultiSelectSession"] = queued.isMultiSelectMode && queued.selectedIDs == [3, 4]
        queued.pendingPostDeletionSelectionIndex = 0
        queued.pendingPostDeletionSelectionGeneration = queued.reloadEntriesGeneration
        queued.syncSelectionFromQuickLook(id: 3)
        queued.applySnapshot(ids: [2, 3]); queued.dataSource.release()
        checks["explicitOnlineSelectionCancelsOldRestore"] = queued.selectedIDs == [3]
        let adjacent = OnlineProbe(); adjacent.isMultiSelectMode = false
        adjacent.selectedIDs = [2]; adjacent.selectedAnchorID = 2
        adjacent.deleteSelected(); adjacent.orderedIDs = [1, 3]
        adjacent.applySnapshot(ids: [1, 3]); adjacent.dataSource.release()
        checks["ordinaryOnlineDeletionStillSelectsAdjacentCard"] = adjacent.selectedIDs == [3]
        service.isDownloadsMultiSelectMode = false
        service.downloads = [
            .init(id: "clean", browserItem: .init(tags: ["Everyone"])),
            .init(id: "mature", browserItem: .init(tags: ["Mature"])),
            .init(id: "nudity", browserItem: .init(tags: [" nUdItY "])),
            .init(id: "legacy", browserItem: .init(hasAdultContent: true)),
            .init(id: "local", tags: ["Mature", "Nudity"]),
            .init(id: "near", title: "Mature and Nudity title", browserItem: .init(tags: ["Mature Nature", "NotNudity"])),
            .init(id: "failed", browserItem: .init(tags: ["Nudity"]), status: .failed("fixture")),
            .init(id: "retry", browserItem: .init(tags: ["Mature"]), status: .downloading),
            .init(id: "new-download", status: .queued)]
        checks["adultContentDefaultsToShown"] = service.downloadsShowsAdultContent
            && service.filteredAndSortedDownloads(from: service.downloads).count == 8
        service.selectedDownloadID = "nudity"; service.selectedDownloadIDs = ["nudity"]
        service.downloadsShowsAdultContent = false
        checks["officialAdultAndNudityAreHiddenWithoutGuessingLocalTags"] = Set(service.displayedDownloads.map(\.id)) == ["clean", "local", "near"]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["hiddenAdultSelectionIsSanitized"] = service.selectedDownloadID == nil && service.selectedDownloadIDs.isEmpty
        service.downloadsShowsAdultContent = true
        checks["reenablingRestoresWholeExistingProjection"] = service.displayedDownloads.count == 8

        var publications = 0
        let projectionSubscription = service.$displayedDownloads.dropFirst().sink { _ in publications += 1 }
        service.mergeCalls = 0
        for _ in 0..<20 { service.refreshDisplayedDownloads() }
        checks["unchangedDownloadProjectionPublishesNothingAndMergesOncePerRefresh"] = publications == 0
            && service.mergeCalls == 20
        service.selectedDownloadID = "outside-projection"
        service.selectedDownloadIDs = ["outside-projection"]
        service.refreshDisplayedDownloads()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["unchangedProjectionStillSanitizesSelection"] = publications == 0
            && service.selectedDownloadID == nil && service.selectedDownloadIDs.isEmpty
        service.mergeCalls = 0
        service.downloads[0].title = "Updated metadata"
        checks["metadataChangePublishesProjectionSynchronouslyWithoutSecondMerge"] = publications == 1
            && service.displayedDownloads.contains { $0.title == "Updated metadata" } && service.mergeCalls == 1
        projectionSubscription.cancel()

        let intent = SteamWorkshopService()
        intent.downloadJobStore.jobs = [
            .init(accountSteamId: "A", workshopItemId: "ready", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "failure", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "failure", state: .failed),
            .init(accountSteamId: "B", workshopItemId: "other-account", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "retry", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "new-task", state: .running)]
        var intentPublications = 0
        let intentSubscription = intent.$displayedDownloads.dropFirst().sink { _ in intentPublications += 1 }
        let ready = SteamWorkshopDownloadRecord(id: "ready", title: "Keep ready metadata")
        intent.downloads = [ready]
        checks["newFailedIntentsConvergeInOneDidSetReentryAndOnePublication"] = intent.mergeCalls == 2
            && intentPublications == 1 && intent.downloads.count == 3
            && Set(intent.displayedDownloads.map(\.id)) == ["ready", "failure", "retry"]
        checks["readyMetadataAndDuplicateFailedIntentRemainSingleCards"] = intent.downloads.first { $0.id == "ready" } == ready
            && intent.downloads.filter { $0.id == "failure" }.count == 1
        intent.mergeCalls = 0
        intent.refreshDisplayedDownloads()
        checks["settledFailedIntentRefreshMergesOnceWithoutRepublishing"] = intent.mergeCalls == 1 && intentPublications == 1
        intent.downloadJobStore.history = []
        intent.refreshDisplayedDownloads()
        checks["clearedHistoryHidesActiveRetryButPreservesFailedIntent"] = Set(intent.displayedDownloads.map(\.id))
            == ["ready", "failure"] && intentPublications == 2
        intent.steamAuth.steamId = "B"
        let accountB = intent.filteredAndSortedDownloads(from: [ready])
        checks["projectionSynthesizesOnlyCurrentAccountIntents"] = Set(accountB.map(\.id)) == ["ready", "other-account"]
        intent.steamAuth.steamId = nil
        checks["signedOutProjectionCannotSynthesizeFailedIntents"] = intent.filteredAndSortedDownloads(from: [ready]) == [ready]
        intentSubscription.cancel()

        // Count reads at the real history input; projection and synthesis bodies
        // remain production code. Each measured call gets its own input snapshot.
        var historyReadMetrics: [String: Int] = [:]
        @MainActor func measuredHistory(_ name: String, on probe: SteamWorkshopService,
            _ operation: () -> [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
            let before = probe.downloadJobStore.historyReadCount
            let result = operation()
            historyReadMetrics[name] = probe.downloadJobStore.historyReadCount - before
            return result
        }
        let historyProbe = SteamWorkshopService()
        historyProbe.downloadJobStore.history = [
            .init(accountSteamId: "A", workshopItemId: "retry-one", outcome: .failed),
            .init(accountSteamId: "A", workshopItemId: "retry-one", outcome: .completed),
            .init(accountSteamId: "A", workshopItemId: "retry-two", outcome: .completed),
            .init(accountSteamId: "A", workshopItemId: "retry-two", outcome: .failed),
            .init(accountSteamId: "A", workshopItemId: "retry-two", outcome: .cancelled),
            .init(accountSteamId: "A", workshopItemId: "failed-then-success", outcome: .failed),
            .init(accountSteamId: "A", workshopItemId: "failed-then-success", outcome: .completed),
            .init(accountSteamId: "A", workshopItemId: "shared", outcome: .completed),
            .init(accountSteamId: "B", workshopItemId: "shared", outcome: .failed),
            .init(accountSteamId: "B", workshopItemId: "retry-two", outcome: .completed),
            .init(accountSteamId: "A", workshopItemId: "completed-only", outcome: .completed),
            .init(accountSteamId: "A", workshopItemId: "cancelled-only", outcome: .cancelled)]
        let retryRecords: [SteamWorkshopDownloadRecord] = [
            ready, .init(id: "retry-one", status: .queued),
            .init(id: "retry-two", status: .downloading),
            .init(id: "failed-then-success", status: .queued),
            .init(id: "shared", status: .queued),
            .init(id: "completed-only", status: .downloading),
            .init(id: "cancelled-only", status: .queued),
            .init(id: "failed-card", status: .failed("retained"))]
        let mergedRetries = measuredHistory("mergedManyRetries", on: historyProbe) {
            historyProbe.filteredAndSortedMergedDownloads(from: retryRecords)
        }
        checks["mixedAccountHistoryKeepsOnlyCurrentAccountFailedRetries"] = Set(mergedRetries.map(\.id))
            == ["ready", "retry-one", "retry-two", "failed-then-success", "failed-card"]
        checks["anyFailureSurvivesLaterSuccessOrCancellation"] = mergedRetries.contains { $0.id == "retry-one" }
            && mergedRetries.contains { $0.id == "retry-two" }
            && mergedRetries.contains { $0.id == "failed-then-success" }
        checks["completedAndCancelledHistoryAloneNeverCreateRetryCards"] = !mergedRetries.contains { $0.id == "completed-only" }
            && !mergedRetries.contains { $0.id == "cancelled-only" }
        checks["mergedProjectionReadsHistoryAtMostOnce"] = historyReadMetrics["mergedManyRetries"] == 1

        historyProbe.downloadJobStore.jobs = [
            .init(accountSteamId: "A", workshopItemId: "ready", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "failure", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "failure", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "retry-one", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "retry-one", state: .running),
            .init(accountSteamId: "A", workshopItemId: "retry-two", state: .staged),
            .init(accountSteamId: "A", workshopItemId: "failed-then-success", state: .committing),
            .init(accountSteamId: "A", workshopItemId: "shared", state: .queued),
            .init(accountSteamId: "B", workshopItemId: "other-account", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "completed-only", state: .running),
            .init(accountSteamId: "A", workshopItemId: "cancelled-only", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "new-task", state: .running),
            .init(accountSteamId: "A", workshopItemId: "terminal-cancelled", state: .cancelled),
            .init(accountSteamId: "A", workshopItemId: "terminal-completed", state: .completed)]
        let synthesizedRetries = measuredHistory("synthesisManyRetries", on: historyProbe) {
            historyProbe.downloadsWithFailedIntents(from: [ready])
        }
        checks["synthesisPreservesReadyAndDeduplicatesMixedRetryJobs"] = synthesizedRetries.count == 5
            && Set(synthesizedRetries.map(\.id)) == ["ready", "failure", "retry-one", "retry-two", "failed-then-success"]
            && synthesizedRetries.first { $0.id == "ready" } == ready
            && synthesizedRetries.first { $0.id == "retry-one" }?.status == .queued
            && synthesizedRetries.first { $0.id == "retry-two" }?.status == .downloading
            && synthesizedRetries.first { $0.id == "failed-then-success" }?.status == .downloading
        checks["intentSynthesisReadsHistoryAtMostOnce"] = historyReadMetrics["synthesisManyRetries"] == 1

        let retryMissProbe = SteamWorkshopService()
        retryMissProbe.downloadJobStore.jobs = [
            .init(accountSteamId: "A", workshopItemId: "miss-one", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "miss-two", state: .running),
            .init(accountSteamId: "A", workshopItemId: "miss-three", state: .staged)]
        let retryMissRecords: [SteamWorkshopDownloadRecord] = [
            .init(id: "miss-one", status: .queued),
            .init(id: "miss-two", status: .downloading),
            .init(id: "miss-three", status: .downloading)]
        let missHistories: [(String, [IntentHistory])] = [
            ("emptyHistoryManyRetries", []),
            ("foreignOnlyHistoryManyRetries", [
                .init(accountSteamId: "B", workshopItemId: "miss-one", outcome: .failed),
                .init(accountSteamId: "B", workshopItemId: "miss-two", outcome: .failed),
                .init(accountSteamId: "B", workshopItemId: "miss-three", outcome: .failed)])]
        var emptyHistoryMergeBehavior = true, emptyHistorySynthesisBehavior = true
        for (label, history) in missHistories {
            retryMissProbe.downloadJobStore.history = history
            let projected = measuredHistory(label + "Merged", on: retryMissProbe) {
                retryMissProbe.filteredAndSortedMergedDownloads(from: retryMissRecords)
            }
            let synthesized = measuredHistory(label + "Synthesis", on: retryMissProbe) {
                retryMissProbe.downloadsWithFailedIntents(from: [])
            }
            emptyHistoryMergeBehavior = emptyHistoryMergeBehavior && projected.isEmpty
            emptyHistorySynthesisBehavior = emptyHistorySynthesisBehavior && synthesized.isEmpty
        }
        checks["emptyOrForeignOnlyHistoryKeepsAllMergedRetriesHidden"] = emptyHistoryMergeBehavior
        checks["emptyOrForeignOnlyHistorySynthesizesNoRetryCards"] = emptyHistorySynthesisBehavior
        checks["emptyOrForeignOnlyMergedHistoryReadsOnce"] = ["emptyHistoryManyRetriesMerged",
            "foreignOnlyHistoryManyRetriesMerged"].allSatisfy { historyReadMetrics[$0] == 1 }
        checks["emptyOrForeignOnlySynthesisHistoryReadsOnce"] = ["emptyHistoryManyRetriesSynthesis",
            "foreignOnlyHistoryManyRetriesSynthesis"].allSatisfy { historyReadMetrics[$0] == 1 }

        let noRetryProbe = SteamWorkshopService()
        let settledRecords: [SteamWorkshopDownloadRecord] = [ready, .init(id: "failed-card", status: .failed("retained"))]
        let settled = measuredHistory("mergedNoEligibleRetry", on: noRetryProbe) {
            noRetryProbe.filteredAndSortedMergedDownloads(from: settledRecords)
        }
        noRetryProbe.downloadsDisplayMode = .web
        let modeFiltered = measuredHistory("mergedModeFilteredRetries", on: noRetryProbe) {
            noRetryProbe.filteredAndSortedMergedDownloads(from: retryRecords)
        }
        noRetryProbe.downloadsDisplayMode = .all
        noRetryProbe.downloadsShowsAdultContent = false
        let adultFiltered = measuredHistory("mergedAdultFilteredRetry", on: noRetryProbe) {
            noRetryProbe.filteredAndSortedMergedDownloads(from: [
                .init(id: "retry", browserItem: .init(tags: ["Mature"]), status: .queued)])
        }
        noRetryProbe.downloadJobStore.jobs = [
            .init(accountSteamId: "A", workshopItemId: "ready", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "failure", state: .failed),
            .init(accountSteamId: "B", workshopItemId: "foreign-retry", state: .queued),
            .init(accountSteamId: "A", workshopItemId: "terminal", state: .completed)]
        let noEligibleSynthesis = measuredHistory("synthesisNoEligibleRetry", on: noRetryProbe) {
            noRetryProbe.downloadsWithFailedIntents(from: [ready])
        }
        checks["nonRetryAndFilteredPathsKeepTheirExistingOutputs"] = Set(settled.map(\.id)) == ["ready", "failed-card"]
            && modeFiltered.isEmpty && adultFiltered.isEmpty
            && Set(noEligibleSynthesis.map(\.id)) == ["ready", "failure"]
        checks["noEligibleRetryPathsNeverReadHistory"] = ["mergedNoEligibleRetry", "mergedModeFilteredRetries",
            "mergedAdultFilteredRetry", "synthesisNoEligibleRetry"].allSatisfy { historyReadMetrics[$0] == 0 }

        let mutableHistory = SteamWorkshopService()
        mutableHistory.downloadJobStore.history = []
        let sharedRetry = SteamWorkshopDownloadRecord(id: "shared", status: .queued)
        mutableHistory.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "shared", state: .queued),
            .init(accountSteamId: "B", workshopItemId: "shared", state: .queued)]
        func currentRetries(_ name: String) -> (projection: [SteamWorkshopDownloadRecord], synthesis: [SteamWorkshopDownloadRecord]) {
            let projected = measuredHistory(name, on: mutableHistory) {
                mutableHistory.filteredAndSortedMergedDownloads(from: [sharedRetry])
            }
            let synthesized = measuredHistory(name + "Synthesis", on: mutableHistory) {
                mutableHistory.downloadsWithFailedIntents(from: [])
            }
            return (projected, synthesized)
        }
        let beforeAdd = currentRetries("emptyHistory")
        mutableHistory.downloadJobStore.history = [.init(accountSteamId: "A", workshopItemId: "shared", outcome: .failed)]
        let afterAdd = currentRetries("addedHistory")
        mutableHistory.steamAuth.steamId = "B"
        let afterAccountChange = currentRetries("changedAccount")
        mutableHistory.downloadJobStore.history = [.init(accountSteamId: "B", workshopItemId: "shared", outcome: .failed)]
        let afterAccountHistoryAdd = currentRetries("changedAccountAddedHistory")
        mutableHistory.downloadJobStore.history = []
        let afterClear = currentRetries("clearedHistory")
        checks["historyAddClearAndAccountChangeAffectTheNextProjection"] = beforeAdd.projection.isEmpty
            && afterAdd.projection == [sharedRetry] && afterAccountChange.projection.isEmpty
            && afterAccountHistoryAdd.projection == [sharedRetry] && afterClear.projection.isEmpty
        checks["historyAddClearAndAccountChangeAffectTheNextSynthesis"] = beforeAdd.synthesis.isEmpty
            && afterAdd.synthesis.map(\.id) == ["shared"] && afterAccountChange.synthesis.isEmpty
            && afterAccountHistoryAdd.synthesis.map(\.id) == ["shared"] && afterClear.synthesis.isEmpty
        mutableHistory.downloadJobStore.history = [.init(accountSteamId: "A", workshopItemId: "shared", outcome: .failed)]
        var noAccountBehavior = true
        for (label, account) in [("nilAccount", Optional<String>.none), ("emptyAccount", Optional(""))] {
            mutableHistory.steamAuth.steamId = account
            let projected = measuredHistory(label + "Merged", on: mutableHistory) {
                mutableHistory.filteredAndSortedMergedDownloads(from: retryRecords)
            }
            mutableHistory.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "shared", state: .queued)]
            let synthesized = measuredHistory(label + "Synthesis", on: mutableHistory) {
                mutableHistory.downloadsWithFailedIntents(from: [ready])
            }
            noAccountBehavior = noAccountBehavior && Set(projected.map(\.id)) == ["ready", "failed-card"]
                && synthesized == [ready]
        }
        checks["nilAndEmptyAccountsKeepReadyAndFailureWithoutRetrySynthesis"] = noAccountBehavior
        checks["nilAndEmptyAccountPathsNeverReadHistory"] = ["nilAccountMerged", "nilAccountSynthesis",
            "emptyAccountMerged", "emptyAccountSynthesis"].allSatisfy { historyReadMetrics[$0] == 0 }

        let previousDownloads = service.downloads
        func sortable(_ id: String, _ title: String, _ date: TimeInterval, _ bytes: Int64) -> SteamWorkshopDownloadRecord {
            var record = SteamWorkshopDownloadRecord(id: id, title: title)
            record.createdAt = Date(timeIntervalSince1970: date)
            record.sizeBytes = bytes; record.sizeText = "same rounded size"
            return record
        }
        let a = sortable("a", "Alpha", 20, 1_000_002)
        var z = sortable("z", "zebra", 10, 1_000_001)
        var folded = sortable("b", "álpha", 20, 1_000_002)
        folded.updatedAt = Date(timeIntervalSince1970: 9000)
        let unknown = SteamWorkshopDownloadRecord(id: "unknown", title: "zz unknown", sizeText: "9999GB")
        service.downloads = [z, unknown, folded, a]
        service.downloadsSortMode = .createdAt; service.downloadsSortAscending = false
        let beforeModification = service.filteredAndSortedDownloads(from: service.downloads).map(\.id)
        z.updatedAt = Date(timeIntervalSince1970: 99999)
        service.downloads[0] = z
        checks["creationSortDoesNotUseModificationDate"] = beforeModification == ["b", "a", "z", "unknown"]
            && service.filteredAndSortedDownloads(from: service.downloads).map(\.id) == beforeModification
        service.downloadsSortMode = .title; service.downloadsSortAscending = true
        let alphabetical = service.filteredAndSortedDownloads(from: service.downloads).map(\.id)
        service.downloadsSortAscending = false
        checks["titleSortIsAZWithExactReverse"] = alphabetical == ["a", "b", "z", "unknown"]
            && service.filteredAndSortedDownloads(from: service.downloads).map(\.id) == alphabetical.reversed()
        service.downloadsSortMode = .size; service.downloadsSortAscending = true
        let sizeAscending = service.filteredAndSortedDownloads(from: service.downloads).map(\.id)
        service.downloadsSortAscending = false
        checks["sizeSortUsesExactBytesInsteadOfFormattedText"] = sizeAscending == ["z", "a", "b", "unknown"]
            && service.filteredAndSortedDownloads(from: service.downloads).map(\.id) == ["b", "a", "z", "unknown"]
        service.downloads = [sortable("3", "Work 10", 1, 1), sortable("2", "work 2", 1, 1),
            sortable("01", "Same", 1, 1), sortable("1", "same", 1, 1)]
        service.downloadsSortMode = .title; service.downloadsSortAscending = true
        let numericOrder = service.filteredAndSortedDownloads(from: service.downloads).map(\.id)
        service.downloadsSortAscending = false
        checks["numericTitlesAndEqualTitlesHaveDeterministicReverse"] = numericOrder == ["01", "1", "2", "3"]
            && service.filteredAndSortedDownloads(from: service.downloads).map(\.id) == numericOrder.reversed()
        service.downloads = previousDownloads
        service.downloadsSortMode = .createdAt; service.downloadsSortAscending = false

        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 640, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        window.contentView = root
        let anchor = NSButton(frame: NSRect(x: 20, y: 340, width: 80, height: 30))
        root.addSubview(anchor)
        let gridScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let grid = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        gridScroll.documentView = grid; root.addSubview(gridScroll)
        let card = NSButton(frame: NSRect(x: 20, y: 20, width: 100, height: 100)); grid.addSubview(card)
        let inspectorScroll = NSScrollView(frame: NSRect(x: 420, y: 0, width: 200, height: 300))
        inspectorScroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
        let dimming = DimmingSurface(frame: root.bounds)
        dimming.addSubview(inspectorScroll)
        let popover = NSPopover(); popover.animates = false
        let panel = NSViewController(); panel.view = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
        popover.contentViewController = panel
        let dismissal = ToolbarPopoverScrollDismissal(popover: popover)
        window.orderFrontRegardless()
        func show() {
            dismissal.watch(relativeTo: anchor)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
        show()
        dismissal.dismissIfGridScroll(in: window, target: inspectorScroll.documentView)
        checks["inspectorScrollingKeepsToolbarPanelOpen"] = popover.isShown
        dismissal.dismissIfGridScroll(in: panel.view.window, target: grid)
        checks["differentWindowCannotDismissToolbarPanel"] = popover.isShown
        dismissal.dismissIfGridScroll(in: window, target: card)
        checks["gridCardScrollingClosesToolbarPanel"] = !popover.isShown
        show(); dismissal.dismissIfGridScroll(in: window, target: gridScroll)
        checks["gridScrollbarScrollingClosesToolbarPanel"] = !popover.isShown
        show(); dismissal.dismissIfGridScroll(in: window, target: dimming)
        checks["gridDimmingOverlayScrollingClosesToolbarPanel"] = !popover.isShown
        show(); dismissal.dismissIfGridScroll(in: window, target: inspectorScroll.documentView)
        checks["inspectorChildInsideOverlayDoesNotCountAsGrid"] = popover.isShown
        popover.performClose(nil)
        dismissal.dismissIfGridScroll(in: window, target: grid)
        checks["closedPanelCanBeReopenedAndClosedAgain"] = !popover.isShown

        let toolbar = SteamWorkshopToolbarController()
        toolbar.handleDownloadsSortAction(anchor)
        func allButtons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(allButtons)
        }
        let buttons = NSApp.windows.filter { $0 !== window && $0.isVisible }
            .compactMap(\.contentView).flatMap(allButtons)
        let adult = buttons.first { $0.title == "成人内容" }
        checks["adultOptionIsLastSortMenuRow"] = adult != nil && buttons.last === adult
        checks["sortMenuUsesRequestedLabelsAndOneCurrentDirection"] = buttons.map(\.title) == ["创建时间", "作品名称", "文件大小", "降序", "成人内容"]
        adult?.performClick(nil)
        checks["adultMenuCheckboxRunsLiveProjectionAndStaysOpen"] = !service.downloadsShowsAdultContent
            && service.displayedDownloads.count == 3 && toolbar.menuPopover.isShown
        func menuButtons() -> [NSButton] {
            NSApp.windows.filter { $0 !== window && $0.isVisible }.compactMap(\.contentView).flatMap(allButtons)
        }
        menuButtons().first { $0.title == "作品名称" }?.performClick(nil)
        checks["selectingTitleStartsWithAZ"] = service.downloadsSortMode == .title && service.downloadsSortAscending
            && menuButtons().filter { $0.title == "升序" || $0.title == "降序" }.map(\.title) == ["升序"]
        menuButtons().first { $0.title == "升序" }?.performClick(nil)
        checks["oneDirectionRowTogglesAndDisplaysCurrentOrder"] = !service.downloadsSortAscending
            && menuButtons().filter { $0.title == "升序" || $0.title == "降序" }.map(\.title) == ["降序"]
        menuButtons().first { $0.title == "作品名称" }?.performClick(nil)
        checks["selectingCurrentModeKeepsDirection"] = !service.downloadsSortAscending
        menuButtons().first { $0.title == "文件大小" }?.performClick(nil)
        checks["selectingSizeDefaultsToLargestFirst"] = service.downloadsSortMode == .size && !service.downloadsSortAscending
        menuButtons().first { $0.title == "降序" }?.performClick(nil)
        menuButtons().first { $0.title == "创建时间" }?.performClick(nil)
        checks["selectingCreationDefaultsToNewestFirst"] = service.downloadsSortMode == .createdAt && !service.downloadsSortAscending
        if let directory = ProcessInfo.processInfo.environment["MWX_LIBRARY_TOOLBAR_PROOF_DIR"],
           let panel = menuButtons().first?.window?.contentView {
            panel.layoutSubtreeIfNeeded()
            if let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) {
                panel.cacheDisplay(in: panel.bounds, to: bitmap)
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("download-sort-menu.png"))
            }
        }
        toolbar.menuPopover.close()
        window.close()
        let historyMetricsData = try JSONSerialization.data(withJSONObject: ["historyReads": historyReadMetrics], options: [.sortedKeys])
        FileHandle.standardError.write(historyMetricsData + Data("\n".utf8))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
