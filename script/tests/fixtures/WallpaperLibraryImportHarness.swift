import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

// PRODUCTION_IMAGE_MODEL
// PRODUCTION_IMPORT_VALUES

nonisolated enum WallpaperPlaybackSequence { struct Pending: Equatable, Sendable {} }
nonisolated final class ImageImportProbe: @unchecked Sendable {
    static let shared = ImageImportProbe()
    private let lock = NSLock()
    private var hold: (DispatchSemaphore, DispatchSemaphore)?
    private var failSynchronization = false
    func failNextSynchronization() { lock.lock(); failSynchronization = true; lock.unlock() }
    func consumeSynchronizationFailure() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = failSynchronization; failSynchronization = false; return value
    }
    func holdNext() -> (DispatchSemaphore, DispatchSemaphore) {
        let pair = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        lock.lock(); hold = pair; lock.unlock()
        return pair
    }
    func waitIfHeld() {
        lock.lock(); let pair = hold; hold = nil; lock.unlock()
        guard let pair else { return }
        pair.0.signal(); precondition(pair.1.wait(timeout: .now() + 5) == .success)
    }
}
@MainActor final class SILService {
    var allowsLibraryMutation = true
    var migrationRecoveryMessage: String?
    var metadataLoadGeneration: UInt64 = 0
    var currentContextTag: String?
    var wallpapers: [SILWallpaper] = []
    var selectedID: String?
    var selectedIDs = Set<String>()
    var isMultiSelectMode = false
    var sortedWallpapers: [SILWallpaper] { wallpapers }
    let persistenceURL: URL
    init(_ url: URL) { persistenceURL = url }
    func admitLibraryMutation(in window: NSWindow? = nil) -> Bool { allowsLibraryMutation }
    func syncSelectedWallpaperInspectorIfNeeded() {}
    func save() { try! persistWallpaperMetadata(wallpapers) }
    func resetForAudit() { metadataLoadGeneration &+= 1; wallpapers = []; save() }
    // PRODUCTION_IMAGE_METHODS
}
@MainActor final class WallpaperManager {
    var allowsLibraryMutation = true
    var migrationRecoveryMessage: String?
    var wallpaperIndexSaveEpoch: UInt64 = 0
    var wallpapers: [VideoWallpaper] = []
    let importPreparationQueue = DispatchQueue(label: "mwx.test.actual-import")
    let importPreparationStateLock = NSLock()
    var importPreparationGeneration: UInt64 = 0
    var importPreparationWorkItem: DispatchWorkItem?
    var libraryBackingPublished: ((WallpaperContentBackingPublication) -> Void)?
    var summaries: [ImportSummary] = []
    var assetJobs: [[URL]] = []
    var automaticPlays = 0
    var indexAcknowledgements = 0
    var indexAcknowledgementFails = false
    func persistWallpaperIndexNow(_ values: [VideoWallpaper]) throws {
        indexAcknowledgements += 1
        if indexAcknowledgementFails { throw CocoaError(.fileWriteNoPermission) }
    }
    func normalizedPath(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path }
    func pathExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func isReadablePath(_ path: String) -> Bool { FileManager.default.isReadableFile(atPath: path) }
    func existingThumbnailPath(for url: URL) -> String? { nil }
    func existingStaticFramePath(for url: URL) -> String? { nil }
    func recordInitialIndexImportContext(_ context: ImportContext, wallpaper: VideoWallpaper) {}
    func scheduleImportedAssetsProcessing(_ urls: [URL]) { assetJobs.append(urls) }
    func acceptsImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission) -> Bool { false }
    func setAsWallpaper(_ value: VideoWallpaper, admission: ImportedVideoPlaybackAdmission) { automaticPlays += 1 }
    func failImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission, reason: String) {}
    func reportMigrationReadOnly(in window: NSWindow?) {}
    func presentImportSummary(_ value: ImportSummary, in window: NSWindow?) { summaries.append(value) }
    func holdQueue() -> (DispatchSemaphore, DispatchSemaphore) {
        let pair = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        importPreparationQueue.async { pair.0.signal(); precondition(pair.1.wait(timeout: .now() + 5) == .success) }
        return pair
    }
    func resetForAudit() { wallpaperIndexSaveEpoch &+= 1; wallpapers = [] }
    // PRODUCTION_FAILURE_SUMMARY
    // PRODUCTION_VIDEO_METHODS
}
@MainActor final class WallpaperLibraryWorkspace {
    let collections: UserCollectionsController?
    let presentation = ImportPresentation()
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    var edited: [WallpaperLibraryPage] = []
    var contentValues: [WallpaperReference: WallpaperContentItem] = [:]
    let catalog = ImportCatalog()
    init(_ collections: UserCollectionsController) { self.collections = collections }
    func didEditMembers(of page: WallpaperLibraryPage) { edited.append(page) }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        guard let value = contentValues[reference] else { throw CocoaError(.fileNoSuchFile) }
        return value
    }
}
@MainActor final class ImportCatalog { var refreshes = 0; func refreshAvailability() { refreshes += 1 } }
@MainActor final class ImportPresentation { var canEditCollections = true; var page: WallpaperLibraryPage = .videos }
@MainActor var presentedImportAlerts: [(String, String)] = []
struct ImportAlert { let title: String; let message: String }
@MainActor func makeAppAlert(title: String, message: String) -> ImportAlert {
    ImportAlert(title: title, message: message)
}
@MainActor func presentAppAlert(_ value: ImportAlert, in window: NSWindow?) {
    presentedImportAlerts.append((value.title, value.message))
}
@MainActor func appModalHostWindow() -> NSWindow? { nil }

@main struct WallpaperLibraryImportHarness {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let until = Date().addingTimeInterval(5)
        while !condition(), Date() < until { try await Task.sleep(nanoseconds: 5_000_000) }
        precondition(condition(), "Actual import did not finish")
    }
    static func png(_ url: URL) throws {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh3sAAAAASUVORK5CYII=")!
        try bytes.write(to: url)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks: [String: Bool] = [:]
        let files = root.appendingPathComponent("files"); try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let imageA = files.appendingPathComponent("A.png"), imageB = files.appendingPathComponent("B.png")
        let unreadableImage = files.appendingPathComponent("unreadable.png")
        let missingImage = files.appendingPathComponent("missing.png")
        try png(imageA); try png(imageB); try png(unreadableImage)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableImage.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadableImage.path) }
        let directory = files.appendingPathComponent("Directory"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let nestedA = directory.appendingPathComponent("nested-A.png"), nestedB = directory.appendingPathComponent("nested-B.png")
        try png(nestedA); try png(nestedB)
        let misleading = directory.appendingPathComponent("looks-like-image.png")
        try FileManager.default.createDirectory(at: misleading, withIntermediateDirectories: true)
        let nestedVideo = directory.appendingPathComponent("not-recursively-imported.mp4")
        try Data("source video admission fixture".utf8).write(to: nestedVideo)
        let images = SILService(root.appendingPathComponent("images.json"))
        var receipt: WallpaperSourceImportResult?
        images.importImages(from: [imageA, imageA, missingImage, unreadableImage, directory], presentsSummary: false) { receipt = $0 }
        try await wait { receipt != nil }
        let sourceResult = receipt!
        checks["ActualImageWorkerReportsPerInputAddedExistingAndMissing"] = sourceResult.items.filter { $0.sourceURL == imageA }.map(\.disposition) == [.added, .existing]
            && sourceResult.items.contains { $0.sourceURL == missingImage && $0.disposition == .failed && $0.failureMessage == "文件不存在" }
        checks["ActualImageWorkerKeepsUnreadableSourceButExcludesOrganization"] = !FileManager.default.isReadableFile(atPath: unreadableImage.path)
            && sourceResult.items.contains { $0.sourceURL == unreadableImage && $0.organizationItem?.isAvailable == false }
            && !sourceResult.organizationItems.contains { $0.locator.path == unreadableImage.path }
        checks["ImageMetadataUsesOriginalWorkerAndJSONOwner"] = images.wallpapers.first { $0.path == imageA.path }?.pixelWidth == 1
            && (try? JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: images.persistenceURL)))?.count == images.wallpapers.count
        checks["ImageNamedDirectoryNeverBecomesAvailableSource"] = sourceResult.items.contains { $0.sourceURL.standardizedFileURL.path == misleading.standardizedFileURL.path && $0.disposition == .failed }
            && !images.wallpapers.contains { $0.path == misleading.path }
        do {
            let protected = root.appendingPathComponent("write-failure", isDirectory: true)
            try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
            let saved = protected.appendingPathComponent("images.json")
            let failingImages = SILService(saved)
            failingImages.wallpapers = [SILWallpaper(path: imageA.path)]
            failingImages.save()
            let original = try Data(contentsOf: saved), originalIDs = failingImages.wallpapers.map(\.id)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: protected.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path) }
            var failure: WallpaperSourceImportResult?
            failingImages.importImages(from: [imageB], presentsSummary: false) { failure = $0 }
            try await wait { failure != nil }
            let afterFailure = try Data(contentsOf: saved)
            checks["ExplicitImageReceiptRequiresActualJSONPersistenceBeforeSourcePublication"] = failure?.organizationItems.isEmpty == true
                && failure?.items.count == 1 && failure?.items.first?.disposition == .failed
                && failure?.items.first?.failureMessage?.contains("未获保存确认") == true
                && failingImages.wallpapers.map(\.id) == originalIDs && afterFailure == original
        }
        do {
            let saved = root.appendingPathComponent("sync-ack-failure.json")
            let uncertain = SILService(saved)
            ImageImportProbe.shared.failNextSynchronization()
            var failure: WallpaperSourceImportResult?
            uncertain.importImages(from: [imageB], presentsSummary: false) { failure = $0 }
            try await wait { failure != nil }
            let actual = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: saved))
            checks["WriteAfterAcknowledgementFailurePublishesDiskFactButNeverSuccessfulReceipt"] = actual.count == 1
                && uncertain.wallpapers == actual && failure?.items.first?.disposition == .failed
                && failure?.organizationItems.isEmpty == true
                && failure?.items.first?.failureMessage?.contains("未获保存确认") == true
        }
        checks["DirectoryImportRemainsImagesOnlyAndPreservesNestedReceiptOrder"] = sourceResult.organizationItems.contains { $0.locator.path == nestedA.path }
            && sourceResult.organizationItems.contains { $0.locator.path == nestedB.path }
            && !images.wallpapers.contains { $0.path == nestedVideo.path }
            && sourceResult.organizationItems.compactMap { $0.locator.path }.filter { $0.hasPrefix(directory.path + "/") }
                == images.wallpapers.map(\.path).filter { $0.hasPrefix(directory.path + "/") }
        let imageHold = ImageImportProbe.shared.holdNext()
        var lateImageCallback = false
        images.importImages(from: [imageB], presentsSummary: false) { _ in lateImageCallback = true }
        precondition(imageHold.0.wait(timeout: .now() + 3) == .success)
        images.resetForAudit(); imageHold.1.signal()
        try await Task.sleep(nanoseconds: 120_000_000)
        checks["ResetRevokesActualImageWorkerBeforeCommitAndCallback"] = images.wallpapers.isEmpty && !lateImageCallback

        let videoA = files.appendingPathComponent("A.mp4"), videoB = files.appendingPathComponent("B.mp4")
        let unreadableVideo = files.appendingPathComponent("unreadable.mp4"), missingVideo = files.appendingPathComponent("missing.mp4")
        try Data("video admission A".utf8).write(to: videoA); try Data("video admission B".utf8).write(to: videoB)
        try Data("unreadable admission".utf8).write(to: unreadableVideo)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableVideo.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadableVideo.path) }
        let manager = WallpaperManager()
        var firstVideo: WallpaperSourceImportResult?, secondVideo: WallpaperSourceImportResult?, samePathVideo: WallpaperSourceImportResult?
        let videoHold = manager.holdQueue(); precondition(videoHold.0.wait(timeout: .now() + 3) == .success)
        manager.processImportedVideos(from: [videoA, videoA, missingVideo, unreadableVideo], presentingIn: nil, context: .library,
            presentsSummary: false) { firstVideo = $0 }
        manager.processImportedVideos(from: [videoB], presentingIn: nil, context: .library, presentsSummary: false) { secondVideo = $0 }
        manager.processImportedVideos(from: [videoA], presentingIn: nil, context: .library, presentsSummary: false) { samePathVideo = $0 }
        videoHold.1.signal()
        try await wait { firstVideo != nil && secondVideo != nil && samePathVideo != nil }
        checks["TwoIndependentVideoCommandsBothCompleteWithoutSuperseding"] = firstVideo?.addedCount == 1 && secondVideo?.addedCount == 1
            && manager.wallpapers.map(\.path) == [manager.normalizedPath(videoA.path), manager.normalizedPath(videoB.path)]
        checks["ConcurrentSamePathVideoCommandReusesCommittedSourceID"] = samePathVideo?.existingCount == 1
            && samePathVideo?.organizationItems.first?.reference == firstVideo?.organizationItems.first?.reference
            && manager.wallpapers.count == 2
        checks["ActualVideoWorkerPreservesPerInputOrderAndFailureReasons"] = firstVideo?.items.map(\.sourceURL.path)
                == [videoA, videoA, missingVideo, unreadableVideo].map { manager.normalizedPath($0.path) }
            && firstVideo?.items.map(\.disposition) == [.added, .existing, .failed, .failed]
            && firstVideo?.items[2].failureMessage == "文件不存在" && firstVideo?.items[3].failureMessage == "文件无法读取"
        checks["VideoReceiptUsesStableSourceIDAndNoOrganizationAutoplay"] = firstVideo?.organizationItems.first?.reference.sourceID == manager.wallpapers[0].id
            && manager.automaticPlays == 0 && manager.summaries.isEmpty
        let resetHold = manager.holdQueue(); precondition(resetHold.0.wait(timeout: .now() + 3) == .success)
        var lateVideoCallback = false
        manager.processImportedVideos(from: [videoA], presentingIn: nil, context: .library, presentsSummary: false) { _ in lateVideoCallback = true }
        manager.resetForAudit(); resetHold.1.signal()
        try await Task.sleep(nanoseconds: 120_000_000)
        checks["ResetRevokesActualVideoWorkerAndOldReceipt"] = manager.wallpapers.isEmpty && !lateVideoCallback

        let store = UserCollectionsStore(url: root.appendingPathComponent("relationships.sqlite3"))
        let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let workspace = WallpaperLibraryWorkspace(controller)
        let target = try await controller.createPlaylist(name: "Captured target")
        let another = try await controller.createPlaylist(name: "Another list")
        let coordinator = WallpaperLibraryImportCoordinator(workspace: workspace, manager: manager, images: images, hostWindow: { nil })
        let unsupported = files.appendingPathComponent("not-media.txt"); try Data("not media".utf8).write(to: unsupported)
        let originalOrder = [videoB, directory, videoA, imageA, missingVideo, unsupported]
        coordinator.importFiles(originalOrder, to: .playlist(target))
        try await wait { presentedImportAlerts.contains { $0.0 == "导入结果" } }
        let sourceIDs = Dictionary(manager.wallpapers.map { ($0.path, WallpaperReference(provider: .videoLibrary, sourceID: $0.id)) }, uniquingKeysWith: { a, _ in a })
        let imageIDs = Dictionary(images.wallpapers.map { ($0.path, WallpaperReference(provider: .staticImageLibrary, sourceID: $0.id)) }, uniquingKeysWith: { a, _ in a })
        let members = controller.snapshot.members.filter { $0.playlistID == target }.sorted { $0.position < $1.position }.map(\.reference)
        let middle = images.wallpapers.filter { $0.path.hasPrefix(directory.path + "/") }.map {
            WallpaperReference(provider: .staticImageLibrary, sourceID: $0.id)
        }
        checks["MixedCoordinatorPreservesTopLevelFileAndDirectoryPositions"] = members.count == 5
            && members.first == sourceIDs[manager.normalizedPath(videoB.path)] && Array(members[1...2]) == middle
            && members[3] == sourceIDs[manager.normalizedPath(videoA.path)] && members[4] == imageIDs[imageA.path]
        checks["CapturedTargetNeverUsesAnotherCurrentList"] = !controller.snapshot.members.contains { $0.playlistID == another }
            && workspace.edited == [.playlist(target)]
        let summary = presentedImportAlerts.last!.1
        checks["CombinedFailureSummaryKeepsRealReasonsAndCounts"] = summary.contains("新增入库：5 项")
            && summary.contains("未完成：3 项") && summary.contains("missing.mp4：文件不存在")
            && summary.contains("not-media.txt：该页面不接受此文件类型") && summary.contains("looks-like-image.png")
        checks["MixedImportHasNoRetiredTagFavoriteOrPlaybackSideEffect"] = manager.wallpapers.allSatisfy { $0.tags.isEmpty && !$0.isFavorite }
            && images.wallpapers.allSatisfy { $0.tags.isEmpty } && controller.snapshot.recent.isEmpty
            && controller.snapshot.favorites.isEmpty && manager.automaticPlays == 0

        let restoredReference = sourceIDs[manager.normalizedPath(videoA.path)]!
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let beforeRestoreAlerts = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .videos)
        try await wait { presentedImportAlerts.count > beforeRestoreAlerts }
        checks["ExplicitVerifiedExistingImportRestoresTheLibraryWithoutCopyingOrPlayback"] = !controller.snapshot.excludedLibraryReferences.contains { $0.reference == restoredReference }
            && manager.wallpapers.filter { $0.id == restoredReference.sourceID }.count == 1 && manager.automaticPlays == 0
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let restoreHold = manager.holdQueue(); precondition(restoreHold.0.wait(timeout: .now() + 3) == .success)
        let beforeLateRestoreAlerts = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .videos)
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let newHide = controller.snapshot.excludedLibraryReferences
        restoreHold.1.signal()
        try await wait { presentedImportAlerts.count > beforeLateRestoreAlerts }
        checks["ExplicitImportSuccessCannotClearAHideAdmittedAfterTheImportStarted"] = controller.snapshot.excludedLibraryReferences == newHide
            && FileManager.default.fileExists(atPath: videoA.path)

        let beforeFailedOnly = controller.snapshot.organizationState, beforeFailedRevision = controller.snapshot.revision
        let editsBeforeFailure = workspace.edited, failureAlertCount = presentedImportAlerts.count
        coordinator.importFiles([missingVideo, unsupported], to: .playlist(target))
        try await wait { presentedImportAlerts.count > failureAlertCount }
        checks["AllFailedImportDoesNotTouchOrganizationRevisionOrUndoMetadata"] = controller.snapshot.organizationState == beforeFailedOnly
            && controller.snapshot.revision == beforeFailedRevision && workspace.edited == editsBeforeFailure
        let failedDestination = try await controller.createPlaylist(name: "No successful source")
        let noSuccessHold = manager.holdQueue(); precondition(noSuccessHold.0.wait(timeout: .now() + 3) == .success)
        let noSuccessAlertCount = presentedImportAlerts.count
        coordinator.importFiles([missingVideo], to: .playlist(failedDestination))
        _ = try await controller.perform(.deletePlaylist(failedDestination))
        noSuccessHold.1.signal()
        try await wait { presentedImportAlerts.count > noSuccessAlertCount }
        checks["AllFailedDeletedDestinationNeverClaimsSourceImported"] = presentedImportAlerts.last?.0 != "壁纸已入库，整理未完成"
            && presentedImportAlerts.last?.1.contains("新增入库：0 项") == true
            && presentedImportAlerts.last?.1.contains("文件不存在") == true

        // A real source command may finish after its destination was deleted;
        // the source remains, and the App reports only organization failure.
        let held = manager.holdQueue(); precondition(held.0.wait(timeout: .now() + 3) == .success)
        let removed = try await controller.createPlaylist(name: "Deleted while preparing")
        let deletedAlertCount = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .playlist(removed))
        _ = try await controller.perform(.deletePlaylist(removed)); held.1.signal()
        try await wait { presentedImportAlerts.count > deletedAlertCount }
        checks["DeletedDestinationDoesNotRedirectOrHideSourceSuccess"] = manager.wallpapers.contains { $0.path == manager.normalizedPath(videoA.path) }
            && !controller.snapshot.members.contains { $0.playlistID == removed }
            && presentedImportAlerts.last?.0 == "导入整理未完成"
            && presentedImportAlerts.last?.1.contains("原始壁纸仍保留在资料库中") == true
        let alertCount = presentedImportAlerts.count
        let resetBatch = manager.holdQueue(); precondition(resetBatch.0.wait(timeout: .now() + 3) == .success)
        coordinator.importFiles([videoA], to: .favorites)
        try await controller.reset(); manager.resetForAudit(); images.resetForAudit()
        resetBatch.1.signal(); try await Task.sleep(nanoseconds: 150_000_000)
        checks["ResetRevokesMixedBatchOrganizationAndLateSuccessAlert"] = controller.snapshot.favorites.isEmpty
            && presentedImportAlerts.count == alertCount && manager.wallpapers.isEmpty && images.wallpapers.isEmpty

        // Recent readiness uses the same canonical unique-before-50 boundary
        // as the visible page, including the actual fiftieth provider.
        let canonical = WallpaperReference(provider: .videoLibrary, sourceID: "canonical")
        let alias = WallpaperReference(provider: .videoLibrary, sourceID: "alias")
        let final = WallpaperReference(provider: .staticImageLibrary, sourceID: "fiftieth")
        var recent = [WallpaperRecentUse(reference: alias, lastSuccessfulUseAt: nil, commitSequence: 100, migrationOrder: nil),
                      WallpaperRecentUse(reference: canonical, lastSuccessfulUseAt: nil, commitSequence: 99, migrationOrder: nil)]
        recent += (0..<48).map { .init(reference: .init(provider: .videoLibrary, sourceID: "v\($0)"), lastSuccessfulUseAt: nil,
                                     commitSequence: Int64(98 - $0), migrationOrder: nil) }
        recent.append(.init(reference: final, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: nil))
        let relationship = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil, playlists: [], members: [], favorites: [],
            recent: recent, aliases: [.init(alias: alias, canonical: canonical, proof: .restoredSourceRecord)], locators: [])
        let required = try WallpaperLibraryQuery.requiredProviders(page: .recent, state: .init(), relationships: relationship)
        let visible = try WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: .init(), relationships: relationship)
        checks["RecentReadinessSharesCanonicalUniqueBeforeFiftyBoundary"] = required == [.videoLibrary, .staticImageLibrary]
            && visible.items.count == 50 && visible.items.last?.reference == final
        if checks.values.contains(false) {
            let detail: [String: Any] = [
                "videoItems": firstVideo!.items.map { ["path": $0.sourceURL.path, "status": String(describing: $0.disposition), "reason": $0.failureMessage ?? ""] },
                "secondVideoItems": secondVideo!.items.map { ["path": $0.sourceURL.path, "status": String(describing: $0.disposition)] },
                "videoSourcePaths": sourceIDs.keys.sorted(), "expectedVideos": [videoA.path, videoB.path],
                "mixedMembers": members.map(\.storageKey), "expectedVideoIDs": sourceIDs.mapValues(\.storageKey),
                "expectedImageIDs": imageIDs.mapValues(\.storageKey), "summary": summary
            ]
            FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]))
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
