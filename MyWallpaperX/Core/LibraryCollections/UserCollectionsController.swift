import Combine
import Foundation

/// Main-actor snapshot adapter for the one relationship store. It serializes
/// admitted UI commands and success metadata; it owns no source library or
/// playback state. App/Shell inject one instance into their consumers.
@MainActor final class UserCollectionsController: ObservableObject {
    @Published private(set) var snapshot: UserCollectionsSnapshot
    @Published private(set) var lastError: String?
    @Published private(set) var isResetting = false
    /// Fired synchronously in the admitted FIFO turn, after the actual commit.
    /// Only explicit UI actions opt in; playback/profile metadata never does.
    var onOrganizationTransaction: ((LibraryCollectionsOrganizationState, LibraryCollectionsOrganizationState, String, UUID) -> Void)?
    private let store: UserCollectionsStore
    private var tail: Task<Void, Never>?
    private var admission: UInt64 = 0
    private var historyToken: LibraryHistoryWriterToken?
    private var pendingHistory: [SuccessfulUse] = []
    private var hasIssuedOrganizationUndo = false

    private struct SuccessfulUse {
        let reference: WallpaperReference
        let locator: WallpaperLocator?
        let sequence: UInt64
        let date: Date
    }

    init(store: UserCollectionsStore, snapshot: UserCollectionsSnapshot) {
        self.store = store
        self.snapshot = snapshot
    }

    @discardableResult
    func perform(_ commands: [UserCollectionsCommand], undoName: String? = nil,
                 expectedEpoch: UUID? = nil) async throws -> UserCollectionsSnapshot {
        let clearsHistory = commands.contains {
            switch $0 { case .clearRecent, .removeRecent: return true; default: return false }
        }
        let pendingSequences = clearsHistory ? Set(pendingHistory.map(\.sequence)) : []
        return try await enqueueOperation(expectedEpoch: expectedEpoch, undoName: undoName,
            afterCommit: { _, state in self.discardClearedHistory(commands, admitted: pendingSequences, aliases: state.aliases) }) { _, epoch in
                try await self.store.apply(commands, expectedEpoch: epoch)
            }
    }

    private func enqueue(undoName: String? = nil,
                         _ makeCommands: @escaping @MainActor (UserCollectionsSnapshot) -> [UserCollectionsCommand]) async throws -> UserCollectionsSnapshot {
        try await enqueueOperation(undoName: undoName) { state, epoch in
            try await self.store.apply(makeCommands(state), expectedEpoch: epoch)
        }
    }

    private func enqueueOperation(expectedEpoch: UUID? = nil, undoName: String? = nil,
        afterCommit: (@MainActor (UserCollectionsSnapshot, UserCollectionsSnapshot) -> Void)? = nil,
        _ operation: @escaping @MainActor (UserCollectionsSnapshot, UUID) async throws -> UserCollectionsSnapshot) async throws -> UserCollectionsSnapshot {
        guard !isResetting, expectedEpoch == nil || expectedEpoch == snapshot.resetEpoch else { throw UserCollectionsError.staleResetEpoch }
        let generation = admission, epoch = expectedEpoch ?? snapshot.resetEpoch, preceding = tail
        let task = Task { @MainActor in
            await preceding?.value
            guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
            let before = self.snapshot
            do {
                let state = try await operation(before, epoch)
                guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
                self.snapshot = state
                self.lastError = nil
                afterCommit?(before, state)
                if let undoName, before.organizationState != state.organizationState {
                    self.hasIssuedOrganizationUndo = true
                    self.onOrganizationTransaction?(before.organizationState, state.organizationState, undoName, epoch)
                }
                return state
            } catch {
                if self.admission == generation { self.lastError = error.localizedDescription }
                throw error
            }
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    @discardableResult
    func perform(_ command: UserCollectionsCommand, undoName: String? = nil,
                 expectedEpoch: UUID? = nil) async throws -> UserCollectionsSnapshot {
        try await perform([command], undoName: undoName, expectedEpoch: expectedEpoch)
    }

    @discardableResult
    func restoreOrganization(expected: LibraryCollectionsOrganizationState, replacement: LibraryCollectionsOrganizationState,
                             expectedEpoch: UUID) async throws -> UserCollectionsSnapshot {
        try await perform(.restoreOrganization(expected: expected, replacement: replacement), expectedEpoch: expectedEpoch)
    }

    @discardableResult
    func applyPersonalSettings(_ payload: LibraryCollectionsPersonalSettingsImport, commandID: UUID,
                              expectedOrganization: LibraryCollectionsOrganizationState,
                              expectedEpoch: UUID) async throws -> UserCollectionsSnapshot {
        try await enqueueOperation(expectedEpoch: expectedEpoch) { _, epoch in
            try await self.store.applyPersonalSettings(payload, commandID: commandID,
                expectedOrganization: expectedOrganization, expectedEpoch: epoch)
        }
    }

    /// Removing history must not resurrect an earlier failed metadata write on
    /// exit flush. Retire only events admitted before the successful clear; real
    /// later playback events still publish normally, with the original watermark.
    private func discardClearedHistory(_ commands: [UserCollectionsCommand], admitted: Set<UInt64>, aliases: [WallpaperReferenceAlias]) {
        guard !admitted.isEmpty else { return }
        var clearAll = false, removed = Set<WallpaperReference>()
        for command in commands {
            switch command {
            case .clearRecent: clearAll = true
            case .removeRecent(let references): removed.formUnion(references)
            default: break
            }
        }
        guard clearAll || !removed.isEmpty else { return }
        if clearAll {
            pendingHistory.removeAll { admitted.contains($0.sequence) }
            return
        }
        let targets = Dictionary(uniqueKeysWithValues: aliases.map { ($0.alias, $0.canonical) })
        func canonical(_ reference: WallpaperReference) -> WallpaperReference {
            var value = reference, seen = Set<WallpaperReference>()
            while let next = targets[value], seen.insert(value).inserted { value = next }
            return value
        }
        removed = Set(removed.map(canonical))
        pendingHistory.removeAll { admitted.contains($0.sequence) && removed.contains(canonical($0.reference)) }
    }

    @discardableResult
    func createPlaylist(name: String, members: [WallpaperOrganizationItem] = [], at date: Date = Date()) async throws -> UUID {
        try await createPlaylist(metadata: .init(name: name), members: members, at: date)
    }

    @discardableResult
    func createPlaylist(metadata: WallpaperPlaylistMetadata, coverAsset: WallpaperPlaylistCoverAsset? = nil,
                        members: [WallpaperOrganizationItem] = [], at date: Date = Date(),
                        expectedEpoch: UUID? = nil) async throws -> UUID {
        let id = UUID()
        _ = try await enqueueOperation(expectedEpoch: expectedEpoch, undoName: "新建播放列表") { state, epoch in
            let playlist = WallpaperPlaylist(id: id, name: metadata.name.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: date, sidebarRank: state.playlists.count,
                descriptionText: metadata.descriptionText, customCoverAssetID: metadata.customCoverAssetID)
            var commands: [UserCollectionsCommand] = [.createPlaylistWithCover(playlist, coverAsset)]
            if !members.isEmpty { commands.append(.addMembers(id, members, date)) }
            commands.append(.reorderPlaylists(state.playlists.map(\.id) + [id]))
            return try await self.store.apply(commands, expectedEpoch: epoch)
        }
        return id
    }

    @discardableResult
    func editPlaylistMetadata(id: UUID, expected: WallpaperPlaylistMetadata, replacement: WallpaperPlaylistMetadata,
                              coverAsset: WallpaperPlaylistCoverAsset? = nil, at date: Date = Date(),
                              expectedEpoch: UUID) async throws -> UserCollectionsSnapshot {
        try await perform(.editPlaylistMetadata(id: id, expected: expected, replacement: replacement,
            coverAsset: coverAsset, at: date), undoName: "编辑播放列表", expectedEpoch: expectedEpoch)
    }

    func playlistCoverAsset(id: UUID, expectedEpoch: UUID) async throws -> WallpaperPlaylistCoverAsset? {
        try await store.playlistCoverAsset(id: id, expectedEpoch: expectedEpoch)
    }

    func playlistCoverAssets(ids: Set<UUID>, expectedEpoch: UUID) async throws -> [WallpaperPlaylistCoverAsset] {
        try await store.playlistCoverAssets(ids: ids, expectedEpoch: expectedEpoch)
    }

    func pruneUnreferencedPlaylistCoverAssets(expectedEpoch: UUID) async throws {
        _ = try await enqueueOperation(expectedEpoch: expectedEpoch) { state, epoch in
            guard !self.hasIssuedOrganizationUndo else { return state }
            try await self.store.pruneUnreferencedPlaylistCoverAssets(expectedEpoch: epoch)
            return state
        }
    }

    @discardableResult
    func duplicatePlaylist(_ sourceID: UUID, at date: Date = Date()) async throws -> UUID {
        let id = UUID()
        _ = try await enqueue(undoName: "复制播放列表") { state in
            let name = (state.playlists.first { $0.id == sourceID }?.name ?? "播放列表") + " 副本"
            let playlist = WallpaperPlaylist(id: id, name: name, createdAt: date, sidebarRank: state.playlists.count)
            return [.duplicatePlaylist(sourceID: sourceID, playlist: playlist),
                    .reorderPlaylists(state.playlists.map(\.id) + [id])]
        }
        return id
    }

    /// Called synchronously at the original successful product commit. Enqueue
    /// before yielding so two real commits cannot reach SQLite out of order.
    /// Failed metadata stays at the head; a later commit or exit flush retries
    /// it without replaying the wallpaper or replacing its output.
    func recordSuccessfulUse(_ reference: WallpaperReference, locator: WallpaperLocator?,
                             sequence: UInt64, at date: Date = Date()) {
        guard !isResetting else { return }
        pendingHistory.append(SuccessfulUse(reference: reference, locator: locator, sequence: sequence, date: date))
        scheduleHistoryDrain()
    }

    private func scheduleHistoryDrain() {
        let generation = admission, preceding = tail
        let task = Task { @MainActor in
            await preceding?.value
            guard self.admission == generation else { return }
            await self.drainHistory(generation: generation)
        }
        tail = task
    }

    private func drainHistory(generation: UInt64) async {
        guard !pendingHistory.isEmpty else { return }
        do {
            if historyToken == nil {
                let token = try await store.startHistorySession(expectedEpoch: snapshot.resetEpoch)
                guard admission == generation else { return }
                historyToken = token
            }
            guard let token = historyToken else { return }
            while admission == generation, let event = pendingHistory.first {
                _ = try await store.recordSuccessfulUse(event.reference, locator: event.locator,
                                                        token: token, sequence: event.sequence, at: event.date)
                guard admission == generation else { return }
                pendingHistory.removeFirst()
            }
            let state = try await store.snapshot()
            guard admission == generation else { return }
            snapshot = state
            lastError = nil
        } catch {
            if admission == generation { lastError = error.localizedDescription }
        }
    }

    /// One reset barrier revokes queued commands and pending metadata at once.
    /// Successive resets read the latest epoch inside their serialized turn.
    func reset(beforeStoreReset: @escaping @MainActor () -> Void = {}) async throws {
        admission &+= 1
        let generation = admission, preceding = tail
        isResetting = true
        pendingHistory.removeAll()
        historyToken = nil
        let task = Task { @MainActor in
            await preceding?.value
            guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
            do {
                let current = try await self.store.snapshot()
                guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
                beforeStoreReset()
                guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
                let state = try await self.store.reset(expectedEpoch: current.resetEpoch)
                guard self.admission == generation else { throw UserCollectionsError.staleResetEpoch }
                self.snapshot = state
                self.lastError = nil
                self.hasIssuedOrganizationUndo = false
                self.isResetting = false
            } catch {
                if self.admission == generation { self.lastError = error.localizedDescription; self.isResetting = false }
                throw error
            }
        }
        tail = Task { _ = try? await task.value }
        try await task.value
    }

    /// Await the current FIFO until its actual Task identity is stable. A real
    /// playback commit during an await may append another tail. Failed UI
    /// commands are already reported to their callers and do not block exit;
    /// only retained, unpersisted success metadata reports a save failure.
    func flush() async -> String? {
        if !pendingHistory.isEmpty { scheduleHistoryDrain() }
        while let pending = tail {
            await pending.value
            if tail == pending { break }
        }
        return pendingHistory.isEmpty ? nil : lastError
    }
}
