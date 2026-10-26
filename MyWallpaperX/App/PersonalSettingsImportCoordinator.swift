import Combine
import Foundation
import ImageIO

/// App-owned recovery for the three existing persistence owners. The SQLite
/// relationship transaction is not presented as a cross-owner transaction.
@MainActor final class PersonalSettingsImportCoordinator: ObservableObject {
    @Published private(set) var isApplying = false
    @Published private(set) var recoveryMessage: String?
    var allowsEditing: Bool { !isApplying && recoveryMessage == nil }

    private let manager: WallpaperManager
    private let images: SILService
    private let collections: UserCollectionsController
    private let recoveryURL: URL
    private let readVideoSort: @MainActor () throws -> WallpaperLibraryVideoSortPreference
    private let validateVideoSort: @MainActor (WallpaperLibraryVideoSortPatch, UUID) throws -> Void
    private let applyVideoSort: @MainActor (WallpaperLibraryVideoSortPatch, UUID) throws -> Void
    private let beforeApply: @MainActor () -> Void
    private var generation: UInt64 = 0

    private enum Stage: Int, Codable, Sendable {
        case prepared, videos, images, relationships, preferences, viewSort
    }
    private struct Recovery: Codable, Sendable {
        let schemaVersion: Int
        var stage: Stage
        let importedAt: Date
        let plan: LibraryPersonalSettingsPlan
        let videoSortPatch: WallpaperLibraryVideoSortPatch?
    }

    init(manager: WallpaperManager, images: SILService, collections: UserCollectionsController,
         recoveryURL: URL,
         readVideoSort: @escaping @MainActor () throws -> WallpaperLibraryVideoSortPreference,
         validateVideoSort: @escaping @MainActor (WallpaperLibraryVideoSortPatch, UUID) throws -> Void,
         applyVideoSort: @escaping @MainActor (WallpaperLibraryVideoSortPatch, UUID) throws -> Void,
         beforeApply: @escaping @MainActor () -> Void = {}) {
        self.manager = manager; self.images = images; self.collections = collections
        self.recoveryURL = recoveryURL; self.beforeApply = beforeApply
        self.readVideoSort = readVideoSort; self.validateVideoSort = validateVideoSort; self.applyVideoSort = applyVideoSort
        do {
            if let recovery = try readRecovery() {
                recoveryMessage = PersonalSettingsError.recoveryRequired(String(describing: recovery.stage)).localizedDescription
            }
        } catch { recoveryMessage = error.localizedDescription }
    }

    func exportPersonalSettings(to url: URL) async throws -> PersonalSettingsExportSummary {
        guard !isApplying else { throw PersonalSettingsError.importInProgress }
        guard recoveryMessage == nil else { throw PersonalSettingsError.recoveryRequired(recoveryMessage ?? "") }
        guard manager.didFinishInitialIndexLoad else { throw PersonalSettingsError.indexLoading }
        let sources = manager.personalSettingsSources + images.personalSettingsSources
        var preferences = PersonalSettingsPreferences(from: manager.settings)
        preferences.videoLibrarySort = try readVideoSort()
        // Legacy fields remain readable, but cannot export a retired/stale UI
        // value or mislabel createdAt/lastUsed as the old dateAdded behavior.
        preferences.sortMode = nil; preferences.sortAscending = nil
        let state = collections.snapshot
        let covers = try await collections.playlistCoverAssets(ids: Set(state.playlists.compactMap(\.customCoverAssetID)),
                                                               expectedEpoch: state.resetEpoch)
        let payload = try LibraryPersonalSettings.export(sources: sources, preferences: preferences,
                                                        state: state, coverAssets: covers)
        let worker = Task.detached(priority: .utility) {
            try LibraryPersonalSettings.encode(payload).write(to: url, options: .atomic)
        }
        try await worker.value
        return .init(wallpaperCount: payload.collections?.favoriteStates.count ?? sources.count,
                     tagCount: payload.collections?.playlists.count ?? 0)
    }

    func importPersonalSettings(from url: URL) async throws -> PersonalSettingsImportSummary {
        try admitImport()
        guard recoveryMessage == nil else { throw PersonalSettingsError.recoveryRequired(recoveryMessage ?? "") }
        do {
            if let _ = try readRecovery() { throw PersonalSettingsError.recoveryRequired("存在待恢复导入") }
        } catch {
            recoveryMessage = error.localizedDescription
            throw error
        }
        isApplying = true
        defer { isApplying = false }
        let epoch = generation, state = collections.snapshot
        let sources = manager.personalSettingsSources + images.personalSettingsSources
        let preferences = PersonalSettingsPreferences(from: manager.settings)
        let videoSortBefore = try readVideoSort()
        let legacyVideos = manager.wallpapers
        let worker = Task.detached(priority: .utility) {
            let payload = try LibraryPersonalSettings.decode(Data(contentsOf: url))
            if payload.schemaVersion >= 7 { try Self.validateCustomCoverCopies(payload.collections?.coverAssets ?? []) }
            let paths = LibraryPersonalSettings.paths(in: payload, sources: sources)
            var normalized: [String: String] = [:]
            for path in paths {
                normalized[path] = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            }
            let importedPaths = Set((payload.sources.map(\.path) + payload.entries.map(\.path) + payload.silEntries.map(\.path)
                + (payload.collections?.locators.compactMap { $0.locator.path } ?? [])).map { normalized[$0] ?? $0 })
            let missing = importedPaths.filter { !FileManager.default.fileExists(atPath: $0) }.count
            let legacyOrder = legacyVideos.enumerated().sorted {
                $0.element.lastUsed == $1.element.lastUsed ? $0.offset < $1.offset : $0.element.lastUsed < $1.element.lastUsed
            }.map { WallpaperReference(provider: .videoLibrary, sourceID: $0.element.id) }
            return (payload, normalized, missing, legacyOrder)
        }
        let (payload, paths, missing, legacyOrder) = try await worker.value
        try requireGeneration(epoch, resetEpoch: state.resetEpoch)
        let target = payload.preferences.applying(to: manager.settings)
        let plan = try LibraryPersonalSettings.plan(payload, sources: sources, beforePreferences: preferences,
            targetPreferences: .init(from: target), state: state, normalizedPaths: paths, missingPathCount: missing)
        var referencesByPath: [WallpaperProvider: [String: WallpaperReference]] = [:]
        for patch in plan.sourcePatches {
            let reference = patch.target.reference
            let path = paths[patch.target.path] ?? patch.target.path
            if referencesByPath[reference.provider]?[path] == nil {
                referencesByPath[reference.provider, default: [:]][path] = reference
            }
        }
        var remapping: [WallpaperReference: WallpaperReference] = [:]
        for declared in payload.sources {
            if let reference = referencesByPath[declared.reference.provider]?[paths[declared.path] ?? declared.path] {
                remapping[declared.reference] = reference
            }
        }
        let videoSortPatch = try payload.preferences.videoSortPatch(before: videoSortBefore,
            legacyTimeOrder: legacyOrder, remapping: remapping)
        if let videoSortPatch { try validateVideoSort(videoSortPatch, state.resetEpoch) }
        // Parse/mapping/preconditions complete before the first persistent edit.
        guard collections.snapshot.organizationState == state.organizationState else { throw UserCollectionsError.organizationConflict }
        try validateSources(plan)
        guard PersonalSettingsPreferences(from: manager.settings) == preferences else { throw PersonalSettingsError.preferencesChanged }
        var recovery = Recovery(schemaVersion: 2, stage: .prepared, importedAt: Date(), plan: plan, videoSortPatch: videoSortPatch)
        recoveryMessage = PersonalSettingsError.recoveryRequired("prepared").localizedDescription
        try writeRecovery(recovery)
        return try await apply(&recovery, generation: epoch)
    }

    /// Imported copies are decoded once in the existing explicit-import worker,
    /// before any source or relationship owner is changed. No source file is read.
    nonisolated private static func validateCustomCoverCopies(_ assets: [WallpaperPlaylistCoverAsset]) throws {
        for asset in assets {
            // Inspect encoded properties before decoding any pixels. A small
            // declaration cannot admit a much larger encoded source image.
            guard asset.isValidControlledCopy,
                  let source = CGImageSourceCreateWithData(asset.imageData as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  WallpaperPlaylistCoverAsset.allowsCopy(encodedByteCount: asset.imageData.count, pixelWidth: width, pixelHeight: height),
                  width == asset.pixelWidth, height == asset.pixelHeight else {
                throw PersonalSettingsError.invalidPayload("列表封面副本尺寸或数据预算无效")
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width == width, image.height == height else {
                throw PersonalSettingsError.invalidPayload("列表封面副本无法解码")
            }
        }
    }

    /// App startup calls this before admitting organization/settings editing.
    /// Missing and failed/corrupt recovery reads are distinct; errors never
    /// silently turn a half import into a fresh import.
    @discardableResult
    func resumeIfNeeded() async throws -> PersonalSettingsImportSummary? {
        try admitImport()
        let stored: Recovery
        do {
            guard let value = try readRecovery() else {
                recoveryMessage = nil
                resumeSourceCleanup()
                return nil
            }
            stored = value
        } catch {
            recoveryMessage = error.localizedDescription
            throw error
        }
        isApplying = true
        defer { isApplying = false }
        var recovery = stored
        return try await apply(&recovery, generation: generation)
    }

    /// The App invokes this in the existing reset preparation barrier.
    func cancelForReset() {
        generation &+= 1
        WallpaperManager.defersMissingFileCleanupForPersonalSettingsRecovery = false
        SILService.defersMissingFileCleanupForPersonalSettingsRecovery = false
    }

    /// Exit revokes late continuations but retains durable recovery and the
    /// startup cleanup barrier. The App then flushes the one relationship FIFO.
    func prepareForTermination() { generation &+= 1 }

    /// Only a committed new relationship epoch may retire the old import log.
    func clearRecoveryAfterReset() throws {
        guard !isApplying else { throw PersonalSettingsError.importInProgress }
        if let stored = try readRecovery() {
            guard stored.plan.resetEpoch != collections.snapshot.resetEpoch else { throw UserCollectionsError.staleResetEpoch }
            try FileManager.default.removeItem(at: recoveryURL)
        }
        recoveryMessage = nil
    }

    private func admitImport() throws {
        guard !isApplying else { throw PersonalSettingsError.importInProgress }
        guard manager.allowsLibraryMutation, images.allowsLibraryMutation, !collections.isResetting else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: manager.migrationRecoveryMessage
                ?? images.migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        guard manager.didFinishInitialIndexLoad else { throw PersonalSettingsError.indexLoading }
    }

    private func apply(_ recovery: inout Recovery, generation epoch: UInt64) async throws -> PersonalSettingsImportSummary {
        do {
            try requireGeneration(epoch, resetEpoch: recovery.plan.resetEpoch)
            try validateSources(recovery.plan)
            let current = PersonalSettingsPreferences(from: manager.settings)
            guard recovery.plan.beforePreferences.matchesForRecovery(current) || recovery.plan.targetPreferences.matchesForRecovery(current) else {
                throw PersonalSettingsError.preferencesChanged
            }
            if let patch = recovery.videoSortPatch { try validateVideoSort(patch, recovery.plan.resetEpoch) }
            beforeApply()
            try requireGeneration(epoch, resetEpoch: recovery.plan.resetEpoch)
            if recovery.stage.rawValue < Stage.videos.rawValue {
                try manager.applyPersonalSettingsSources(recovery.plan.sourcePatches)
                recovery.stage = .videos; try writeRecovery(recovery)
            }
            if recovery.stage.rawValue < Stage.images.rawValue {
                try images.applyPersonalSettingsSources(recovery.plan.sourcePatches, at: recovery.importedAt)
                recovery.stage = .images; try writeRecovery(recovery)
            }
            if recovery.stage.rawValue < Stage.relationships.rawValue {
                _ = try await collections.applyPersonalSettings(recovery.plan.collections, commandID: recovery.plan.commandID,
                    expectedOrganization: recovery.plan.expectedOrganization, expectedEpoch: recovery.plan.resetEpoch)
                try requireGeneration(epoch, resetEpoch: recovery.plan.resetEpoch)
                recovery.stage = .relationships; try writeRecovery(recovery)
            }
            if recovery.stage.rawValue < Stage.preferences.rawValue {
                try manager.applyPersonalSettingsPreferences(expected: recovery.plan.beforePreferences, target: recovery.plan.targetPreferences)
                recovery.stage = .preferences; try writeRecovery(recovery)
            }
            try requireGeneration(epoch, resetEpoch: recovery.plan.resetEpoch)
            if recovery.schemaVersion >= 2, recovery.stage.rawValue < Stage.viewSort.rawValue {
                if let patch = recovery.videoSortPatch { try applyVideoSort(patch, recovery.plan.resetEpoch) }
                recovery.stage = .viewSort; try writeRecovery(recovery)
            }
            try requireGeneration(epoch, resetEpoch: recovery.plan.resetEpoch)
            try FileManager.default.removeItem(at: recoveryURL)
            recoveryMessage = nil
            resumeSourceCleanup()
            NotificationCenter.default.post(name: .wallpaperManagerDidImportPersonalSettings, object: manager)
            return recovery.plan.summary
        } catch {
            recoveryMessage = PersonalSettingsError.recoveryRequired(String(describing: recovery.stage)).localizedDescription
                + "\n" + error.localizedDescription
            throw error
        }
    }

    private func requireGeneration(_ value: UInt64, resetEpoch: UUID) throws {
        guard generation == value, !collections.isResetting, collections.snapshot.resetEpoch == resetEpoch else {
            throw UserCollectionsError.staleResetEpoch
        }
    }

    private func resumeSourceCleanup() {
        manager.resumeMissingFileCleanupAfterSettingsRecovery()
        images.resumeMissingFileCleanupAfterSettingsRecovery()
    }

    private func validateSources(_ plan: LibraryPersonalSettingsPlan) throws {
        let sources = manager.personalSettingsSources + images.personalSettingsSources
        let current = Dictionary(sources.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        for patch in plan.sourcePatches {
            guard current[patch.target.reference] == patch.before || current[patch.target.reference] == patch.target else {
                throw PersonalSettingsError.sourceChanged
            }
        }
    }

    private func readRecovery() throws -> Recovery? {
        let data: Data
        do { data = try Data(contentsOf: recoveryURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        let record = try JSONDecoder().decode(Recovery.self, from: data)
        guard (1...2).contains(record.schemaVersion), record.schemaVersion != 1 || record.videoSortPatch == nil && record.stage.rawValue <= Stage.preferences.rawValue else {
            throw PersonalSettingsError.invalidPayload("导入恢复版本")
        }
        return record
    }

    private func writeRecovery(_ record: Recovery) throws {
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: recoveryURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: recoveryURL)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
