import Combine
import Foundation

nonisolated struct WallpaperLibraryPresentationState: Sendable {
    var page: WallpaperLibraryPage = .videos
    var query = WallpaperLibraryQueryState()
    var queryResult = WallpaperLibraryPageResult(items: [], unfilteredCount: 0)
    var directoryEntries: [WallpaperPlaylistDirectoryEntry] = []
    var selectionState = WallpaperLibrarySelectionState()
    var directoryScrollAnchor: UUID?
    var directoryScrollOffset: Double?
    var directoryScrollAtTop: Bool?
    var lastError: String?
    var lastErrorEvent: UInt64 = 0
    var allowsEditing = true
}

/// Organization may finish after source projection or user navigation. This
/// receipt identifies only the original selection intent, never source truth.
nonisolated struct WallpaperLibrarySelectionReceipt: Sendable {
    fileprivate let id = UUID()
}

/// Page navigation and view sessions only. Catalog/relationships arrive from
/// their existing owners; browsing never changes the playback source or output.
@MainActor final class WallpaperLibraryPresentation: ObservableObject {
    static let settingsKey = "wallpaperLibraryPresentation.v1"
    /// Consumers subscribe to this value once, never assemble several publishers.
    @Published private(set) var state = WallpaperLibraryPresentationState()
    var page: WallpaperLibraryPage { state.page }
    var queryState: WallpaperLibraryQueryState { state.query }
    var queryResult: WallpaperLibraryPageResult { state.queryResult }
    var directoryEntries: [WallpaperPlaylistDirectoryEntry] { state.directoryEntries }
    var selectionState: WallpaperLibrarySelectionState { state.selectionState }
    var lastError: String? { state.lastError }
    var directoryScrollAnchor: UUID? { state.directoryScrollAnchor }
    var directoryScrollOffset: Double? { state.directoryScrollOffset }
    var directoryScrollAtTop: Bool? { state.directoryScrollAtTop }
    /// Type facets share the exact page/search/provider/status contract. The
    /// active type is removed only for these counts; no source owner is read.
    var mediaKindCounts: [WallpaperMediaKind: Int] {
        guard let catalog, let relationships else { return [:] }
        var query = queryState
        query.kind = nil
        query.sort = .sourceOrder
        guard let result = try? WallpaperLibraryQuery.project(page: page, state: query, catalog: catalog, relationships: relationships) else { return [:] }
        return result.items.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }
    /// The injected relationship writer. Recovery can browse without one.
    let collections: UserCollectionsController?
    var canEditCollections: Bool { state.allowsEditing && collections != nil && collections?.isResetting == false }
    var permitsDirectoryReordering: Bool {
        page == .playlists && queryState.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct Session {
        var query = WallpaperLibraryQueryState()
        var selection = WallpaperLibrarySelectionState()
    }
    private struct PendingSelectionOperation {
        let page: WallpaperLibraryPage
        let resetEpoch: UUID
        let displayed: [WallpaperReference]
        let targets: Set<WallpaperReference>
        let selection: WallpaperLibrarySelectionState
        let waitsForRemoval: Bool
        var expectedSessionID: UUID
        var succeeded: Set<WallpaperReference>?
    }
    private struct SavedQuery: Codable {
        let page: WallpaperLibraryPage
        let query: WallpaperLibraryQueryState
        let wasSubscriptions: Bool
        private enum CodingKeys: String, CodingKey { case page, query }
        private enum LegacyPageKey: String, CodingKey { case workshopSubscriptions }
        init(page: WallpaperLibraryPage, query: WallpaperLibraryQueryState) {
            self.page = page; self.query = query; wasSubscriptions = false
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let pageDecoder = try values.superDecoder(forKey: .page)
            wasSubscriptions = try pageDecoder.container(keyedBy: LegacyPageKey.self).contains(.workshopSubscriptions)
            page = try WallpaperLibraryPage(from: pageDecoder)
            var restored = try values.decode(WallpaperLibraryQueryState.self, forKey: .query)
            if page == .downloads, restored.status == .transferring || restored.status == .failed { restored.status = .all }
            query = restored
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(page, forKey: .page)
            try values.encode(query, forKey: .query)
        }
    }
    private struct SavedState: Codable {
        let version: Int
        let page: WallpaperLibraryPage
        let queries: [SavedQuery]
        let directoryScrollAnchor: UUID?
        let directoryScrollOffset: Double?
        let directoryScrollAtTop: Bool?
    }
    private let defaults: UserDefaults
    private var sessions: [WallpaperLibraryPage: Session] = [:]
    private var mayWriteSettings = true
    private var lastSavedData: Data?
    private var settingsError: String?
    private var catalog: WallpaperLibraryCatalog?
    var relationshipsRevision: Int64? { relationships?.revision }
    private var relationships: UserCollectionsSnapshot?
    private var relationshipsKnown = true
    private var pendingRemovals: [UUID: PendingSelectionOperation] = [:]

    init(collections: UserCollectionsController?, defaults: UserDefaults,
         migratedQueries: [WallpaperLibraryPage: WallpaperLibraryQueryState] = [:], migrationWarning: String? = nil) {
        self.collections = collections
        self.defaults = defaults
        if defaults.object(forKey: Self.settingsKey) == nil {
            sessions = migratedQueries.mapValues { Session(query: $0) }
            var next = state
            next.query = sessions[next.page]?.query ?? .init()
            next.lastError = migrationWarning
            state = next
            settingsError = migrationWarning
        } else { restoreSettings() }
    }

    /// A failed query leaves the last valid page, items and relationship input
    /// intact. An empty successful result is therefore distinct from failure.
    @discardableResult
    func update(catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot, relationshipsKnown: Bool = true) -> Bool {
        // Queued Combine deliveries cannot replace a later accepted fact with
        // an older snapshot, including one from before a deletion or reset.
        if let previous = self.catalog, catalog.revision < previous.revision { return false }
        if let previous = self.relationships, relationships.revision < previous.revision { return false }
        var nextPage = page
        if relationshipsKnown, case .playlist(let id) = page, !relationships.playlists.contains(where: { $0.id == id }) {
            nextPage = .playlists
        }
        do {
            var nextSessions = sessions
            let didReset = self.relationships.map { $0.resetEpoch != relationships.resetEpoch } ?? false
            if didReset {
                // The store's reset epoch is the existing authority. Revoke
                // every view receipt, including remote pages, before any late
                // catalog can make an old reference visible again.
                for key in Array(nextSessions.keys) {
                    nextSessions[key]?.selection = WallpaperLibrarySelectionState()
                    nextSessions[key]?.query.scrollAnchor = nil
                    nextSessions[key]?.query.scrollOffset = nil
                    nextSessions[key]?.query.scrollAtTop = nil
                }
            }
            let query = nextSessions[nextPage]?.query ?? .init()
            let result = try project(page: nextPage, query: query, catalog: catalog, relationships: relationships, relationshipsKnown: relationshipsKnown)
            let entries = nextPage == .playlists ? try WallpaperLibraryQuery.directory(state: query, catalog: catalog, relationships: relationships) : nil
            var session = nextSessions[nextPage] ?? Session()
            let previousSessionID = session.selection.sessionID
            try reconcile(&session, page: nextPage, items: result.items, relationships: relationships)
            if nextPage != page { session.selection.sessionID = UUID() }
            if didReset || nextPage != page { pendingRemovals.removeAll() }
            else { advanceRemovalSessions(page: nextPage, from: previousSessionID, to: session.selection.sessionID) }
            try settleRemovals(in: &session, page: nextPage, items: result.items, catalog: catalog, relationships: relationships)
            self.catalog = catalog
            self.relationships = relationships
            self.relationshipsKnown = relationshipsKnown
            let liveIDs = Set(relationships.playlists.map(\.id))
            sessions = nextSessions.filter { key, _ in
                if relationshipsKnown, case .playlist(let id) = key { return liveIDs.contains(id) }
                return true
            }
            let anchor = didReset ? nil : relationshipsKnown ? directoryScrollAnchor.flatMap { liveIDs.contains($0) ? $0 : nil } : directoryScrollAnchor
            let removedAnchor = directoryScrollAnchor != nil && anchor == nil
            sessions[nextPage] = session
            state = WallpaperLibraryPresentationState(page: nextPage, query: session.query, queryResult: result,
                directoryEntries: entries ?? directoryEntries, selectionState: session.selection,
                directoryScrollAnchor: anchor,
                directoryScrollOffset: didReset || removedAnchor ? nil : directoryScrollOffset,
                directoryScrollAtTop: didReset ? nil : removedAnchor ? (directoryScrollAtTop == true ? true : nil) : directoryScrollAtTop,
                lastError: settingsError, allowsEditing: state.allowsEditing)
            persistSettings()
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func switchPage(_ newPage: WallpaperLibraryPage) -> Bool {
        guard newPage != page else { return true }
        return present(newPage, query: sessions[newPage]?.query ?? .init(), entering: true)
    }

    @discardableResult
    func setQueryState(_ state: WallpaperLibraryQueryState) -> Bool {
        present(page, query: state, entering: false)
    }

    /// Profile settings bridge only the Videos sort. Navigation and every
    /// other query field remain owned by their existing view sessions.
    func videoSortPreference() throws -> WallpaperLibraryVideoSortPreference {
        let query = sessions[.videos]?.query ?? .init()
        guard let mode = WallpaperLibraryVideoSortPreference.Mode(rawValue: (query.sort ?? .sourceOrder).rawValue) else {
            throw WallpaperLibraryVideoSortError.unsupported
        }
        return WallpaperLibraryVideoSortPreference(mode: mode, ascending: query.ascending,
            legacyTimeOrder: mode == .legacyTime ? (query.legacyTimeOrder ?? []) : nil)
    }

    func validateVideoSortPatch(_ patch: WallpaperLibraryVideoSortPatch, resetEpoch: UUID) throws {
        guard collections?.isResetting == false, collections?.snapshot.resetEpoch == resetEpoch else {
            throw UserCollectionsError.staleResetEpoch
        }
        guard mayWriteSettings else {
            throw WallpaperLibraryVideoSortError.readOnly
        }
        let current = try videoSortPreference()
        guard current == patch.before || current == patch.target else { throw WallpaperLibraryVideoSortError.changed }
    }

    func applyVideoSortPatch(_ patch: WallpaperLibraryVideoSortPatch, resetEpoch: UUID) throws {
        try validateVideoSortPatch(patch, resetEpoch: resetEpoch)
        if try videoSortPreference() != patch.target {
            var session = sessions[.videos] ?? Session()
            session.query.sort = WallpaperLibrarySort(rawValue: patch.target.mode.rawValue)
            session.query.ascending = patch.target.ascending
            session.query.legacyTimeOrder = patch.target.legacyTimeOrder
            if page == .videos {
                guard present(.videos, query: session.query, entering: false) else {
                    throw WallpaperLibraryVideoSortError.unsupported
                }
            } else {
                sessions[.videos] = session
                persistSettings()
            }
        }
        guard defaults.synchronize() else {
            throw WallpaperLibraryVideoSortError.persistenceFailed
        }
    }

    func setScrollAnchor(_ reference: WallpaperReference?, offset: Double? = nil, atTop: Bool? = nil,
                         page targetPage: WallpaperLibraryPage? = nil) {
        guard reference?.sourceID.isEmpty != true else { report(UserCollectionsError.invalidReference); return }
        guard offset?.isFinite != false else { report(SettingsFailure.invalid); return }
        let target = targetPage ?? page
        // A departing native view cannot recreate a session whose UUID was
        // deleted by the latest accepted relationship owner (including reset).
        if relationshipsKnown, case .playlist(let id) = target, let relationships,
           !relationships.playlists.contains(where: { $0.id == id }) { return }
        var session = sessions[target] ?? Session()
        guard session.query.scrollAnchor != reference || session.query.scrollOffset != offset || session.query.scrollAtTop != atTop else { return }
        session.query.scrollAnchor = reference
        session.query.scrollOffset = offset
        session.query.scrollAtTop = atTop
        sessions[target] = session
        // A settled receipt can arrive while leaving its page. Persist that
        // session without projecting it over the newly visible page.
        if target == page {
            var next = state
            next.query = session.query
            state = next
        }
        persistSettings()
    }

    func setDirectoryScrollAnchor(_ id: UUID?, offset: Double? = nil, atTop: Bool? = nil) {
        guard offset?.isFinite != false else { report(SettingsFailure.invalid); return }
        guard directoryScrollAnchor != id || directoryScrollOffset != offset || directoryScrollAtTop != atTop else { return }
        var next = state
        next.directoryScrollAnchor = id
        next.directoryScrollOffset = offset
        next.directoryScrollAtTop = atTop
        state = next
        persistSettings()
    }

    /// Fixed-ID completions use expectedSessionID. A later selection or return
    /// visit cannot be cleared or changed by an earlier asynchronous action.
    @discardableResult
    func setSelection(_ references: Set<WallpaperReference>, focused: WallpaperReference? = nil,
                      isSelecting: Bool = false, expectedSessionID: UUID? = nil) -> Bool {
        if let expectedSessionID, expectedSessionID != selectionState.sessionID { return false }
        var session = sessions[page] ?? Session()
        var next = session.selection
        next.references = references
        next.focusedReference = focused
        next.isSelecting = isSelecting
        if !page.isRemoteBrowse, catalog != nil {
            let visible = Set(queryResult.items.map(\.reference))
            next.references.formIntersection(visible)
            if let focus = next.focusedReference, !visible.contains(focus) { next.focusedReference = nil }
        }
        if next != session.selection {
            next.sessionID = UUID()
            pendingRemovals.removeAll()
        }
        session.selection = next
        sessions[page] = session
        var snapshot = state
        snapshot.selectionState = next
        state = snapshot
        return true
    }

    /// Capture the displayed order before the confirmation sheet. A context
    /// menu on an unselected card still removes that card, but never borrows
    /// somebody else's selection to force an adjacent selection afterwards.
    func beginRemoval(_ references: Set<WallpaperReference>, from page: WallpaperLibraryPage) -> WallpaperLibrarySelectionReceipt? {
        guard page == self.page, !references.isEmpty, !page.isRemoteBrowse,
              let relationships else { return nil }
        // A newer explicit removal is another user intent. Do not retain a
        // backlog of old selection adjustments while a same-ID row reappears.
        pendingRemovals.removeAll()
        let receipt = WallpaperLibrarySelectionReceipt()
        pendingRemovals[receipt.id] = PendingSelectionOperation(page: page, resetEpoch: relationships.resetEpoch,
            displayed: queryResult.items.map(\.reference), targets: references, selection: selectionState,
            waitsForRemoval: true, expectedSessionID: selectionState.sessionID)
        return receipt
    }

    /// Only an operation on the current multi-selection may finish that mode.
    /// Projection reconciliation advances this same receipt; a new user
    /// selection, page visit or reset revokes it through the existing owner.
    func beginOrganizationOperation(_ references: Set<WallpaperReference>) -> WallpaperLibrarySelectionReceipt? {
        guard selectionState.isSelecting, !references.isEmpty, references == selectionState.references,
              let relationships else { return nil }
        pendingRemovals.removeAll()
        let receipt = WallpaperLibrarySelectionReceipt()
        pendingRemovals[receipt.id] = PendingSelectionOperation(page: page, resetEpoch: relationships.resetEpoch,
            displayed: [], targets: references, selection: selectionState, waitsForRemoval: false,
            expectedSessionID: selectionState.sessionID)
        return receipt
    }

    func completeOrganizationOperation(_ receipt: WallpaperLibrarySelectionReceipt?, succeeded: Bool) {
        guard let receipt, let pending = pendingRemovals.removeValue(forKey: receipt.id),
              !pending.waitsForRemoval, succeeded, pending.page == page,
              pending.resetEpoch == relationships?.resetEpoch,
              pending.expectedSessionID == selectionState.sessionID else { return }
        let selection = selectionState
        let focus = selection.focusedReference.flatMap { selection.references.contains($0) ? $0 : nil }
            ?? queryResult.items.first(where: { selection.references.contains($0.reference) })?.reference
        _ = setSelection(focus.map { [$0] } ?? [], focused: focus, isSelecting: false,
            expectedSessionID: pending.expectedSessionID)
    }

    /// Services/Store report actual successes. Selection waits for their real
    /// projection to omit those references; this does not hide or edit a row.
    func completeRemoval(_ receipt: WallpaperLibrarySelectionReceipt?, succeeded: Set<WallpaperReference>) {
        guard let receipt, var pending = pendingRemovals[receipt.id] else { return }
        guard pending.page == page, pending.resetEpoch == relationships?.resetEpoch,
              pending.expectedSessionID == selectionState.sessionID else {
            pendingRemovals.removeValue(forKey: receipt.id)
            return
        }
        pending.succeeded = succeeded.intersection(pending.targets)
        guard pending.succeeded?.isEmpty == false else {
            pendingRemovals.removeValue(forKey: receipt.id)
            return
        }
        pendingRemovals[receipt.id] = pending
        guard let catalog, let relationships else { return }
        do {
            var session = sessions[page] ?? Session()
            try settleRemovals(in: &session, page: page, items: queryResult.items, catalog: catalog, relationships: relationships)
            guard session.selection != selectionState else { return }
            sessions[page] = session
            var next = state
            next.selectionState = session.selection
            state = next
        } catch { report(error) }
    }

    private func advanceRemovalSessions(page: WallpaperLibraryPage, from previous: UUID, to current: UUID) {
        for id in Array(pendingRemovals.keys) where pendingRemovals[id]?.page == page
            && pendingRemovals[id]?.expectedSessionID == previous {
            pendingRemovals[id]?.expectedSessionID = current
        }
    }

    private func settleRemovals(in session: inout Session, page: WallpaperLibraryPage, items: [WallpaperContentItem],
                                catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot) throws {
        let eligible = pendingRemovals.filter { $0.value.waitsForRemoval && $0.value.page == page && $0.value.resetEpoch == relationships.resetEpoch
            && $0.value.expectedSessionID == session.selection.sessionID && $0.value.succeeded != nil }
        guard !eligible.isEmpty else { return }
        // Filters are not deletion evidence. Check the unfiltered page using
        // the same query owner and normalize any aliases learned while waiting.
        let present = Set(try WallpaperLibraryQuery.project(page: page, state: .init(), catalog: catalog,
            relationships: relationships).items.map(\.reference))
        let all = eligible.values.reduce(into: Set<WallpaperReference>()) {
            $0.formUnion($1.displayed); $0.formUnion($1.targets); $0.formUnion($1.selection.references)
            if let focus = $1.selection.focusedReference { $0.insert(focus) }
        }
        let aliases = try WallpaperLibraryQuery.canonicalReferences(all, relationships: relationships)
        let visible = Set(items.map(\.reference))
        for (id, pending) in eligible {
            let succeeded = Set(pending.succeeded!.compactMap { aliases[$0] })
            guard succeeded.isDisjoint(with: present) else { continue }
            let original = pending.selection
            let selected = Set(original.references.compactMap { aliases[$0] })
            let ordered = pending.displayed.compactMap { aliases[$0] }
            var next = session.selection
            next.references = selected.subtracting(succeeded).intersection(visible)
            let originalFocus = original.focusedReference.flatMap { aliases[$0] }
            next.focusedReference = originalFocus.flatMap { next.references.contains($0) ? $0 : nil }
                ?? ordered.first(where: { next.references.contains($0) })
            let targets = Set(pending.targets.compactMap { aliases[$0] })
            next.isSelecting = original.isSelecting && (succeeded != targets || targets != selected)
            if !original.isSelecting, pending.targets.count == 1, selected.count == 1,
               let target = pending.targets.first.flatMap({ aliases[$0] }), selected.contains(target),
               succeeded.contains(target), let index = ordered.firstIndex(of: target) {
                let following = ordered.dropFirst(index + 1).first { visible.contains($0) && !succeeded.contains($0) }
                let preceding = ordered.prefix(index).last { visible.contains($0) && !succeeded.contains($0) }
                let adjacent = following ?? preceding
                next.references = adjacent.map { [$0] } ?? []
                next.focusedReference = adjacent
            }
            pendingRemovals.removeValue(forKey: id)
            if next != session.selection {
                next.sessionID = UUID()
                session.selection = next
                // Another in-flight operation cannot take over this completed
                // action's new selection, even if it shared the old token.
                pendingRemovals.removeAll()
                break
            }
        }
    }

    private func present(_ requestedPage: WallpaperLibraryPage, query: WallpaperLibraryQueryState, entering: Bool) -> Bool {
        do {
            guard query.scrollAnchor?.sourceID.isEmpty != true else { throw UserCollectionsError.invalidReference }
            guard (3...6).contains(query.preferredColumns), query.scrollOffset?.isFinite != false else { throw SettingsFailure.invalid }
            let result: WallpaperLibraryPageResult
            var entries: [WallpaperPlaylistDirectoryEntry]?
            var session = sessions[requestedPage] ?? Session()
            session.query = query
            if let catalog, let relationships {
                result = try project(page: requestedPage, query: query, catalog: catalog, relationships: relationships, relationshipsKnown: relationshipsKnown)
                if requestedPage == .playlists {
                    entries = try WallpaperLibraryQuery.directory(state: query, catalog: catalog, relationships: relationships)
                }
                let previousSessionID = session.selection.sessionID
                try reconcile(&session, page: requestedPage, items: result.items, relationships: relationships)
                if !entering {
                    advanceRemovalSessions(page: requestedPage, from: previousSessionID, to: session.selection.sessionID)
                    try settleRemovals(in: &session, page: requestedPage, items: result.items, catalog: catalog, relationships: relationships)
                }
            } else {
                result = WallpaperLibraryPageResult(items: [], unfilteredCount: 0)
            }
            if entering { session.selection.sessionID = UUID(); pendingRemovals.removeAll() }
            sessions[requestedPage] = session
            state = WallpaperLibraryPresentationState(page: requestedPage, query: session.query, queryResult: result,
                directoryEntries: entries ?? directoryEntries, selectionState: session.selection,
                directoryScrollAnchor: directoryScrollAnchor, directoryScrollOffset: directoryScrollOffset,
                directoryScrollAtTop: directoryScrollAtTop, lastError: settingsError, allowsEditing: state.allowsEditing)
            persistSettings()
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func project(page: WallpaperLibraryPage, query: WallpaperLibraryQueryState,
                         catalog: WallpaperLibraryCatalog, relationships: UserCollectionsSnapshot,
                         relationshipsKnown: Bool) throws -> WallpaperLibraryPageResult {
        // Recovery has no authority to infer that an unreadable UUID was
        // deleted. Keep its saved page/query until a real snapshot is available.
        if !relationshipsKnown, case .playlist = page {
            return WallpaperLibraryPageResult(items: [], unfilteredCount: 0)
        }
        return try WallpaperLibraryQuery.project(page: page, state: query, catalog: catalog, relationships: relationships)
    }

    private func reconcile(_ session: inout Session, page: WallpaperLibraryPage,
                           items: [WallpaperContentItem], relationships: UserCollectionsSnapshot) throws {
        // Remote pagination/selection belongs to the existing browser owner;
        // its absent local catalog is not evidence that its selection vanished.
        guard !page.isRemoteBrowse else { return }
        var references = session.selection.references
        if let focus = session.selection.focusedReference { references.insert(focus) }
        if let anchor = session.query.scrollAnchor { references.insert(anchor) }
        let aliases = try WallpaperLibraryQuery.canonicalReferences(references, relationships: relationships)
        let visible = Set(items.map(\.reference))
        let selected = Set(session.selection.references.compactMap { aliases[$0] }).intersection(visible)
        let focused = session.selection.focusedReference.flatMap { aliases[$0] }.flatMap { visible.contains($0) ? $0 : nil }
        if selected != session.selection.references || focused != session.selection.focusedReference {
            session.selection.sessionID = UUID()
            session.selection.references = selected
            session.selection.focusedReference = focused
        }
        if let anchor = session.query.scrollAnchor { session.query.scrollAnchor = aliases[anchor] ?? anchor }
    }

    private func restoreSettings() {
        guard let raw = defaults.object(forKey: Self.settingsKey) else { return }
        do {
            guard let data = raw as? Data else { throw SettingsFailure.invalid }
            let saved = try JSONDecoder().decode(SavedState.self, from: data)
            guard saved.version == 1 || saved.version == 2, saved.directoryScrollOffset?.isFinite != false else { throw SettingsFailure.invalid }
            var restored: [WallpaperLibraryPage: Session] = [:]
            var legacySubscriptions: WallpaperLibraryQueryState?
            for item in saved.queries {
                guard item.query.scrollAnchor?.sourceID.isEmpty != true else { throw SettingsFailure.invalid }
                if item.wasSubscriptions {
                    guard legacySubscriptions == nil else { throw SettingsFailure.invalid }
                    legacySubscriptions = item.query
                    continue
                }
                guard restored[item.page] == nil else { throw SettingsFailure.invalid }
                restored[item.page] = Session(query: item.query)
            }
            if restored[.workshop] == nil, let legacy = legacySubscriptions {
                restored[.workshop] = Session(query: .init(preferredColumns: legacy.preferredColumns,
                    scrollAnchor: legacy.scrollAnchor, scrollOffset: legacy.scrollOffset, scrollAtTop: legacy.scrollAtTop))
            }
            sessions = restored
            lastSavedData = data
            var next = state
            next.page = saved.page
            next.query = sessions[saved.page]?.query ?? .init()
            next.directoryScrollAnchor = saved.directoryScrollAnchor
            next.directoryScrollOffset = saved.version == 1 ? nil : saved.directoryScrollOffset
            next.directoryScrollAtTop = saved.version == 1 ? nil : saved.directoryScrollAtTop
            state = next
            if saved.version == 1 || legacySubscriptions != nil { persistSettings() }
        } catch {
            // Keep the original bytes for a future supported reader/recovery.
            mayWriteSettings = false
            settingsError = "界面状态无法恢复，原设置已保留。"
            var next = state
            next.lastError = settingsError
            state = next
        }
    }

    private func persistSettings() {
        guard mayWriteSettings else { return }
        let values = sessions.sorted { $0.key.persistenceKey < $1.key.persistenceKey }.map { SavedQuery(page: $0.key, query: $0.value.query) }
        let saved = SavedState(version: 2, page: page, queries: values, directoryScrollAnchor: directoryScrollAnchor,
            directoryScrollOffset: directoryScrollOffset, directoryScrollAtTop: directoryScrollAtTop)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(saved)
            guard data != lastSavedData else { return }
            defaults.set(data, forKey: Self.settingsKey)
            lastSavedData = data
        }
        catch { report(error) }
    }

    func setEditingAllowed(_ allowed: Bool) {
        guard state.allowsEditing != allowed else { return }
        var next = state
        next.allowsEditing = allowed
        state = next
    }

    /// Explicit reinstall owns the replacement of view preferences as well as
    /// source data. Ordinary recovery never overwrites unsupported saved bytes.
    func resetViewState() {
        sessions.removeAll()
        pendingRemovals.removeAll()
        mayWriteSettings = true
        settingsError = nil
        lastSavedData = nil
        state = WallpaperLibraryPresentationState()
        if let catalog, let relationships {
            _ = update(catalog: catalog, relationships: relationships, relationshipsKnown: relationshipsKnown)
        } else { persistSettings() }
    }

    func report(_ error: Error) {
        var next = state
        next.lastError = error.localizedDescription
        next.lastErrorEvent &+= 1
        state = next
    }

    private enum SettingsFailure: Error { case invalid }
}
