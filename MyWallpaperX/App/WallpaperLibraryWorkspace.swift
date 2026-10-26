import AppKit
import Combine
import Foundation

/// App composition for the one catalog, relationship writer and Shell state.
/// Selection, preparation and output still belong to WallpaperManager; source
/// services retain their media and command lifetimes.
@MainActor final class WallpaperLibraryWorkspace {
    let collections: UserCollectionsController?
    let catalog: WallpaperLibraryCatalogController
    let presentation: WallpaperLibraryPresentation
    let recoveryMessage: String?
    private let manager: WallpaperManager
    private let images: SILService
    private let steam: SteamWorkshopService
    private let online: OnlineLibraryService
    private let readOnlyRelationships: UserCollectionsSnapshot
    private var subscriptions = Set<AnyCancellable>()
    private(set) var projectionRevision: UInt64 = 0
    /// A UI invalidation from the existing transaction owner, independent of
    /// recent-history persistence succeeding or changing the visible page.
    let playbackChanges = PassthroughSubject<Void, Never>()

    private(set) lazy var restoration = WallpaperLibraryPlaybackRestoration(manager: manager, defaults: defaults,
        snapshotProvider: { [weak self] source, query in try self?.restorationSnapshot(source: source, query: query) },
        contentResolver: { [weak self] reference in try self?.playbackContent(for: reference) },
        dependencyProvider: { [weak self] source, query in
            guard let self else { return [] }
            switch source {
            case .page(let page): return try WallpaperLibraryQuery.requiredProviders(page: page, state: query ?? .init(), relationships: self.relationships)
            case .single(let reference): return [(try self.content(for: reference)).providerReference.provider]
            case .global: return Set(WallpaperProvider.allCases)
            }
        }, report: { [weak self] in self?.presentation.report($0) })
    private var personalSettingsReady = true
    private let defaults: UserDefaults

    var relationships: UserCollectionsSnapshot { collections?.snapshot ?? readOnlyRelationships }

    init(startup: LibraryCollectionsStartupOutcome, manager: WallpaperManager,
         images: SILService, steam: SteamWorkshopService, online: OnlineLibraryService, defaults: UserDefaults) {
        self.manager = manager
        self.defaults = defaults
        self.images = images
        self.steam = steam
        self.online = online
        recoveryMessage = startup.recoveryMessage
        readOnlyRelationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
        if case .ready(let publication) = startup {
            collections = UserCollectionsController(store: publication.store, snapshot: publication.snapshot)
        } else { collections = nil }
        catalog = WallpaperLibraryCatalogController(manager: manager, images: images, steam: steam, online: online)
        var migratedQueries: [WallpaperLibraryPage: WallpaperLibraryQueryState] = [:]
        var preferenceWarnings: [String] = []
        if defaults.object(forKey: WallpaperLibraryPresentation.settingsKey) == nil, case .ready(let publication) = startup {
            if let seed = publication.viewPreferencesSeed {
                let mapped = WallpaperLibraryViewPreferencesMigration.map(seed, relationships: collections?.snapshot ?? readOnlyRelationships)
                migratedQueries = mapped.queries
                if !mapped.warnings.isEmpty { preferenceWarnings.append("部分旧版界面偏好无法恢复：" + mapped.warnings.joined(separator: "、")) }
            }
            if let warning = publication.viewPreferencesWarning { preferenceWarnings.append(warning) }
        }
        presentation = WallpaperLibraryPresentation(collections: collections, defaults: defaults,
            migratedQueries: migratedQueries, migrationWarning: preferenceWarnings.isEmpty ? nil : preferenceWarnings.joined(separator: "\n"))
        // Initial empty projections are a loading state. Relationship-only
        // pages can already retain their unavailable members and names.
        _ = presentation.update(catalog: catalog.catalog, relationships: relationships, relationshipsKnown: collections != nil)
        // Capture the launch intent before any delayed source publication or
        // first user action can arrive; a lazy first use would capture too late.
        _ = restoration
        installPlaybackBindings()
        PlaybackCommandMultiplexer.shared.pauseSnapshots.map(\.isUserPaused).removeDuplicates()
            .sink { [weak self] in self?.restoration.onUserPauseChanged($0) }.store(in: &subscriptions)
        if let collections {
            catalog.$catalog.combineLatest(collections.$snapshot)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] catalog, relationships in self?.acceptProjection(catalog, relationships: relationships) }
                .store(in: &subscriptions)
        } else {
            catalog.$catalog.receive(on: DispatchQueue.main).sink { [weak self] catalog in
                guard let self else { return }
                self.acceptProjection(catalog, relationships: self.readOnlyRelationships)
            }.store(in: &subscriptions)
        }
    }

    private func acceptProjection(_ catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot) {
        guard presentation.update(catalog: catalog, relationships: relationships, relationshipsKnown: collections != nil) else { return }
        projectionRevision &+= 1
        refreshPlaybackAvailability()
        restoration.updateInitialReadiness(loadedProviders: catalog.loadedProviders,
            existingPlaylistIDs: Set(relationships.playlists.map(\.id)), resetEpoch: relationships.resetEpoch,
            relationshipsReady: collections != nil && personalSettingsReady, catalogRevision: catalog.revision)
    }

    func setPersonalSettingsReady(_ ready: Bool) {
        personalSettingsReady = ready
        presentation.setEditingAllowed(ready)
        restoration.updateInitialReadiness(loadedProviders: catalog.catalog.loadedProviders,
            existingPlaylistIDs: Set(relationships.playlists.map(\.id)), resetEpoch: relationships.resetEpoch,
            relationshipsReady: collections != nil && ready, catalogRevision: catalog.catalog.revision)
    }

    private func installPlaybackBindings() {
        manager.libraryPlaybackPendingChanged = { [weak self] in self?.playbackChanges.send() }
        let onlineImages = OnlineImageLibrary.shared
        onlineImages.requestLibraryPlayback = { [weak self] reference in self?.requestSingle(reference) }
        onlineImages.captureApplyIntent = { [weak self] in
            guard let self else { return { false } }
            let token = ImportedVideoAutoplayGate.shared.claim()
            let epoch = self.manager.playbackIntentEpoch
            return { [weak self] in
                guard let self else { return false }
                return self.manager.playbackIntentEpoch == epoch && ImportedVideoAutoplayGate.shared.isCurrent(token)
            }
        }
        onlineImages.isFileInUse = { [weak self] path in
            guard let self else { return true }
            if self.manager.isLocalSourceFileInUse(path) { return true }
            let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return true }
            return screens.contains { screen in
                guard let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return true }
                return current.standardizedFileURL.resolvingSymlinksInPath() == target
            }
        }
        manager.libraryPlaybackSnapshotProvider = { [weak self] reference, source, cause in
            self?.playbackSnapshot(reference: reference, source: source, cause: cause)
        }
        manager.libraryPlaybackDispatcher = { [weak self] pending in
            guard let self, let content = try? self.playbackContent(for: pending.proposal.entry.reference) else { return false }
            return WallpaperLibraryPlaybackRouting.dispatch(pending, content: content, manager: self.manager,
                workshop: self.steam, online: self.online, images: self.images, relationships: self.relationships)
        }
        manager.libraryPlaybackCommitted = { [weak self] commit in
            guard let self else { return }
            // A provenance receipt can have canonicalized aliases while this
            // immutable ticket was preparing. Refresh its fixed identities
            // before the next scheduling boundary, even if metadata I/O fails.
            self.refreshPlaybackAvailability()
            self.playbackChanges.send()
            self.restoration.onCommitted(commit)
            guard commit.shouldRecordRecent else { return }
            self.collections?.recordSuccessfulUse(commit.reference,
                locator: (try? self.content(for: commit.reference))?.locator, sequence: commit.ticket.epoch)
        }
        manager.libraryPlaybackStopped = { [weak self] in self?.restoration.onStopped(); self?.playbackChanges.send() }
        manager.libraryPlaybackFailed = { [weak self] in self?.restoration.onFailed($0); self?.playbackChanges.send() }
        manager.libraryPlaybackResetRequested = { [weak self] in self?.restoration.reset() }
        manager.libraryBackingPublished = { [weak self] publication in self?.acceptBacking(publication) }
    }

    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        try WallpaperLibraryQuery.resolve([reference], catalog: catalog.catalog, relationships: relationships)[0]
    }

    private func playbackContent(for reference: WallpaperReference) throws -> WallpaperContentItem {
        let projected = try content(for: reference)
        if projected.capabilities.contains(.play) { return projected }
        let immediate: WallpaperContentItem?
        let canonical = projected.reference
        switch canonical.provider {
        case .steamWorkshop: immediate = steam.libraryContentItemForExplicitPlayback(id: canonical.sourceID)
        case .pixabay: immediate = Int(canonical.sourceID).flatMap { id in
            String(id).utf8.elementsEqual(canonical.sourceID.utf8) ? online.libraryContentItemForExplicitPlayback(id: id) : nil
        }
        case .wallhaven, .pixiv: immediate = OnlineImageLibrary.shared.content(for: canonical)
        default: immediate = nil
        }
        guard let immediate else { return projected }
        return try WallpaperLibraryQuery.resolve([reference],
            catalog: WallpaperLibraryCatalog(downloads: [immediate]), relationships: relationships)[0]
    }

    /// Original source buttons request one explicit local item; browsing does
    /// not lend that action a previous page's playlist or change its membership.
    func requestSingle(_ reference: WallpaperReference) {
        do {
            let target = try playbackContent(for: reference)
            let snapshot = try makeSnapshot(source: .single(target.reference), items: [target], query: nil)
            guard manager.requestLibraryPlayback(reference: target.reference, from: snapshot, cause: .userSelection) != nil else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "壁纸当前不可用，请定位文件或重新下载。"])
            }
        } catch { presentation.report(error) }
    }

    func isFavorite(_ reference: WallpaperReference) -> Bool {
        guard let item = try? content(for: reference) else { return false }
        return relationships.favorites.contains { $0.reference == item.reference }
    }

    func isPlaying(_ reference: WallpaperReference) -> Bool {
        guard let current = manager.libraryPlaybackSequence.committed,
              manager.playbackSwitch.committed?.ticket == current.ticket,
              let currentContent = try? content(for: current.reference), let target = try? content(for: reference) else { return false }
        return currentContent.reference == target.reference
    }

    /// The displayed ordered/filter result is captured only by an explicit
    /// action. Merely navigating to a page never changes a running source.
    func capturePlaybackSnapshot(for reference: WallpaperReference,
        resolvedProjection: (catalogRevision: UInt64, relationshipsRevision: Int64, resetEpoch: UUID, items: [WallpaperContentItem])? = nil
    ) throws -> WallpaperPlaybackSequence.Snapshot {
        let page = presentation.page
        if page.isRemoteBrowse {
            let target = try content(for: reference)
            return try makeSnapshot(source: .single(target.reference), items: [target], query: nil)
        }
        let values: [WallpaperContentItem]
        if let resolvedProjection, resolvedProjection.catalogRevision == catalog.catalog.revision,
           resolvedProjection.relationshipsRevision == relationships.revision,
           resolvedProjection.resetEpoch == relationships.resetEpoch {
            values = resolvedProjection.items
        } else {
            values = try WallpaperLibraryQuery.resolve(presentation.queryResult.items.map(\.reference),
                catalog: catalog.catalog, relationships: relationships)
        }
        return try makeSnapshot(source: .page(page), items: values, query: presentation.queryState)
    }

    func play(_ reference: WallpaperReference, from captured: WallpaperPlaybackSequence.Snapshot? = nil,
              cause: WallpaperPlaybackCause = .userSelection) {
        do {
            let target = try content(for: reference)
            let snapshot = try captured ?? capturePlaybackSnapshot(for: reference)
            let requested = snapshot.entries.contains(where: { $0.reference == reference }) ? reference : target.reference
            guard manager.requestLibraryPlayback(reference: requested, from: snapshot, cause: cause) != nil else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "壁纸当前不可用，请定位文件或重新下载。"])
            }
        } catch { presentation.report(error) }
    }

    private func playbackSnapshot(reference: WallpaperReference?, source: WallpaperPlaybackSequence.Source,
                                  cause: WallpaperPlaybackCause) -> WallpaperPlaybackSequence.Snapshot? {
        do {
            switch source {
            case .single:
                guard let reference else { return nil }
                let item = try playbackContent(for: reference)
                return try makeSnapshot(source: .single(item.reference), items: [item], query: nil)
            case .global:
                guard catalog.catalog.loadedProviders == Set(WallpaperProvider.allCases) else { return nil }
                let values = try [WallpaperLibraryPage.videos, .images, .downloads].flatMap {
                    try WallpaperLibraryQuery.project(page: $0, state: .init(), catalog: catalog.catalog,
                        relationships: relationships).items
                }
                return try makeSnapshot(source: .global, items: values, query: nil)
            case .page(let page):
                let query: WallpaperLibraryQueryState
                if cause == .userSelection, presentation.page == page { query = presentation.queryState }
                else if let session = manager.libraryPlaybackSequence.committed, session.snapshot.source == source,
                        let captured = session.snapshot.sourceQuery { query = captured }
                else { return nil }
                let result = try WallpaperLibraryQuery.project(page: page, state: query, catalog: catalog.catalog,
                    relationships: relationships)
                return try makeSnapshot(source: source, items: result.items, query: query)
            }
        } catch { presentation.report(error); return nil }
    }

    private func restorationSnapshot(source: WallpaperPlaybackSequence.Source,
                                     query: WallpaperLibraryQueryState?) throws -> WallpaperPlaybackSequence.Snapshot? {
        switch source {
        case .single(let reference):
            let item = try playbackContent(for: reference)
            return try makeSnapshot(source: .single(item.reference), items: [item], query: nil)
        case .page(let page):
            guard let query else { return nil }
            let values = try WallpaperLibraryQuery.project(page: page, state: query, catalog: catalog.catalog,
                                                          relationships: relationships).items
            return try makeSnapshot(source: source, items: values, query: query)
        case .global:
            return playbackSnapshot(reference: nil, source: .global, cause: .restore)
        }
    }

    private func makeSnapshot(source: WallpaperPlaybackSequence.Source, items: [WallpaperContentItem],
                              query: WallpaperLibraryQueryState?, preserving original: WallpaperPlaybackSequence.Snapshot? = nil,
                              preferredReference: WallpaperReference? = nil) throws -> WallpaperPlaybackSequence.Snapshot {
        var stableReferences: [WallpaperReference: WallpaperReference] = [:]
        var previousEntries: [WallpaperReference: WallpaperPlaybackSequence.Entry] = [:]
        if let original {
            let canonical = try WallpaperLibraryQuery.canonicalReferences(Set(original.entries.map(\.reference)), relationships: relationships)
            for entry in original.entries {
                previousEntries[entry.reference] = entry
                if let resolved = canonical[entry.reference], stableReferences[resolved] == nil { stableReferences[resolved] = entry.reference }
            }
            if let preferredReference, let resolved = canonical[preferredReference] { stableReferences[resolved] = preferredReference }
        }
        let entries = items.map { item in
            let reference = stableReferences[item.reference] ?? item.reference
            if !catalog.catalog.loadedProviders.contains(item.providerReference.provider),
               !item.publishedAvailability.isAvailable,
               let previous = previousEntries[reference] {
                // Absence before a source's first completed projection is
                // unknown, not an authoritative disappearance of this ticket.
                return previous
            }
            let runtime: WallpaperRuntimeKind?
            switch item.kind {
            case .video: runtime = .video
            case .image: runtime = .systemStill
            case .web: runtime = .web
            case .scene: runtime = .scene
            case .unknown: runtime = nil
            }
            return WallpaperPlaybackSequence.Entry(reference: reference, runtime: runtime,
                isPlayable: item.capabilities.contains(.play) && runtime != nil,
                resourceRevision: item.metadata.resourceRevision)
        }
        return try WallpaperPlaybackSequence.Snapshot(source: source, revision: projectionRevision,
            entries: entries, sourceQuery: query)
    }

    private var capturedPlaybackSources: [(snapshot: WallpaperPlaybackSequence.Snapshot, ticket: PlaybackSwitchTicket, reference: WallpaperReference)] {
        var result: [(WallpaperPlaybackSequence.Snapshot, PlaybackSwitchTicket, WallpaperReference)] = []
        if let committed = manager.libraryPlaybackSequence.committed { result.append((committed.snapshot, committed.ticket, committed.reference)) }
        if let pending = manager.libraryPlaybackSequence.pending { result.append((pending.proposal.snapshot, pending.ticket, pending.proposal.entry.reference)) }
        return result
    }

    private func refreshPlaybackAvailability() {
        for captured in capturedPlaybackSources {
            let original = captured.snapshot
            do {
                let current = try WallpaperLibraryQuery.resolve(original.entries.map(\.reference),
                    catalog: catalog.catalog, relationships: relationships)
                let updated = try makeSnapshot(source: original.source, items: current, query: original.sourceQuery,
                    preserving: original, preferredReference: captured.reference)
                manager.updateLibraryPlaybackSource(updated, reason: .availability, targetTicket: captured.ticket)
            } catch { presentation.report(error) }
        }
    }

    /// Explicit organization commands call this after their transaction. Recent
    /// success publications themselves never reorder a running recent snapshot.
    func didEditMembers(of page: WallpaperLibraryPage, deleted: Bool = false) {
        let source = WallpaperPlaybackSequence.Source.page(page)
        for captured in capturedPlaybackSources where captured.snapshot.source == source {
            let original = captured.snapshot
            do {
                if deleted {
                    let removal = try WallpaperPlaybackSequence.Snapshot(source: original.source, revision: projectionRevision,
                        entries: original.entries, sourceQuery: original.sourceQuery)
                    manager.updateLibraryPlaybackSource(removal, reason: .sourceDeleted, targetTicket: captured.ticket)
                    continue
                }
                guard let query = original.sourceQuery else { continue }
                let result = try WallpaperLibraryQuery.project(page: page, state: query, catalog: catalog.catalog,
                    relationships: relationships)
                let updated = try makeSnapshot(source: source, items: result.items, query: query, preserving: original, preferredReference: captured.reference)
                manager.updateLibraryPlaybackSource(updated, reason: .explicitMembers, targetTicket: captured.ticket)
            } catch { presentation.report(error) }
        }
    }

    func didRestoreOrganization() {
        let snapshots = [manager.libraryPlaybackSequence.committed?.snapshot,
                         manager.libraryPlaybackSequence.pending?.proposal.snapshot].compactMap { $0 }
        var visited = Set<WallpaperLibraryPage>()
        for snapshot in snapshots {
            guard case .page(let page) = snapshot.source, visited.insert(page).inserted else { continue }
            let deleted: Bool
            if case .playlist(let id) = page { deleted = !relationships.playlists.contains { $0.id == id } }
            else { deleted = false }
            didEditMembers(of: page, deleted: deleted)
        }
    }

    private func acceptBacking(_ publication: WallpaperContentBackingPublication) {
        guard let collections, !collections.isResetting, let alias = publication.alias else { return }
        let epoch = collections.snapshot.resetEpoch
        Task { @MainActor [weak self, weak collections] in
            guard let self, let collections, !collections.isResetting, collections.snapshot.resetEpoch == epoch else { return }
            do {
                let canonical = try WallpaperLibraryQuery.canonicalReferences([alias.alias, alias.canonical],
                    relationships: collections.snapshot)
                guard let previous = canonical[alias.alias], previous == alias.alias || previous == alias.canonical,
                      canonical[alias.canonical] == alias.canonical else { throw UserCollectionsError.migrationConflict }
                if previous == alias.canonical { return }
                _ = try await collections.perform(.linkAlias(alias, Date()), expectedEpoch: epoch)
            } catch {
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.presentation.report(error)
            }
        }
    }

    func refreshSources() {
        steam.reloadInstalledItems()
        catalog.refreshAvailability()
    }

    func flush() async -> String? { await collections?.flush() }
}
