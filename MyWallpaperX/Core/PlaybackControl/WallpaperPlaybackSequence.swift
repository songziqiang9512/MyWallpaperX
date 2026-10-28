import Foundation

nonisolated enum WallpaperPlaybackCause: String, Codable, Sendable {
    case userSelection, manualNavigation, timer, ended, failureRecovery, restore, recovery, settingsReload
    var shouldRecordRecent: Bool {
        switch self {
        case .userSelection, .manualNavigation, .timer, .ended, .failureRecovery: return true
        case .restore, .recovery, .settingsReload: return false
        }
    }
}

/// Pure navigation state inside the existing product owner. It never accepts a
/// product intent, resolves a provider, owns a renderer or writes relationships.
nonisolated struct WallpaperPlaybackSequence: Sendable {
    enum Source: Hashable, Codable, Sendable {
        case page(WallpaperLibraryPage), global, single(WallpaperReference)
    }
    enum Direction: Sendable { case previous, next }
    enum Mode: Sendable { case loop, sequential, random }
    enum NavigationPolicy: Sendable { case adjacent, randomHistory }
    enum SourceUpdateReason: Sendable { case explicitMembers, availability, recentSuccessReorder, sourceDeleted }
    struct Entry: Equatable, Sendable {
        let reference: WallpaperReference
        let runtime: WallpaperRuntimeKind?
        let isPlayable: Bool
        let resourceRevision: String?

        init(reference: WallpaperReference, runtime: WallpaperRuntimeKind?, isPlayable: Bool, resourceRevision: String? = nil) {
            self.reference = reference
            self.runtime = runtime
            self.isPlayable = isPlayable
            self.resourceRevision = resourceRevision
        }
    }
    struct Snapshot: Equatable, Sendable {
        let source: Source
        let revision: UInt64
        let entries: [Entry]
        /// The accepted page query, without view-only density/scroll settings.
        /// Later UI browsing must not silently expand this playback source.
        let sourceQuery: WallpaperLibraryQueryState?

        init(source: Source, revision: UInt64, entries: [Entry],
             sourceQuery: WallpaperLibraryQueryState? = nil) throws {
            if case .page(let page) = source, page.isRemoteBrowse || page == .playlists { throw Failure.invalidSource }
            if case .single(let reference) = source, reference.sourceID.isEmpty { throw Failure.invalidSource }
            var seen = Set<WallpaperReference>(), unique: [Entry] = []
            for entry in entries {
                guard !entry.reference.sourceID.isEmpty, !entry.isPlayable || entry.runtime != nil else { throw Failure.invalidSnapshot }
                if case .single(let reference) = source, reference != entry.reference { throw Failure.invalidSource }
                if seen.insert(entry.reference).inserted { unique.append(entry) }
            }
            if sourceQuery != nil, case .page = source {} else if sourceQuery != nil { throw Failure.invalidSource }
            self.source = source
            self.revision = revision
            self.entries = unique
            self.sourceQuery = Self.playbackQuery(sourceQuery)
        }
    }
    struct Proposal: Equatable, Sendable {
        let entry: Entry
        let snapshot: Snapshot
        let rotationGeneration: UInt64
        let cause: WallpaperPlaybackCause
        fileprivate let history: HistoryChange
    }
    struct Pending: Equatable, Sendable {
        let proposal: Proposal
        let ticket: PlaybackSwitchTicket
    }
    struct Session: Equatable, Sendable {
        var snapshot: Snapshot
        let reference: WallpaperReference
        let ticket: PlaybackSwitchTicket
        var isDetached = false
        var cursor: Int? { snapshot.entries.firstIndex(where: { $0.reference == reference }) }
        fileprivate var removedNext: [WallpaperReference] = []
        fileprivate var removedPrevious: [WallpaperReference] = []
    }
    struct Commit: Equatable, Sendable {
        let reference: WallpaperReference
        let ticket: PlaybackSwitchTicket
        let source: Source
        let cause: WallpaperPlaybackCause
        let isRecovery: Bool
        var shouldRecordRecent: Bool { !isRecovery && cause.shouldRecordRecent }
    }
    enum Failure: Error { case invalidSource, invalidSnapshot }
    fileprivate enum HistoryChange: Equatable, Sendable { case reset, append, back(Int), forward(Int), preserve }
    private struct Traversal: Sendable {
        let snapshot: Snapshot
        let direction: Direction
        let mode: Mode
        let policy: NavigationPolicy
        let cause: WallpaperPlaybackCause
        var visited: Set<WallpaperReference> = []
        var after: WallpaperReference?
    }
    static let historyLimit = 10
    private(set) var committed: Session?
    private(set) var pending: Pending?
    private(set) var rotationGeneration: UInt64 = 0
    private(set) var backHistory: [WallpaperReference] = []
    private(set) var forwardHistory: [WallpaperReference] = []
    private(set) var isExhausted = false
    private var reserved: Proposal?
    private var traversal: Traversal?
    private var pendingSnapshot: Snapshot?
    private var pendingDetached = false

    /// Explicit selection/approved restore supplies the entire bounded source.
    /// An absent/empty source never falls back to a different library here.
    mutating func proposeSelection(_ reference: WallpaperReference, from snapshot: Snapshot,
                                   cause: WallpaperPlaybackCause = .userSelection,
                                   expectedGeneration: UInt64? = nil) -> Proposal? {
        guard expectedGeneration == nil || expectedGeneration == rotationGeneration else { return nil }
        var selectedSnapshot = snapshot
        switch cause {
        case .timer, .ended, .failureRecovery, .recovery: return nil
        case .settingsReload:
            guard let committed, committed.reference == reference, committed.snapshot.source == snapshot.source,
                  pending == nil, reserved == nil else { return nil }
            selectedSnapshot = committed.snapshot
        case .userSelection, .manualNavigation, .restore: break
        }
        guard let target = selectedSnapshot.entries.first(where: { $0.reference == reference && $0.isPlayable }) else { return nil }
        rotationGeneration &+= 1
        pending = nil
        pendingSnapshot = nil
        pendingDetached = false
        traversal = nil
        isExhausted = false
        let preserve = cause == .settingsReload
        let proposal = Proposal(entry: target, snapshot: selectedSnapshot, rotationGeneration: rotationGeneration,
                                cause: cause, history: preserve ? .preserve : .reset)
        reserved = proposal
        return proposal
    }

    /// Only one reservation/prepare may advance. Explicit adjacent navigation
    /// preserves list order; randomHistory consumes successful visits only.
    mutating func proposeAdvance(_ direction: Direction = .next, policy: NavigationPolicy = .adjacent,
                                 mode: Mode, cause: WallpaperPlaybackCause = .manualNavigation,
                                 expectedGeneration: UInt64? = nil, chooseIndex: (Int) -> Int) -> Proposal? {
        guard expectedGeneration == nil || expectedGeneration == rotationGeneration,
              let committed, pending == nil, reserved == nil else { return nil }
        let automatic = cause == .timer || cause == .ended || cause == .failureRecovery
        guard cause == .manualNavigation || automatic,
              !automatic || mode != .loop || cause == .failureRecovery,
              !automatic || !isExhausted else { return nil }
        if cause == .ended, committed.ticket.runtime != .video { return nil }
        rotationGeneration &+= 1
        if !automatic { isExhausted = false }
        traversal = Traversal(snapshot: committed.snapshot, direction: direction, mode: mode, policy: policy,
                              cause: cause, after: committed.reference)
        let proposal = nextProposal(chooseIndex: chooseIndex)
        reserved = proposal
        if proposal == nil { traversal = nil; if automatic { isExhausted = true } }
        return proposal
    }

    /// The caller first obtains the original Manager ticket and verifies that it
    /// remains admitted. No epoch or product ticket is minted by this value.
    @discardableResult
    mutating func stage(_ proposal: Proposal, ticket: PlaybackSwitchTicket) -> Bool {
        guard reserved == proposal, proposal.rotationGeneration == rotationGeneration,
              proposal.entry.runtime == ticket.runtime, ticket != committed?.ticket else { return false }
        pending = Pending(proposal: proposal, ticket: ticket)
        pendingSnapshot = nil
        pendingDetached = false
        reserved = nil
        return true
    }

    /// Recovery is a new execution of the same committed selection. It neither
    /// consumes a newer pending selection nor creates another recent/history row.
    mutating func commit(_ ticket: PlaybackSwitchTicket, recovery: Bool = false) -> Commit? {
        if recovery {
            guard let committed, committed.ticket == ticket else { return nil }
            return Commit(reference: committed.reference, ticket: ticket, source: committed.snapshot.source,
                          cause: .recovery, isRecovery: true)
        }
        guard let pending, pending.ticket == ticket else { return nil }
        let proposal = pending.proposal
        let latest = pendingSnapshot ?? proposal.snapshot
        updateHistory(proposal.history, target: proposal.entry.reference, snapshot: latest)
        var session = Session(snapshot: proposal.snapshot, reference: proposal.entry.reference, ticket: ticket,
                              isDetached: pendingDetached)
        replaceSnapshot(&session, with: latest)
        committed = session
        clearAttempt()
        rotationGeneration &+= 1
        isExhausted = false
        return Commit(reference: proposal.entry.reference, ticket: ticket, source: latest.source,
                      cause: proposal.cause, isRecovery: false)
    }

    @discardableResult
    mutating func fail(_ ticket: PlaybackSwitchTicket) -> Bool {
        guard pending?.ticket == ticket else { return false }
        clearAttempt()
        rotationGeneration &+= 1
        return true
    }

    @discardableResult
    mutating func cancel(_ ticket: PlaybackSwitchTicket) -> Bool { fail(ticket) }

    /// Used for an accepted automatic/explicit navigation attempt, not an
    /// unrelated provider failure. Visited belongs to this generation/revision.
    mutating func retryAfterFailure(_ ticket: PlaybackSwitchTicket, chooseIndex: (Int) -> Int) -> Proposal? {
        guard let pending, pending.ticket == ticket else { return nil }
        guard var traversal, traversal.snapshot.revision == pending.proposal.snapshot.revision,
              pending.proposal.rotationGeneration == rotationGeneration else {
            _ = fail(ticket)
            return nil
        }
        traversal.visited.insert(pending.proposal.entry.reference)
        traversal.after = pending.proposal.entry.reference
        self.traversal = traversal
        self.pending = nil
        pendingSnapshot = nil
        pendingDetached = false
        let proposal = nextProposal(chooseIndex: chooseIndex)
        reserved = proposal
        if proposal == nil {
            self.traversal = nil
            isExhausted = true
            rotationGeneration &+= 1
        }
        return proposal
    }

    /// Resource refreshes do not append/reorder members. Explicit edits update
    /// the next boundary; an admitted ticket can settle against the latest list.
    mutating func updateSource(_ snapshot: Snapshot, reason: SourceUpdateReason,
                               targetTicket: PlaybackSwitchTicket? = nil) {
        guard reason != .recentSuccessReorder else { return }
        func matches(_ previous: Snapshot?) -> Bool {
            guard let previous, previous.source == snapshot.source else { return false }
            return reason != .explicitMembers || previous.sourceQuery == snapshot.sourceQuery
        }
        let affectsCommitted = (targetTicket == nil || committed?.ticket == targetTicket) && matches(committed?.snapshot)
        let affectsPending = (targetTicket == nil || pending?.ticket == targetTicket) && matches(pendingSnapshot ?? pending?.proposal.snapshot)
        // A reserved proposal has no accepted product ticket. An obsolete
        // ticket-specific update may never mutate that newer reservation.
        let affectsReserved = targetTicket == nil && matches(reserved?.snapshot)
        guard affectsCommitted || affectsPending || affectsReserved else { return }
        let oldPending = affectsPending ? (pendingSnapshot ?? pending?.proposal.snapshot) : nil
        let oldCommitted = affectsCommitted ? committed?.snapshot : nil
        let oldReserved = affectsReserved ? reserved?.snapshot : nil
        let revision = max(oldPending?.revision ?? 0, oldCommitted?.revision ?? 0, oldReserved?.revision ?? 0)
        guard snapshot.revision >= revision else { return }
        if reason == .sourceDeleted {
            if affectsCommitted { committed?.isDetached = true }
            if affectsPending { pendingDetached = true }
            if affectsReserved {
                reserved = nil
                traversal = nil
                rotationGeneration &+= 1
            }
            return
        }
        if reason == .availability {
            let existing = [oldPending, oldCommitted, oldReserved].compactMap { $0 }
            guard existing.contains(where: { availability(snapshot, retaining: $0).entries != $0.entries }) else { return }
        }
        var improved = false
        if affectsCommitted, var session = committed, !session.isDetached || reason == .availability {
            let next = reason == .availability ? availability(snapshot, retaining: session.snapshot) : snapshot
            improved = resourceImproved(from: session.snapshot, to: next)
            replaceSnapshot(&session, with: next)
            committed = session
        }
        if affectsPending, let pending, !pendingDetached || reason == .availability {
            let previous = pendingSnapshot ?? pending.proposal.snapshot
            pendingSnapshot = reason == .availability ? availability(snapshot, retaining: previous) : snapshot
            if let pendingSnapshot { improved = improved || resourceImproved(from: previous, to: pendingSnapshot) }
        }
        // Any old retry/queued tick is revoked, but the original product ticket
        // is not cancelled here. Its success still selects only its fixed ID.
        reserved = nil
        traversal = nil
        rotationGeneration &+= 1
        if reason == .explicitMembers || improved { isExhausted = false }
    }

    mutating func stop() {
        clearAttempt()
        committed = nil
        backHistory.removeAll()
        forwardHistory.removeAll()
        rotationGeneration &+= 1
        isExhausted = false
    }

    private mutating func clearAttempt() {
        pending = nil
        reserved = nil
        traversal = nil
        pendingSnapshot = nil
        pendingDetached = false
    }

    private mutating func nextProposal(chooseIndex: (Int) -> Int) -> Proposal? {
        guard let traversal, let committed else { return nil }
        let eligible = traversal.snapshot.entries.filter {
            $0.isPlayable && $0.reference != committed.reference && !traversal.visited.contains($0.reference)
        }
        let byReference = Dictionary(eligible.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        var target: Entry?, history: HistoryChange = .append
        let historical = traversal.cause == .manualNavigation && traversal.policy == .randomHistory && traversal.mode == .random
        if historical {
            let values = traversal.direction == .previous ? backHistory : forwardHistory
            if let index = values.indices.reversed().first(where: { byReference[values[$0]] != nil }) {
                target = byReference[values[index]]
                history = traversal.direction == .previous ? .back(index) : .forward(index)
            }
        }
        let random = traversal.mode == .random && (traversal.cause == .timer || traversal.cause == .ended || traversal.cause == .failureRecovery
            || historical && traversal.direction == .next)
        if target == nil, random, !eligible.isEmpty {
            let index = chooseIndex(eligible.count)
            guard eligible.indices.contains(index) else { return nil }
            target = eligible[index]
        } else if target == nil {
            let order: [WallpaperReference]
            if let after = traversal.after, traversal.snapshot.entries.contains(where: { $0.reference == after }) {
                order = orderedReferences(traversal.snapshot.entries.map(\.reference), after: after, direction: traversal.direction)
            } else {
                order = traversal.direction == .next ? committed.removedNext : committed.removedPrevious
            }
            target = order.lazy.compactMap { byReference[$0] }.first
        }
        guard let target else { return nil }
        return Proposal(entry: target, snapshot: traversal.snapshot, rotationGeneration: rotationGeneration,
                        cause: traversal.cause, history: history)
    }

    private mutating func updateHistory(_ change: HistoryChange, target: WallpaperReference, snapshot: Snapshot) {
        let sameSource = committed?.snapshot.source == snapshot.source
        let members = Set(snapshot.entries.map(\.reference))
        let old = committed?.reference
        if !sameSource { backHistory.removeAll(); forwardHistory.removeAll() }
        var appendPrevious = true
        switch change {
        case .preserve: appendPrevious = false
        case .reset: backHistory.removeAll(); forwardHistory.removeAll()
        case .back(let index):
            appendPrevious = false
            backHistory = Array(backHistory.prefix(index))
            if let old, old != target, members.contains(old) { forwardHistory.append(old) }
        case .forward(let index): forwardHistory = Array(forwardHistory.prefix(index))
        case .append: forwardHistory.removeAll()
        }
        if appendPrevious, let old, old != target, sameSource, members.contains(old) { backHistory.append(old) }
        backHistory = Array(backHistory.filter { members.contains($0) }.suffix(Self.historyLimit))
        forwardHistory = Array(forwardHistory.filter { members.contains($0) }.suffix(Self.historyLimit))
    }

    private func replaceSnapshot(_ session: inout Session, with snapshot: Snapshot) {
        let references = snapshot.entries.map(\.reference), members = Set(references)
        if !members.contains(session.reference) {
            let old = session.snapshot.entries.map(\.reference)
            let next = old.contains(session.reference) ? orderedReferences(old, after: session.reference, direction: .next) : session.removedNext
            let previous = old.contains(session.reference) ? orderedReferences(old, after: session.reference, direction: .previous) : session.removedPrevious
            session.removedNext = next.filter { members.contains($0) }
            session.removedPrevious = previous.filter { members.contains($0) }
            var nextSeen = Set(session.removedNext), previousSeen = Set(session.removedPrevious)
            session.removedNext += references.filter { nextSeen.insert($0).inserted }
            session.removedPrevious += references.reversed().filter { previousSeen.insert($0).inserted }
        } else { session.removedNext = []; session.removedPrevious = [] }
        session.snapshot = snapshot
    }

    private func availability(_ update: Snapshot, retaining old: Snapshot) -> Snapshot {
        let facts = Dictionary(update.entries.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        // Both inputs have already validated their source and unique entries.
        return Snapshot(source: old.source, revision: update.revision, sourceQuery: old.sourceQuery, validatedEntries: old.entries.map {
            facts[$0.reference] ?? Entry(reference: $0.reference, runtime: $0.runtime, isPlayable: false, resourceRevision: $0.resourceRevision)
        })
    }

    private func resourceImproved(from old: Snapshot, to next: Snapshot) -> Bool {
        let previous = Dictionary(old.entries.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        return next.entries.contains { entry in
            guard entry.reference != committed?.reference, entry.isPlayable, let before = previous[entry.reference] else { return false }
            return !before.isPlayable || entry.resourceRevision != nil && entry.resourceRevision != before.resourceRevision
        }
    }

    private func orderedReferences(_ values: [WallpaperReference], after reference: WallpaperReference,
                                   direction: Direction) -> [WallpaperReference] {
        guard let start = values.firstIndex(of: reference), !values.isEmpty else { return [] }
        return (1...values.count).map { step in
            values[(start + (direction == .next ? step : -step) + values.count) % values.count]
        }
    }
}

private extension WallpaperPlaybackSequence.Snapshot {
    nonisolated static func playbackQuery(_ input: WallpaperLibraryQueryState?) -> WallpaperLibraryQueryState? {
        guard var input else { return nil }
        input.preferredColumns = 5
        input.scrollAnchor = nil
        input.scrollOffset = nil
        input.scrollAtTop = nil
        return input
    }

    nonisolated init(source: WallpaperPlaybackSequence.Source, revision: UInt64, sourceQuery: WallpaperLibraryQueryState?, validatedEntries: [WallpaperPlaybackSequence.Entry]) {
        self.source = source
        self.revision = revision
        self.entries = validatedEntries
        self.sourceQuery = sourceQuery
    }
}
