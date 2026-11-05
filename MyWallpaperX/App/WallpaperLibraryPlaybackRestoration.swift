import Foundation

private nonisolated struct WallpaperPlaybackRestorationEnvelope: Codable, Equatable {
    enum Status: String, Codable { case selection, stopped }
    let schema: Int
    let status: Status
    let source: WallpaperPlaybackSequence.Source?
    let sourceQuery: WallpaperLibraryQueryState?
    let reference: WallpaperReference?
    let userPaused: Bool

    var isValid: Bool {
        guard schema == 2 else { return false }
        switch status {
        case .stopped where source == nil && sourceQuery == nil && reference == nil: return true
        case .selection, .stopped:
            guard let source, let reference, !reference.sourceID.isEmpty else { return false }
            switch source {
            case .single(let value): return value == reference && sourceQuery == nil
            case .global: return sourceQuery == nil
            case .page(let page): return !page.isRemoteBrowse && page != .playlists && sourceQuery != nil
            }
        }
    }
}

/// The App's only replay owner. Persisted metadata describes a last
/// successful selection, never an exported queue, product ticket or renderer.
@MainActor final class WallpaperLibraryPlaybackRestoration {
    static let storageKey = "WallpaperLibraryPlaybackSession"
    typealias Snapshot = WallpaperPlaybackSequence.Snapshot
    typealias Source = WallpaperPlaybackSequence.Source
    private enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
    private let manager: WallpaperManager
    private let defaults: UserDefaults
    private let snapshotProvider: (Source, WallpaperLibraryQueryState?) throws -> Snapshot?
    private let contentResolver: (WallpaperReference) throws -> WallpaperContentItem?
    private let dependencyProvider: (Source, WallpaperLibraryQueryState?) throws -> Set<WallpaperProvider>
    private let prepareProviders: (Set<WallpaperProvider>) -> Void
    private let report: (Error) -> Void
    private var envelope: WallpaperPlaybackRestorationEnvelope?
    private var preservesUnrecognizedInput = false
    private var didReportUnrecognizedInput = false
    private var waiting = true
    private var waitingIntentEpoch: UInt64
    private var lastResetEpoch: UUID?
    private var latestCatalogRevision: UInt64 = 0
    private var resetBarrier: (epoch: UUID?, revision: UInt64)?
    private var existingPlaylistIDs = Set<UUID>()
    private var loadedProviders = Set<WallpaperProvider>()
    private var relationshipsReady = false
    private var manualReplayFailure: (ticket: PlaybackSwitchTicket, notify: () -> Void)?

    /// The same saved success descriptor serves manual replay. A stopped
    /// descriptor retains identity without granting automatic launch admission.
    var rememberedReference: WallpaperReference? {
        guard !preservesUnrecognizedInput else { return nil }
        return envelope?.reference
    }

    init(manager: WallpaperManager, defaults: UserDefaults,
         snapshotProvider: @escaping (Source, WallpaperLibraryQueryState?) throws -> Snapshot?,
         contentResolver: @escaping (WallpaperReference) throws -> WallpaperContentItem?,
         dependencyProvider: @escaping (Source, WallpaperLibraryQueryState?) throws -> Set<WallpaperProvider> = { _, _ in Set(WallpaperProvider.allCases) },
         prepareProviders: @escaping (Set<WallpaperProvider>) -> Void = { _ in },
         report: @escaping (Error) -> Void = { _ in }) {
        self.manager = manager
        self.defaults = defaults
        self.snapshotProvider = snapshotProvider
        self.contentResolver = contentResolver
        self.dependencyProvider = dependencyProvider
        self.prepareProviders = prepareProviders
        self.report = report
        waitingIntentEpoch = manager.playbackIntentEpoch
        readEnvelope()
    }

    @discardableResult func resumeLastSelection(onFailure: @escaping () -> Void = {}) -> Bool {
        guard manager.playbackSwitch.committed == nil, manager.playbackSwitch.pending == nil,
              manager.libraryPlaybackSequence.pending == nil,
              let saved = envelope, rememberedReference != nil else { return false }
        do {
            let providers = try requiredProviders(includingStopped: true)
            prepareProviders(providers)
            guard relationshipsReady, providers.isSubset(of: loadedProviders) else {
                report(Failure.message("资料库仍在载入，请稍后重试。"))
                return false
            }
        } catch { report(error); return false }
        waiting = false
        manualReplayFailure = nil
        guard restore(saved, userPaused: false) else { return false }
        if let pending = manager.libraryPlaybackSequence.pending, pending.proposal.cause == .restore {
            manualReplayFailure = (pending.ticket, onFailure)
        } else if manager.playbackSwitch.committed == nil {
            report(Failure.message("上次成功播放的壁纸恢复失败，请重新选择壁纸。"))
            return false
        }
        return true
    }

    /// Only actual source dependencies gate replay. An unrelated failed online
    /// scan cannot block a validated local selection; unknown dependencies are
    /// still loading, never evidence that a file or membership was deleted.
    func updateInitialReadiness(loadedProviders: Set<WallpaperProvider>, existingPlaylistIDs: Set<UUID>,
                                resetEpoch: UUID, relationshipsReady: Bool = true,
                                catalogRevision: UInt64 = 0) {
        self.existingPlaylistIDs = existingPlaylistIDs
        self.loadedProviders = loadedProviders
        self.relationshipsReady = relationshipsReady
        lastResetEpoch = resetEpoch
        latestCatalogRevision = catalogRevision
        guard waiting else { return }
        guard manager.playbackIntentEpoch == waitingIntentEpoch else {
            waiting = false
            return
        }
        guard relationshipsReady else { return }
        if manager.settings.restorePlaybackOnLaunch && !preservesUnrecognizedInput {
            do {
                let providers = try requiredProviders()
                prepareProviders(providers)
                if !providers.isSubset(of: loadedProviders) { return }
            }
            catch { waiting = false; report(error); return }
        }
        if let barrier = resetBarrier {
            guard (barrier.epoch == nil || barrier.epoch != resetEpoch), catalogRevision > barrier.revision else { return }
        }
        guard manager.playbackIntentEpoch == waitingIntentEpoch else { waiting = false; return }
        waiting = false
        resetBarrier = nil
        guard manager.settings.restorePlaybackOnLaunch else {
            // No product intent/session is admitted; OS-applied images remain.
            manager.stopAutoSwitchTimer()
            manager.currentWallpaper = nil
            manager.isPlaying = false
            return
        }
        guard !preservesUnrecognizedInput else {
            if !didReportUnrecognizedInput {
                didReportUnrecognizedInput = true
                report(Failure.message("保存的播放来源版本未知或已损坏，已保留原数据；请手动选择壁纸。"))
            }
            return
        }
        guard let envelope else { return }
        guard envelope.status == .selection else {
            manager.stopAutoSwitchTimer()
            manager.currentWallpaper = nil
            manager.isPlaying = false
            return
        }
        restore(envelope)
    }

    func onCommitted(_ commit: WallpaperPlaybackSequence.Commit) {
        guard !commit.isRecovery,
              let session = manager.libraryPlaybackSequence.committed,
              session.ticket == commit.ticket, session.reference == commit.reference else { return }
        waiting = false
        manualReplayFailure = nil
        preservesUnrecognizedInput = false
        write(.init(schema: 2, status: .selection, source: session.snapshot.source,
            sourceQuery: session.snapshot.sourceQuery, reference: session.reference,
            userPaused: PlaybackCommandMultiplexer.shared.isUserPaused))
    }

    /// Explicit Stop and exhausted-output Stop persist the stopped selection.
    /// Termination only revokes the original intent and never calls this hook.
    func onStopped() {
        waiting = false
        manualReplayFailure = nil
        let remembered = rememberedReference
        write(.init(schema: 2, status: .stopped, source: envelope?.source,
                    sourceQuery: envelope?.sourceQuery, reference: remembered,
                    userPaused: PlaybackCommandMultiplexer.shared.isUserPaused))
    }

    /// System suspension is deliberately not persisted as a user's pause intent.
    /// Initial publisher delivery before a real session must not erase the saved bit.
    func onUserPauseChanged(_ isPaused: Bool) {
        guard !waiting, manager.libraryPlaybackSequence.committed != nil,
              let envelope, envelope.status == .selection, envelope.userPaused != isPaused else { return }
        write(.init(schema: envelope.schema, status: envelope.status, source: envelope.source,
                    sourceQuery: envelope.sourceQuery, reference: envelope.reference, userPaused: isPaused))
    }

    func onFailed(_ pending: WallpaperPlaybackSequence.Pending) {
        guard let failure = manualReplayFailure, failure.ticket == pending.ticket,
              manager.playbackIntentEpoch == pending.ticket.epoch else { return }
        manualReplayFailure = nil
        report(Failure.message("上次成功播放的壁纸恢复失败，请重新选择壁纸。"))
        failure.notify()
    }

    /// The original reset owner already stops output and clears the media index.
    /// Wait for both its new relationship epoch and a newer source projection.
    func reset() {
        resetBarrier = (lastResetEpoch, latestCatalogRevision)
        waitingIntentEpoch = manager.playbackIntentEpoch
        waiting = true
        envelope = nil
        manualReplayFailure = nil
        preservesUnrecognizedInput = false
        didReportUnrecognizedInput = false
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func requiredProviders(includingStopped: Bool = false) throws -> Set<WallpaperProvider> {
        guard let saved = envelope, saved.status == .selection || includingStopped,
              let reference = saved.reference, let source = saved.source else { return [] }
        let resolved = try? contentResolver(reference)
        let owner = resolved?.providerReference.provider ?? reference.provider
        let targetIsReady = resolved?.publishedAvailability.isAvailable == true
            && resolved?.capabilities.contains(.play) == true && resolved.flatMap({ runtime($0.kind) }) != nil
        if sourceWasDeleted(source) { return targetIsReady ? [] : [owner] }
        var providers: Set<WallpaperProvider>
        switch source {
        case .single: return targetIsReady ? [] : [owner]
        case .global: providers = Set(WallpaperProvider.allCases)
        case .page(let page):
            switch page {
            case .videos: providers = [.videoLibrary]
            case .images: providers = [.staticImageLibrary]
            case .downloads: providers = [.steamWorkshop, .pixabay, .wallhaven, .pixiv]
            default: providers = try dependencyProvider(source, saved.sourceQuery)
            }
            if let filtered = saved.sourceQuery?.providers, !filtered.isEmpty { providers.formIntersection(filtered) }
        }
        if !targetIsReady { providers.insert(owner) }
        return providers
    }

    private func readEnvelope() {
        guard let raw = defaults.object(forKey: Self.storageKey) else { return }
        guard let data = raw as? Data,
              let decoded = try? JSONDecoder().decode(WallpaperPlaybackRestorationEnvelope.self, from: data),
              decoded.isValid else {
            preservesUnrecognizedInput = true
            return
        }
        envelope = decoded
    }

    private func write(_ value: WallpaperPlaybackRestorationEnvelope) {
        guard !preservesUnrecognizedInput, value.isValid else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        envelope = value
        if defaults.data(forKey: Self.storageKey) != data { defaults.set(data, forKey: Self.storageKey) }
    }

    @discardableResult private func restore(_ saved: WallpaperPlaybackRestorationEnvelope, userPaused: Bool? = nil) -> Bool {
        guard let reference = saved.reference, let source = saved.source else { return false }
        let intentEpoch = manager.playbackIntentEpoch
        do {
            guard let content = try playableContent(reference) else {
                report(Failure.message("上次成功播放的壁纸当前不可用，已保留系统画面。"))
                return false
            }
            let target = content.reference
            let snapshot: Snapshot
            if sourceWasDeleted(source) {
                snapshot = try single(content)
            } else if case .single = source {
                snapshot = try single(content)
            } else if let resolved = try snapshotProvider(source, saved.sourceQuery),
                      resolved.source == source, resolved.sourceQuery == normalizedQuery(saved.sourceQuery),
                      resolved.entries.contains(where: { $0.reference == target && $0.isPlayable }) {
                snapshot = resolved
            } else {
                // Removed membership is not authority to choose another member.
                snapshot = try single(content)
            }
            guard manager.playbackIntentEpoch == intentEpoch else { return false }
            applyUserPause(userPaused ?? saved.userPaused)
            guard manager.playbackIntentEpoch == intentEpoch else { return false }
            guard manager.requestLibraryPlayback(reference: target, from: snapshot, cause: .restore) != nil else {
                report(Failure.message("上次成功播放的壁纸恢复失败，已保留系统画面。"))
                return false
            }
            return true
        } catch { report(error); return false }
    }

    private func playableContent(_ reference: WallpaperReference) throws -> WallpaperContentItem? {
        guard let content = try contentResolver(reference), content.publishedAvailability.isAvailable,
              content.capabilities.contains(.play), runtime(content.kind) != nil else { return nil }
        return content
    }

    private func single(_ content: WallpaperContentItem) throws -> Snapshot {
        try Snapshot(source: .single(content.reference), revision: latestCatalogRevision, entries: [entry(content)])
    }

    private func entry(_ content: WallpaperContentItem) -> WallpaperPlaybackSequence.Entry {
        .init(reference: content.reference, runtime: runtime(content.kind), isPlayable: true,
              resourceRevision: content.metadata.resourceRevision)
    }

    private func runtime(_ kind: WallpaperMediaKind) -> WallpaperRuntimeKind? {
        switch kind {
        case .image: return .systemStill
        case .video: return .video
        case .web: return .web
        case .scene: return .scene
        case .unknown: return nil
        }
    }

    private func sourceWasDeleted(_ source: Source) -> Bool {
        if case .page(.playlist(let id)) = source { return !existingPlaylistIDs.contains(id) }
        return false
    }

    private func normalizedQuery(_ query: WallpaperLibraryQueryState?) -> WallpaperLibraryQueryState? {
        guard var query else { return nil }
        query.preferredColumns = 5
        query.scrollAnchor = nil
        query.scrollOffset = nil
        query.scrollAtTop = nil
        return query
    }

    private func applyUserPause(_ paused: Bool) {
        PlaybackCommandMultiplexer.shared.dispatch(paused ? .pause : .resume)
    }
}
