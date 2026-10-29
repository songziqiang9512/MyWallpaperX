import Foundation

private nonisolated struct WallpaperPlaybackRestorationEnvelope: Codable, Equatable {
    enum Status: String, Codable { case selection, stopped }
    let schema: Int
    let status: Status
    let source: WallpaperPlaybackSequence.Source?
    let sourceQuery: WallpaperLibraryQueryState?
    let reference: WallpaperReference?
    let userPaused: Bool
    var legacyAdmission: Bool? = nil

    var isValid: Bool {
        guard schema == 1 else { return false }
        if legacyAdmission == true {
            guard status == .selection, let source, case .single = source, sourceQuery == nil else { return false }
        }
        switch status {
        case .stopped where source == nil && sourceQuery == nil && reference == nil: return true
        case .selection, .stopped:
            guard let source, let reference, !reference.sourceID.isEmpty else { return false }
            switch source {
            case .single(let value): return value == reference && sourceQuery == nil
            case .global: return sourceQuery == nil
            case .page(let page): return !page.isRemoteBrowse && page != .playlists
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
    private var legacyReplayReference: WallpaperReference?
    private var legacyFallbackAvailable = false
    private var legacyRememberedReference: WallpaperReference?
    private var loadedProviders = Set<WallpaperProvider>()
    private var relationshipsReady = false
    private var manualReplayFailure: (ticket: PlaybackSwitchTicket, notify: () -> Void)?

    /// The same saved success descriptor serves manual replay. A stopped
    /// descriptor retains identity without granting automatic launch admission.
    var rememberedReference: WallpaperReference? {
        guard !preservesUnrecognizedInput else { return nil }
        if let envelope { return envelope.reference }
        return legacyRememberedReference
    }

    init(manager: WallpaperManager, defaults: UserDefaults,
         snapshotProvider: @escaping (Source, WallpaperLibraryQueryState?) throws -> Snapshot?,
         contentResolver: @escaping (WallpaperReference) throws -> WallpaperContentItem?,
         dependencyProvider: @escaping (Source, WallpaperLibraryQueryState?) throws -> Set<WallpaperProvider> = { _, _ in Set(WallpaperProvider.allCases) },
         report: @escaping (Error) -> Void = { _ in }) {
        self.manager = manager
        self.defaults = defaults
        self.snapshotProvider = snapshotProvider
        self.contentResolver = contentResolver
        self.dependencyProvider = dependencyProvider
        self.report = report
        if (manager.activeWallpaperRuntime == .web || manager.activeWallpaperRuntime == .scene),
           let id = manager.lastWorkshopPlaybackRecordID, !id.isEmpty {
            legacyRememberedReference = .init(provider: .steamWorkshop, sourceID: id)
        } else if manager.activeWallpaperRuntime == .video, let video = manager.currentWallpaper {
            legacyRememberedReference = .init(provider: .videoLibrary, sourceID: video.id)
        } else { legacyRememberedReference = nil }
        waitingIntentEpoch = manager.playbackIntentEpoch
        readEnvelope()
        if envelope == nil, !preservesUnrecognizedInput, let reference = legacyRememberedReference {
            // Preserve the old success before launch-off clears CurrentWallpaper.
            // The explicit migration bit retains only the original first-upgrade
            // auto-replay policy; a real commit/Stop clears that admission.
            write(.init(schema: 1, status: .selection, source: .single(reference), sourceQuery: nil,
                        reference: reference, userPaused: legacyUserPaused, legacyAdmission: true))
        }
    }

    @discardableResult func resumeLastSelection(onFailure: @escaping () -> Void = {}) -> Bool {
        guard manager.playbackSwitch.committed == nil, manager.playbackSwitch.pending == nil,
              manager.libraryPlaybackSequence.pending == nil,
              let reference = rememberedReference else { return false }
        do {
            guard relationshipsReady, try requiredProviders(allowLegacyFallback: false).isSubset(of: loadedProviders) else {
                report(Failure.message("资料库仍在载入，请稍后重试。"))
                return false
            }
        } catch { report(error); return false }
        waiting = false
        manualReplayFailure = nil
        let saved = envelope ?? .init(schema: 1, status: .selection, source: .single(reference),
                                     sourceQuery: nil, reference: reference, userPaused: false)
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
            do { if try !requiredProviders().isSubset(of: loadedProviders) { return } }
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
        if let envelope {
            guard envelope.status == .selection else {
                manager.stopAutoSwitchTimer()
                manager.currentWallpaper = nil
                manager.isPlaying = false
                return
            }
            if envelope.legacyAdmission == true { restoreLegacy() }
            else { restore(envelope) }
        } else {
            // Absence of the new descriptor is the sole legacy admission.
            // A new empty/deleted source, Stop or corrupt descriptor never uses it.
            restoreLegacy()
        }
    }

    func onCommitted(_ commit: WallpaperPlaybackSequence.Commit) {
        guard !commit.isRecovery,
              let session = manager.libraryPlaybackSequence.committed,
              session.ticket == commit.ticket, session.reference == commit.reference else { return }
        waiting = false
        manualReplayFailure = nil
        legacyReplayReference = nil
        legacyFallbackAvailable = false
        write(.init(schema: 1, status: .selection, source: session.snapshot.source,
            sourceQuery: session.snapshot.sourceQuery, reference: session.reference,
            userPaused: PlaybackCommandMultiplexer.shared.isUserPaused))
    }

    /// Explicit Stop and exhausted-output Stop persist the stopped selection.
    /// Termination only revokes the original intent and never calls this hook.
    func onStopped() {
        waiting = false
        manualReplayFailure = nil
        legacyReplayReference = nil
        legacyFallbackAvailable = false
        let remembered = rememberedReference
        write(.init(schema: 1, status: .stopped, source: envelope?.source ?? remembered.map { .single($0) },
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

    /// Only the admitted first-upgrade workshop replay has a video fallback.
    /// The Manager has already settled the failed ticket before this callback.
    func onFailed(_ pending: WallpaperPlaybackSequence.Pending) {
        if let failure = manualReplayFailure, failure.ticket == pending.ticket,
           manager.playbackIntentEpoch == pending.ticket.epoch {
            manualReplayFailure = nil
            report(Failure.message("上次成功播放的壁纸恢复失败，请重新选择壁纸。"))
            failure.notify()
            return
        }
        guard legacyFallbackAvailable, pending.proposal.cause == .restore,
              legacyReplayReference == pending.proposal.entry.reference,
              manager.playbackIntentEpoch == pending.ticket.epoch else { return }
        legacyReplayReference = nil
        legacyFallbackAvailable = false
        restoreLegacyVideo(userPaused: PlaybackCommandMultiplexer.shared.isUserPaused)
    }

    /// The original reset owner already stops output and clears the media index.
    /// Wait for both its new relationship epoch and a newer source projection.
    func reset() {
        resetBarrier = (lastResetEpoch, latestCatalogRevision)
        waitingIntentEpoch = manager.playbackIntentEpoch
        waiting = true
        legacyReplayReference = nil
        legacyFallbackAvailable = false
        envelope = nil
        manualReplayFailure = nil
        legacyRememberedReference = nil
        preservesUnrecognizedInput = false
        didReportUnrecognizedInput = false
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func requiredProviders(allowLegacyFallback: Bool = true) throws -> Set<WallpaperProvider> {
        if let saved = envelope, saved.legacyAdmission != true || !allowLegacyFallback {
            guard saved.status == .selection || !allowLegacyFallback,
                  let reference = saved.reference, let source = saved.source else { return [] }
            let resolved = try? contentResolver(reference)
            let owner = resolved?.providerReference.provider ?? reference.provider
            let targetIsReady = resolved?.publishedAvailability.isAvailable == true
                && resolved?.capabilities.contains(.play) == true && resolved.flatMap({ runtime($0.kind) }) != nil
            if sourceWasDeleted(source) || isPageWithoutQuery(source, saved.sourceQuery) {
                return targetIsReady ? [] : [owner]
            }
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
        guard manager.activeWallpaperRuntime != .systemStill else { return [] }
        var providers: Set<WallpaperProvider> = [.videoLibrary]
        for video in manager.wallpapers {
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: video.id)
            let owner = (try? contentResolver(reference))?.providerReference.provider ?? .videoLibrary
            providers.insert(owner)
        }
        if manager.activeWallpaperRuntime == .web || manager.activeWallpaperRuntime == .scene,
           let id = manager.lastWorkshopPlaybackRecordID, !id.isEmpty {
            let reference = WallpaperReference(provider: .steamWorkshop, sourceID: id)
            let content = try? contentResolver(reference)
            if content?.publishedAvailability.isAvailable != true || content?.capabilities.contains(.play) != true {
                providers.insert(.steamWorkshop)
            }
        }
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
            if sourceWasDeleted(source) || isPageWithoutQuery(source, saved.sourceQuery) {
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

    private var legacyUserPaused: Bool {
        defaults.object(forKey: manager.playbackStateKey) != nil && !defaults.bool(forKey: manager.playbackStateKey)
    }

    private func restoreLegacy() {
        let intentEpoch = manager.playbackIntentEpoch
        let paused: Bool
        if let envelope, envelope.legacyAdmission == true { paused = envelope.userPaused }
        else { paused = legacyUserPaused }
        if manager.activeWallpaperRuntime == .web || manager.activeWallpaperRuntime == .scene,
           let id = manager.lastWorkshopPlaybackRecordID, !id.isEmpty {
            do {
                let reference = WallpaperReference(provider: .steamWorkshop, sourceID: id)
                if let content = try playableContent(reference),
                   (manager.activeWallpaperRuntime == .web && content.kind == .web)
                    || (manager.activeWallpaperRuntime == .scene && content.kind == .scene) {
                    let snapshot = try single(content)
                    guard manager.playbackIntentEpoch == intentEpoch else { return }
                    legacyReplayReference = content.reference
                    legacyFallbackAvailable = true
                    applyUserPause(paused)
                    guard manager.playbackIntentEpoch == intentEpoch else {
                        legacyReplayReference = nil
                        legacyFallbackAvailable = false
                        return
                    }
                    let ticket = manager.requestLibraryPlayback(reference: content.reference, from: snapshot, cause: .restore)
                    // A synchronous provider failure may already have run onFailed.
                    if ticket == nil, legacyFallbackAvailable {
                        legacyReplayReference = nil
                        legacyFallbackAvailable = false
                        restoreLegacyVideo(userPaused: paused)
                    }
                    return
                }
            } catch { report(error) }
        } else if manager.activeWallpaperRuntime == .systemStill {
            // The old format had no image identity. Preserve the OS wallpaper.
            return
        }
        guard manager.playbackIntentEpoch == intentEpoch else { return }
        restoreLegacyVideo(userPaused: paused)
    }

    private func restoreLegacyVideo(userPaused: Bool) {
        let intentEpoch = manager.playbackIntentEpoch
        do {
            // Only rows in the original authoritative in-memory index are eligible.
            // No snapshot upsert, path matching, SQLite reread or library expansion.
            var candidates: [WallpaperContentItem] = []
            var seen = Set<WallpaperReference>()
            for video in manager.wallpapers {
                if let content = try playableContent(.init(provider: .videoLibrary, sourceID: video.id)),
                   content.kind == .video, seen.insert(content.reference).inserted { candidates.append(content) }
            }
            var preferred: [WallpaperReference] = []
            let migrated = envelope?.legacyAdmission == true ? envelope?.reference : nil
            let savedVideo = migrated?.provider == .videoLibrary ? migrated
                : manager.currentWallpaper.map { WallpaperReference(provider: .videoLibrary, sourceID: $0.id) }
            if manager.activeWallpaperRuntime == .video, let savedVideo,
               manager.wallpapers.contains(where: { $0.id.utf8.elementsEqual(savedVideo.sourceID.utf8) }),
               let content = try playableContent(savedVideo) {
                preferred.append(content.reference)
            }
            // Migration already captured the legacy history before source
            // cleanup. Reuse its sole Store projection, restricted to the same
            // authoritative Video index candidates; history cannot upsert files.
            if let recent = try snapshotProvider(.page(.recent), nil) {
                let eligible = Set(candidates.map(\.reference))
                preferred.append(contentsOf: recent.entries.map(\.reference).filter { eligible.contains($0) })
            }
            guard let target = preferred.first(where: { id in candidates.contains(where: { $0.reference == id }) })
                ?? candidates.first?.reference else { return }
            let snapshot = try Snapshot(source: .global, revision: latestCatalogRevision, entries: candidates.map(entry))
            guard manager.playbackIntentEpoch == intentEpoch else { return }
            applyUserPause(userPaused)
            guard manager.playbackIntentEpoch == intentEpoch else { return }
            if manager.requestLibraryPlayback(reference: target, from: snapshot, cause: .restore) == nil {
                report(Failure.message("旧版视频播放状态恢复失败；请手动选择壁纸。"))
            }
        } catch { report(error) }
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

    private func isPageWithoutQuery(_ source: Source, _ query: WallpaperLibraryQueryState?) -> Bool {
        if case .page = source { return query == nil }
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
