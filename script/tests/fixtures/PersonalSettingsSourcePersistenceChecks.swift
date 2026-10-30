import Combine
import Foundation

// Only the temporary copies' real SQLite/JSON writer entries are observed.
// Counts include failed attempts; storage, ACK and recovery remain production.
nonisolated final class PersonalSettingsSourceWrites: @unchecked Sendable {
    static let shared = PersonalSettingsSourceWrites()
    private let lock = NSLock()
    private var entries: [String: Int] = [:]
    func record(_ owner: String) { lock.lock(); entries[owner, default: 0] += 1; lock.unlock() }
    func reset() { lock.lock(); entries.removeAll(); lock.unlock() }
    var counts: (video: Int, images: Int) {
        lock.lock(); defer { lock.unlock() }
        return (entries["video", default: 0], entries["images", default: 0])
    }
}

extension PersonalSettingsImportHarness {
    @MainActor static func runSourcePersistenceChecks(root: URL, manager: WallpaperManager, images: SILService,
        controller: UserCollectionsController, presentation: WallpaperLibraryPresentation) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let writes = PersonalSettingsSourceWrites.shared
        let profile = root.appendingPathComponent("source-writes-profile.json")
        let recovery = root.appendingPathComponent("source-writes-recovery.json")
        let date = Date(timeIntervalSince1970: 50)
        let video = manager.personalSettingsSources[0]
        let image = source("source-writes-image", root.appendingPathComponent("offline-image.png").path,
            "Original image", .staticImageLibrary)
        try images.applyPersonalSettingsSources([.init(before: nil, target: image)], at: date)
        let originalImages = images.wallpapers
        func coordinator() -> PersonalSettingsImportCoordinator {
            PersonalSettingsImportCoordinator(manager: manager, images: images, collections: controller, recoveryURL: recovery,
                readVideoSort: { try presentation.videoSortPreference() },
                validateVideoSort: { try presentation.validateVideoSortPatch($0, resetEpoch: $1) },
                applyVideoSort: { try presentation.applyVideoSortPatch($0, resetEpoch: $1) })
        }
        func prepare(_ sources: [PersonalSettingsLocalSource], collections: LibraryCollectionsPersonalSettingsImport = .init()) throws {
            try write(.init(exportedAt: date, preferences: .init(from: manager.settings),
                sources: sources, collections: collections), to: profile)
            writes.reset()
        }
        let importer = coordinator()
        let unavailable = ref("undeclared-offline-video")
        try prepare([], collections: .init(favoriteStates: [.init(reference: unavailable, isFavorite: true, favoritedAt: date)]))
        _ = try await importer.importPersonalSettings(from: profile)
        checks["EmptySourcePlanSkipsBothWriters"] = writes.counts == (0, 0)
        checks["UndeclaredUnavailableRelationCommitsWithoutSourceFlush"] = controller.snapshot.favorites.contains { $0.reference == unavailable }
            && importer.allowsEditing && !FileManager.default.fileExists(atPath: recovery.path)
        checks["EmptySourcePlanPreservesExistingDurableSources"] = try WallpaperIndexStore.shared.loadWallpapers() == manager.wallpapers
            && JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: images.persistenceURL)) == originalImages

        try prepare([video])
        _ = try await importer.importPersonalSettings(from: profile)
        checks["VideoOnlyPlanSkipsImageWriter"] = writes.counts == (1, 0)
        try prepare([image])
        _ = try await importer.importPersonalSettings(from: profile)
        checks["ImageOnlyPlanSkipsVideoWriter"] = writes.counts == (0, 1)
        try prepare([video, image])
        _ = try await importer.importPersonalSettings(from: profile)
        checks["RelatedEqualPatchesStillAcknowledgeBothWriters"] = writes.counts == (1, 1)
        let renamedVideo = source(video.reference.sourceID, video.path, "Renamed video", firstIndexedAt: video.firstIndexedAt)
        let renamedImage = source(image.reference.sourceID, image.path, "Renamed image", .staticImageLibrary)
        try prepare([renamedVideo, renamedImage])
        _ = try await importer.importPersonalSettings(from: profile)
        checks["MixedChangesPersistThroughBothOriginalWriters"] = try writes.counts == (1, 1)
            && WallpaperIndexStore.shared.loadWallpapers()[0].title == renamedVideo.title
            && JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: images.persistenceURL))[0].title == renamedImage.title

        try WallpaperIndexStore.shared.profileQueryOnly(true)
        try prepare([renamedImage])
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["UnrequestedVideoWriteFailureDoesNotBlockImageImport"] = writes.counts == (0, 1) && importer.allowsEditing
        } catch { checks["UnrequestedVideoWriteFailureDoesNotBlockImageImport"] = false }
        try WallpaperIndexStore.shared.profileQueryOnly(false)
        _ = try await importer.resumeIfNeeded()

        let imageBytes = try Data(contentsOf: images.persistenceURL)
        try FileManager.default.removeItem(at: images.persistenceURL)
        try FileManager.default.createDirectory(at: images.persistenceURL, withIntermediateDirectories: false)
        try prepare([renamedVideo])
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["UnrequestedImageWriteFailureDoesNotBlockVideoImport"] = writes.counts == (1, 0) && importer.allowsEditing
        } catch { checks["UnrequestedImageWriteFailureDoesNotBlockVideoImport"] = false }
        try FileManager.default.removeItem(at: images.persistenceURL)
        try imageBytes.write(to: images.persistenceURL)
        _ = try await importer.resumeIfNeeded()

        try WallpaperIndexStore.shared.profileQueryOnly(true)
        try prepare([renamedVideo])
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["RelatedEqualVideoPatchStillReportsWriteFailure"] = false
        } catch {
            checks["RelatedEqualVideoPatchStillReportsWriteFailure"] = writes.counts.video == 1
                && !importer.allowsEditing && FileManager.default.fileExists(atPath: recovery.path)
        }
        try WallpaperIndexStore.shared.profileQueryOnly(false)
        writes.reset()
        _ = try await importer.resumeIfNeeded()
        checks["RelatedEqualVideoPatchRetriesOriginalWriter"] = try writes.counts.video == 1 && importer.allowsEditing
            && WallpaperIndexStore.shared.loadWallpapers() == manager.wallpapers

        try FileManager.default.removeItem(at: images.persistenceURL)
        try FileManager.default.createDirectory(at: images.persistenceURL, withIntermediateDirectories: false)
        try prepare([renamedImage])
        do {
            _ = try await importer.importPersonalSettings(from: profile)
            checks["RelatedEqualImagePatchStillReportsWriteFailure"] = false
        } catch {
            checks["RelatedEqualImagePatchStillReportsWriteFailure"] = writes.counts.images == 1
                && !importer.allowsEditing && FileManager.default.fileExists(atPath: recovery.path)
        }
        try FileManager.default.removeItem(at: images.persistenceURL)
        try imageBytes.write(to: images.persistenceURL)
        writes.reset()
        _ = try await importer.resumeIfNeeded()
        checks["RelatedEqualImagePatchRetriesOriginalWriter"] = writes.counts.images == 1 && importer.allowsEditing

        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        WallpaperIndexStore.shared.profileHold(entered: entered, release: release)
        precondition(entered.wait(timeout: .now() + 3) == .success)
        manager.scheduleWallpapersAutoPersist()
        manager.saveWallpapers(); manager.saveWallpapers()
        let timer = manager.wallpapersAutoSaveWorkItem
        let revision = manager.wallpaperIndexSaveRevision
        let inFlight = manager.wallpaperIndexSaveInFlight?.revision
        let pending = manager.pendingWallpaperIndexSave?.revision
        DispatchQueue.global().async { release.signal() }
        try manager.applyPersonalSettingsSources([.init(before: renamedImage, target: renamedImage)])
        checks["UndeclaredVideoOwnerDoesNotRevokePendingOrInflightLocalSave"] = inFlight != nil && pending != nil
            && manager.wallpaperIndexSaveRevision == revision
            && manager.wallpaperIndexSaveInFlight?.revision == inFlight && manager.pendingWallpaperIndexSave?.revision == pending
            && timer != nil && timer === manager.wallpapersAutoSaveWorkItem && timer?.isCancelled == false
        manager.wallpapersAutoSaveWorkItem?.cancel(); manager.wallpapersAutoSaveWorkItem = nil
        for _ in 0..<600 {
            if manager.wallpaperIndexSaveInFlight == nil && manager.pendingWallpaperIndexSave == nil { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        checks["UndeclaredOwnerExistingSaveCompletesNormally"] = try manager.wallpaperIndexSaveInFlight == nil
            && manager.pendingWallpaperIndexSave == nil && WallpaperIndexStore.shared.loadWallpapers() == manager.wallpapers
        return checks
    }
}
