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
    enum DependencyStatus { case none }
    let id: String
    var title = "Wallpaper"
    var description = ""
    var tags: [String] = []
    var folderURL = URL(fileURLWithPath: "/private/tmp/source-facts")
    var projectFileURL: URL? = nil
    var ownEntryHTMLURL: URL? = nil
    var dependencyHostEntryHTMLURL: URL? = nil
    var dependencyHostFolderURL: URL? = nil
    var entryHTMLURL: URL? = nil
    var resolvedWebRootURL: URL? = nil
    var previewURL: URL? = nil
    var sourceVideoURL: URL? = nil
    var exportedVideoURL: URL? = nil
    var updatedAt = Date(timeIntervalSince1970: 1)
    var sizeText = "10"
    var status = Status.ready
    var browserItem: BrowserMetadata?
    var contentType = ContentType.video
    var dependencyItemID: String? = nil
    var dependencyStatus = DependencyStatus.none
    var createdAt: Date? = nil
    var sizeBytes: Int64? = nil
    var intentAccountSteamID: String? = nil
}
enum SteamDownloadJobState { case failed, queued, running, staged, committing, cancelled, completed }
struct SteamDownloadJob {
    let accountSteamId: String
    let workshopItemId: String
    var state: SteamDownloadJobState
}
struct IntentHistory: Equatable {
    enum Outcome { case failed, completed, cancelled }
    let accountSteamId: String
    let workshopItemId: String
    let outcome: Outcome
}
final class IntentStore {
    @Published var jobs: [SteamDownloadJob] = []
    @Published var history = [IntentHistory(accountSteamId: "A", workshopItemId: "retry", outcome: .failed)]
    private(set) var historyReadCount = 0
    var historyForProjection: [IntentHistory] { historyReadCount += 1; return history }
}
final class IntentAuth { @Published var steamId: String? = "A" }
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    // DOWNLOADS_PROPERTY
    var mergeCalls = 0
    let downloadJobStore = IntentStore()
    let steamAuth = IntentAuth()
    let libraryRootURL = URL(fileURLWithPath: "/private/tmp/source-facts")
    var requestedBrowserItems: [String: BrowserMetadata] = [:]
    func browserItemForDownload(id: String) -> BrowserMetadata? { requestedBrowserItems[id] }
    var cancellables: Set<AnyCancellable> = []
    func observeProjectionInputs() { observeDownloadJobStoreForProjection() }
    func visibleRecords(_ records: [SteamWorkshopDownloadRecord], account: String? = "A") -> [SteamWorkshopDownloadRecord] {
        let excluded = excludedDownloadReferences(in: records,
            showsAdultContent: downloadsShowsAdultContent, accountSteamID: account)
        return records.filter { !excluded.contains(.init(provider: .steamWorkshop, sourceID: $0.id)) }
    }
    // Record-construction leaves adapt the real intent projection to the small
    // value model above; account/history/dedup and publication bodies are real.
    func synthesizedFailedIntentRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        .init(id: job.workshopItemId, status: .failed("fixture"), contentType: .unknown, intentAccountSteamID: job.accountSteamId)
    }
    func synthesizedActiveRetryRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        .init(id: job.workshopItemId, status: job.state == .queued ? .queued : .downloading, contentType: .unknown, intentAccountSteamID: job.accountSteamId)
    }
    // STEAM_METHODS
}
final class DimmingSurface: NSView, ToolbarGridScrollDismissalSurface {}

@main struct LibraryToolbarBehaviorHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        let service = SteamWorkshopService.shared
        service.downloads = [
            .init(id: "clean", browserItem: .init(tags: ["Everyone"])),
            .init(id: "mature", browserItem: .init(tags: ["Mature"])),
            .init(id: "nudity", browserItem: .init(tags: [" nUdItY "])),
            .init(id: "legacy", browserItem: .init(hasAdultContent: true)),
            .init(id: "local", tags: ["Mature", "Nudity"]),
            .init(id: "near", title: "Mature and Nudity title", browserItem: .init(tags: ["Mature Nature", "NotNudity"])),
            .init(id: "failed", status: .failed("fixture"), browserItem: .init(tags: ["Nudity"])),
            .init(id: "retry", status: .downloading, browserItem: .init(tags: ["Mature"])),
            .init(id: "new-download", status: .queued)]
        checks["adultContentDefaultsToShown"] = service.downloadsShowsAdultContent
            && service.visibleRecords(service.downloads).count == 8
        service.downloadsShowsAdultContent = false
        checks["officialAdultAndNudityAreHiddenWithoutGuessingLocalTags"] = Set(service.visibleRecords(service.downloads).map(\.id)) == ["clean", "local", "near"]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        service.downloadsShowsAdultContent = true
        checks["reenablingRestoresWholeExistingProjection"] = service.visibleRecords(service.downloads).count == 8

        var publications = 0
        let projectionSubscription = service.$downloads.dropFirst().sink { _ in publications += 1 }
        service.mergeCalls = 0
        for _ in 0..<20 { service.refreshDownloadIntentProjection() }
        checks["unchangedDownloadProjectionPublishesNothingAndMergesOncePerRefresh"] = publications == 0
            && service.mergeCalls == 20
        service.mergeCalls = 0
        service.downloads[0].title = "Updated metadata"
        checks["metadataChangePublishesSourceSynchronouslyWithoutSecondMerge"] = publications == 1
            && service.downloads.contains { $0.title == "Updated metadata" } && service.mergeCalls == 1
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
        let intentSubscription = intent.$downloads.dropFirst().sink { _ in intentPublications += 1 }
        let ready = SteamWorkshopDownloadRecord(id: "ready", title: "Keep ready metadata")
        intent.downloads = [ready]
        checks["newFailedIntentsConvergeInOneDidSetReentryAndSourcePublications"] = intent.mergeCalls == 2
            && intentPublications == 2 && intent.downloads.count == 3
            && Set(intent.visibleRecords(intent.downloads).map(\.id)) == ["ready", "failure", "retry"]
        checks["readyMetadataAndDuplicateFailedIntentRemainSingleCards"] = intent.downloads.first { $0.id == "ready" } == ready
            && intent.downloads.filter { $0.id == "failure" }.count == 1
        intent.mergeCalls = 0
        intent.refreshDownloadIntentProjection()
        checks["settledFailedIntentRefreshMergesOnceWithoutRepublishing"] = intent.mergeCalls == 1 && intentPublications == 2
        intent.downloadJobStore.history = []
        intent.refreshDownloadIntentProjection()
        checks["clearedHistoryHidesActiveRetryButPreservesFailedIntent"] = Set(intent.visibleRecords(intent.downloads).map(\.id))
            == ["ready", "failure"] && intentPublications == 2
        intent.steamAuth.steamId = "B"
        let accountB = intent.visibleRecords(intent.downloadsWithFailedIntents(from: [ready]), account: intent.steamAuth.steamId)
        checks["projectionSynthesizesOnlyCurrentAccountIntents"] = Set(accountB.map(\.id)) == ["ready", "other-account"]
        intent.steamAuth.steamId = nil
        checks["signedOutProjectionCannotSynthesizeFailedIntents"] = intent.visibleRecords(intent.downloadsWithFailedIntents(from: [ready]), account: intent.steamAuth.steamId) == [ready]
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
            historyProbe.visibleRecords(retryRecords)
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
                retryMissProbe.visibleRecords(retryMissRecords)
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
            noRetryProbe.visibleRecords(settledRecords)
        }
        noRetryProbe.downloadsShowsAdultContent = false
        let adultFiltered = measuredHistory("mergedAdultFilteredRetry", on: noRetryProbe) {
            noRetryProbe.visibleRecords([
                .init(id: "retry", status: .queued, browserItem: .init(tags: ["Mature"]))])
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
            && adultFiltered.isEmpty
            && Set(noEligibleSynthesis.map(\.id)) == ["ready", "failure"]
        checks["noEligibleRetryPathsNeverReadHistory"] = ["mergedNoEligibleRetry",
            "mergedAdultFilteredRetry", "synthesisNoEligibleRetry"].allSatisfy { historyReadMetrics[$0] == 0 }

        let mutableHistory = SteamWorkshopService()
        mutableHistory.downloadJobStore.history = []
        let sharedRetry = SteamWorkshopDownloadRecord(id: "shared", status: .queued)
        mutableHistory.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "shared", state: .queued),
            .init(accountSteamId: "B", workshopItemId: "shared", state: .queued)]
        func currentRetries(_ name: String) -> (projection: [SteamWorkshopDownloadRecord], synthesis: [SteamWorkshopDownloadRecord]) {
            let projected = measuredHistory(name, on: mutableHistory) {
                mutableHistory.visibleRecords([sharedRetry], account: mutableHistory.steamAuth.steamId)
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
                mutableHistory.visibleRecords(retryRecords, account: account)
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

        let historyEvents = SteamWorkshopService()
        historyEvents.downloadJobStore.history = []
        historyEvents.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "first", state: .queued)]
        historyEvents.observeProjectionInputs()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["initialQueueStaysPopoverOnlyBeforeAnyFailure"] = historyEvents.downloads.isEmpty
        var historyPublications = 0
        let historySub = historyEvents.$downloads.dropFirst().sink { _ in historyPublications += 1 }
        historyEvents.downloadJobStore.history = [.init(accountSteamId: "A", workshopItemId: "first", outcome: .failed)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["historyOnlyPublicationSynthesizesRetryFromTheOriginalOwner"] = historyEvents.downloads.map(\.id) == ["first"]
            && historyEvents.visibleRecords(historyEvents.downloads).map(\.id) == ["first"] && historyPublications == 1
        historyEvents.downloadJobStore.history = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["clearingPublishedHistoryHidesRetryWithoutDroppingAdmittedSourceFacts"] = historyEvents.downloads.map(\.id) == ["first"]
            && historyEvents.visibleRecords(historyEvents.downloads).isEmpty
            && historyEvents.downloadJobStore.jobs.count == 1 && historyEvents.downloadJobStore.jobs[0].state == .queued
            && historyPublications == 1
        historyEvents.downloadJobStore.history = [.init(accountSteamId: "B", workshopItemId: "first", outcome: .failed)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        checks["foreignPublishedHistoryCannotMakeCurrentAccountRetryVisible"] = historyEvents.visibleRecords(historyEvents.downloads).isEmpty
            && historyPublications == 1
        historySub.cancel()

        let accountInput = SteamWorkshopService()
        accountInput.downloadJobStore.history = [.init(accountSteamId: "A", workshopItemId: "shared", outcome: .failed)]
        let accountRows: [SteamWorkshopDownloadRecord] = [.init(id: "shared", status: .queued), ready]
        var observedOldGetter = false, nextAccountExcluded = false, signedOutExcluded = false
        let accountSub = accountInput.steamAuth.$steamId.dropFirst().sink { account in
            let exclusions = accountInput.excludedDownloadReferences(in: accountRows,
                showsAdultContent: true, accountSteamID: account)
            if account == "B" {
                observedOldGetter = accountInput.steamAuth.steamId == "A"
                nextAccountExcluded = exclusions == [.init(provider: .steamWorkshop, sourceID: "shared")]
            } else if account == nil {
                signedOutExcluded = exclusions == [.init(provider: .steamWorkshop, sourceID: "shared")]
            }
        }
        accountInput.steamAuth.steamId = "B"
        let beforeSignedOutReadCount = accountInput.downloadJobStore.historyReadCount
        accountInput.steamAuth.steamId = nil
        checks["publishedNextAccountOverridesPreviousGetterDuringWillSet"] = observedOldGetter && nextAccountExcluded
        checks["publishedSignedOutAccountNeverBorrowsPreviousIdentityOrHistory"] = signedOutExcluded
            && accountInput.downloadJobStore.historyReadCount == beforeSignedOutReadCount
        accountSub.cancel()

        let accountSwitch = SteamWorkshopService()
        let publishedRow = SteamWorkshopDownloadRecord(id: "published", title: "Shared local output")
        let legacyFailure = SteamWorkshopDownloadRecord(id: "legacy-failure", status: .failed("source parse failure"))
        accountSwitch.downloadJobStore.jobs = [
            .init(accountSteamId: "A", workshopItemId: "A-only", state: .failed),
            .init(accountSteamId: "B", workshopItemId: "B-only", state: .failed),
            .init(accountSteamId: "A", workshopItemId: "published", state: .failed),
            .init(accountSteamId: "B", workshopItemId: "published", state: .failed)]
        accountSwitch.downloads = [publishedRow, legacyFailure]
        let accountAInstalled = accountSwitch.downloads
        checks["accountARefreshInstallsExplicitlyTaggedIntentBesideUntouchedPublishedRows"] = Set(accountAInstalled.map(\.id))
            == ["published", "legacy-failure", "A-only"]
            && accountAInstalled.first { $0.id == "A-only" }?.intentAccountSteamID == "A"
            && accountAInstalled.first { $0.id == "published" } == publishedRow
        let transientBExclusions = accountSwitch.excludedDownloadReferences(in: accountAInstalled,
            showsAdultContent: true, accountSteamID: "B")
        checks["nextAccountExcludesOldDerivedFailureBeforeDeferredRefresh"] = transientBExclusions
            == [.init(provider: .steamWorkshop, sourceID: "A-only")]
        accountSwitch.steamAuth.steamId = "B"
        accountSwitch.refreshDownloadIntentProjection()
        checks["accountBRefreshReplacesOldDerivedRowsUsingTheSameInstalledInput"] = Set(accountSwitch.downloads.map(\.id))
            == ["published", "legacy-failure", "B-only"]
            && accountSwitch.downloads.first { $0.id == "B-only" }?.intentAccountSteamID == "B"
            && accountSwitch.downloads.first { $0.id == "published" } == publishedRow
        accountSwitch.steamAuth.steamId = nil
        accountSwitch.refreshDownloadIntentProjection()
        checks["logoutRetractsOnlyTaggedIntentAndPreservesPublishedAndRealFailure"] = accountSwitch.downloads == [publishedRow, legacyFailure]
        accountSwitch.steamAuth.steamId = "B"
        accountSwitch.refreshDownloadIntentProjection()
        accountSwitch.downloadJobStore.jobs = []
        accountSwitch.refreshDownloadIntentProjection()
        checks["removedJobRetractsItsDerivedFailureWithoutDeletingSourceRows"] = accountSwitch.downloads == [publishedRow, legacyFailure]
        accountSwitch.steamAuth.steamId = "A"
        accountSwitch.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "becomes-published", state: .failed)]
        accountSwitch.refreshDownloadIntentProjection()
        let realReplacement = SteamWorkshopDownloadRecord(id: "becomes-published", title: "Now locally published")
        accountSwitch.downloads = [realReplacement, publishedRow, legacyFailure]
        accountSwitch.steamAuth.steamId = "B"
        accountSwitch.refreshDownloadIntentProjection()
        checks["sameIDPublishedReplacementIsNeverRetractedAsOldIntent"] = accountSwitch.downloads
            == [realReplacement, publishedRow, legacyFailure] && realReplacement.intentAccountSteamID == nil

        let transient = SteamWorkshopService()
        transient.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "live", state: .running)]
        let browserMetadata = BrowserMetadata(author: "Actual transient author", tags: ["Scenic"])
        transient.requestedBrowserItems["live"] = browserMetadata
        transient.upsertTransientRecord(id: "live", title: "Downloading", status: .downloading,
            accountSteamID: "A", sizeText: "37%")
        let startedRow = transient.downloads.first { $0.id == "live" }
        checks["actualTransientAdmissionCarriesAccountAndRetainsItsBrowserMetadata"] = startedRow?.intentAccountSteamID == "A"
            && startedRow?.browserItem == browserMetadata && startedRow?.sizeText == "37%" && startedRow?.status == .downloading
        var richRow = startedRow!
        richRow.previewURL = URL(fileURLWithPath: "/private/tmp/source-facts/preview.jpg")
        richRow.sourceVideoURL = URL(fileURLWithPath: "/private/tmp/source-facts/source.mp4")
        richRow.projectFileURL = URL(fileURLWithPath: "/private/tmp/source-facts/project.json")
        richRow.createdAt = Date(timeIntervalSince1970: 25); richRow.sizeBytes = 987654
        transient.downloads = [richRow]
        transient.downloadJobStore.jobs = [.init(accountSteamId: "A", workshopItemId: "live", state: .failed)]
        transient.upsertTransientRecord(id: "live", title: "replacement", status: .failed("network failure"),
            accountSteamID: "A", sizeText: "Failed at 37%")
        let failedRow = transient.downloads.first { $0.id == "live" }
        checks["actualTransientFailureKeepsAccountResourcesAndSourceMetadata"] = failedRow?.intentAccountSteamID == "A"
            && failedRow?.browserItem == richRow.browserItem && failedRow?.previewURL == richRow.previewURL
            && failedRow?.sourceVideoURL == richRow.sourceVideoURL && failedRow?.projectFileURL == richRow.projectFileURL
            && failedRow?.createdAt == richRow.createdAt && failedRow?.sizeBytes == richRow.sizeBytes
            && failedRow?.sizeText == "Failed at 37%" && failedRow?.status == .failed("network failure")
        transient.steamAuth.steamId = "B"
        transient.refreshDownloadIntentProjection()
        checks["switchAccountRetractsActualTransientFailureBeforeAnyLibraryReload"] = transient.downloads.isEmpty
        transient.downloadJobStore.jobs = [.init(accountSteamId: "B", workshopItemId: "live", state: .running)]
        transient.upsertTransientRecord(id: "live", title: "B download", status: .downloading, accountSteamID: "B", sizeText: "8%")
        transient.downloadJobStore.jobs = [.init(accountSteamId: "B", workshopItemId: "live", state: .cancelled)]
        transient.refreshDownloadIntentProjection()
        checks["cancelledJobCannotKeepAnAdmittedTransientRowAlive"] = transient.downloads.isEmpty
        transient.downloads = [publishedRow]
        transient.upsertTransientRecord(id: publishedRow.id, title: "Must not replace local output", status: .failed("update failure"),
            accountSteamID: "A", sizeText: "bad")
        checks["actualTransientProducerNeverOverwritesARealReadyRow"] = transient.downloads == [publishedRow]

        var queryState = WallpaperLibraryQueryState()
        func sortedIDs() throws -> [String] {
            let items = service.downloads.map { record in
                let reference = WallpaperReference(provider: .steamWorkshop, sourceID: record.id)
                return WallpaperContentItem(reference: reference, providerReference: reference,
                    locator: .init(), title: record.title, kind: .video,
                    publishedAvailability: .available, capabilities: [.inspect, .play, .organize],
                    metadata: .init(fileSizeBytes: record.sizeBytes, createdAt: record.createdAt,
                                    modifiedAt: record.updatedAt), acquisition: .idle, update: .idle, aliases: [])
            }
            let relationships = UserCollectionsSnapshot(revision: 1, resetEpoch: UUID(), migrationManifestID: "fixture",
                playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
            return try WallpaperLibraryQuery.project(page: .downloads, state: queryState,
                catalog: .init(downloads: items), relationships: relationships).items.map { $0.reference.sourceID }
        }
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
        queryState = .init(sort: .createdAt, ascending: false)
        let beforeModification = try sortedIDs()
        z.updatedAt = Date(timeIntervalSince1970: 99999)
        service.downloads[0] = z
        checks["creationSortDoesNotUseModificationDate"] = try beforeModification == ["b", "a", "z", "unknown"]
            && (try sortedIDs()) == beforeModification
        queryState = .init(sort: .name, ascending: true)
        let alphabetical = try sortedIDs()
        queryState.ascending = false
        checks["titleSortIsAZWithExactReverse"] = try alphabetical == ["a", "b", "z", "unknown"]
            && (try sortedIDs()) == alphabetical.reversed()
        queryState = .init(sort: .fileSize, ascending: true)
        let sizeAscending = try sortedIDs()
        queryState.ascending = false
        checks["sizeSortUsesExactBytesInsteadOfFormattedText"] = try sizeAscending == ["z", "a", "b", "unknown"]
            && (try sortedIDs()) == ["b", "a", "z", "unknown"]
        service.downloads = [sortable("3", "Work 10", 1, 1), sortable("2", "work 2", 1, 1),
            sortable("01", "Same", 1, 1), sortable("1", "same", 1, 1)]
        queryState = .init(sort: .name, ascending: true)
        let numericOrder = try sortedIDs()
        queryState.ascending = false
        checks["numericTitlesAndEqualTitlesHaveDeterministicReverse"] = try numericOrder == ["01", "1", "2", "3"]
            && (try sortedIDs()) == numericOrder.reversed()

        // Pure source/query checks can run without creating any AppKit window.
        if CommandLine.arguments.contains("--source-only") {
            print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
            return
        }

        var rowEvents: [Int] = []
        let nativeRows: [ToolbarMenuPopoverPresenter.Row] = [
            .header("原选项"), .init(title: "不可用", kind: .action, isEnabled: false, handler: { rowEvents.append(0) }),
            .init(title: "当前选项", kind: .check, isChecked: true, handler: { rowEvents.append(1) }),
            .separator(), .init(title: "状态", kind: .info),
            .init(title: "执行", kind: .action, handler: { rowEvents.append(2) })]
        let nativeMenu = ToolbarMenuPopoverPresenter.menuRepresentation(title: "原入口", rows: nativeRows).submenu!
        checks["native-overflow-preserves-row-order-checkmark-separator-and-info-state"] = nativeMenu.items.map(\.title) == ["原选项", "不可用", "当前选项", "", "状态", "执行"]
            && nativeMenu.items[2].state == .on && nativeMenu.items[3].isSeparatorItem
            && !nativeMenu.items[0].isEnabled && !nativeMenu.items[1].isEnabled && !nativeMenu.items[4].isEnabled
        nativeMenu.performActionForItem(at: 2); nativeMenu.performActionForItem(at: 5)
        checks["native-overflow-dispatches-original-row-closures-once-without-a-sender"] = rowEvents == [1, 2]
        if let action = nativeMenu.items[1].action { NSApp.sendAction(action, to: nativeMenu.items[1].target, from: nativeMenu.items[1]) }
        checks["disabled-native-overflow-cannot-bypass-original-row-qualification"] = rowEvents == [1, 2]

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

        window.close()
        let historyMetricsData = try JSONSerialization.data(withJSONObject: ["historyReads": historyReadMetrics], options: [.sortedKeys])
        FileHandle.standardError.write(historyMetricsData + Data("\n".utf8))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
