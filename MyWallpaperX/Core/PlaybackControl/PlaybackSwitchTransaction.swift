import Foundation

/// A user's selection and an engine's execution are different identities. A
/// reconnect may replace the latter without becoming a new selection.
nonisolated struct PlaybackSwitchTicket: Hashable, Sendable {
    let epoch: UInt64
    let id: UUID
    let runtime: WallpaperRuntimeKind
}

/// Execution operations retain their native identity inside their closures.
/// This value owns no renderer, clock, resource lease, or process.
@MainActor
struct PlaybackSwitchEndpoint {
    let id: UUID
    let activate: () -> Void
    let finalize: () -> Void
    let cancel: (@escaping () -> Void) -> Void
    let setOutputActive: (Bool, @escaping (Bool) -> Void) -> Void
    let retire: (@escaping () -> Void) -> Void
}

/// Pure product state. WallpaperManager is its only mutable owner. In
/// particular, native prepared/visible events cannot commit a selection.
nonisolated struct PlaybackSwitchTransaction {
    struct Selection: Equatable, Sendable {
        let ticket: PlaybackSwitchTicket
        var executionID: UUID? = nil
    }
    struct Pending: Equatable, Sendable {
        enum Phase: Sendable { case preparing, prepared, activating, visible }
        var selection: Selection
        var phase: Phase
        let recovery: Bool
    }
    struct Activity: Equatable, Sendable {
        let id: UUID
        let executionID: UUID
        let active: Bool
    }
    enum Effect: Equatable, Sendable {
        case cancel(UUID, Selection)
        case output(Activity)
        case activate(Selection)
        case finalize(Selection)
        case retire(UUID, Selection)
        case handoff(UUID, Selection, Selection)
        case commit(Selection, recovery: Bool)
        case failed(PlaybackSwitchTicket, String)
        case lost(PlaybackSwitchTicket, String)
    }

    private(set) var epoch: UInt64 = 0
    private(set) var committed: Selection?
    private(set) var pending: Pending?
    private(set) var cancellations: [UUID: Selection] = [:]
    private(set) var activity: Activity?
    private(set) var committedOutputActive = true
    private(set) var retirements: [UUID: Selection] = [:]
    private var recovery: Selection?

    var requestedRuntime: WallpaperRuntimeKind? {
        pending?.selection.ticket.runtime ?? committed?.ticket.runtime
    }

    mutating func begin(_ runtime: WallpaperRuntimeKind) -> (PlaybackSwitchTicket, [Effect]) {
        epoch &+= 1
        let ticket = PlaybackSwitchTicket(epoch: epoch, id: UUID(), runtime: runtime)
        var effects: [Effect] = []
        if let previous = pending { cancel(previous.selection, into: &effects) }
        // Install new intent before effects can synchronously call back.
        pending = Pending(selection: .init(ticket: ticket), phase: .preparing, recovery: false)
        return (ticket, effects)
    }

    mutating func prepared(_ ticket: PlaybackSwitchTicket, executionID: UUID) -> [Effect] {
        let selection = Selection(ticket: ticket, executionID: executionID)
        var effects: [Effect] = []
        if pending?.selection.ticket == ticket {
            if let previous = pending?.selection.executionID, previous != executionID {
                cancel(pending!.selection, into: &effects)
            }
            pending?.selection = selection
            pending?.phase = .prepared
        } else if committed?.ticket == ticket {
            guard committed?.executionID != executionID else { return [] }
            if let previous = recovery, previous != selection { cancel(previous, into: &effects) }
            recovery = selection
        } else {
            cancel(selection, into: &effects)
        }
        advance(into: &effects)
        return effects
    }

    mutating func visible(_ ticket: PlaybackSwitchTicket, executionID: UUID) -> [Effect] {
        guard let candidate = pending, candidate.selection.ticket == ticket,
              candidate.selection.executionID == executionID,
              candidate.phase == .activating else { return [] }
        // A terminal loss may add a retirement barrier after activation. Keep
        // this one-shot native proof until that barrier settles.
        pending?.phase = .visible
        var effects: [Effect] = []
        advance(into: &effects)
        return effects
    }

    private mutating func commitVisible(_ candidate: Pending) -> [Effect] {
        let executionID = candidate.selection.executionID
        let old = committed
        committed = candidate.selection
        pending = nil
        activity = nil
        committedOutputActive = true
        var effects: [Effect] = [.commit(candidate.selection, recovery: candidate.recovery)]
        if let old, old.executionID != executionID {
            let barrier = UUID()
            retirements[barrier] = candidate.selection
            effects.append(.handoff(barrier, old, candidate.selection))
        } else { effects.append(.finalize(candidate.selection)) }
        if let recovery { cancel(recovery, into: &effects) }
        recovery = nil
        return effects
    }

    mutating func failed(_ ticket: PlaybackSwitchTicket, reason: String) -> [Effect] {
        guard pending?.selection.ticket == ticket else { return [] }
        var effects: [Effect] = []
        if let pending { cancel(pending.selection, into: &effects) }
        pending = nil
        effects.append(.failed(ticket, reason))
        advance(into: &effects)
        return effects
    }

    /// Native recovery exhaustion is an output loss, not a new selection and
    /// not a reason to cancel a newer pending user request.
    mutating func lost(_ ticket: PlaybackSwitchTicket, reason: String) -> [Effect] {
        guard let previous = committed, previous.ticket == ticket else { return [] }
        var effects: [Effect] = []
        if pending?.selection.ticket == ticket, let pending {
            cancel(pending.selection, into: &effects)
            self.pending = nil
        }
        if let recovery { cancel(recovery, into: &effects) }
        recovery = nil
        committed = nil
        activity = nil
        committedOutputActive = true
        let barrier = UUID()
        retirements[barrier] = previous
        effects += [.lost(ticket, reason), .retire(barrier, previous)]
        return effects
    }

    mutating func cancelled(_ barrier: UUID) -> [Effect] {
        guard cancellations.removeValue(forKey: barrier) != nil else { return [] }
        var effects: [Effect] = []
        advance(into: &effects)
        return effects
    }

    mutating func retired(_ barrier: UUID) -> [Effect] {
        guard let selection = retirements.removeValue(forKey: barrier) else { return [] }
        var effects: [Effect] = []
        if committed == selection { effects.append(.finalize(selection)) }
        advance(into: &effects)
        return effects
    }

    mutating func activityCompleted(_ operation: Activity, succeeded: Bool) -> [Effect] {
        guard activity == operation, committed?.executionID == operation.executionID else { return [] }
        activity = nil
        var effects: [Effect] = []
        if succeeded {
            committedOutputActive = operation.active
        } else if !operation.active, let pending {
            cancel(pending.selection, into: &effects)
            self.pending = nil
            effects.append(.failed(pending.selection.ticket, "旧壁纸未能确认暂停输出，已取消切换"))
        }
        // Failed restoration must not produce an unbounded immediate retry loop.
        if !succeeded, operation.active { return effects }
        advance(into: &effects)
        return effects
    }

    mutating func stop() -> [Effect] {
        epoch &+= 1
        var effects: [Effect] = []
        if let pending { cancel(pending.selection, into: &effects) }
        if let recovery { cancel(recovery, into: &effects) }
        if let committed {
            let barrier = UUID()
            retirements[barrier] = committed
            effects.append(.retire(barrier, committed))
        }
        pending = nil
        committed = nil
        recovery = nil
        activity = nil
        committedOutputActive = true
        return effects
    }

    private mutating func cancel(_ selection: Selection, into effects: inout [Effect]) {
        guard !cancellations.values.contains(selection) else { return }
        let barrier = UUID()
        cancellations[barrier] = selection
        effects.append(.cancel(barrier, selection))
    }

    private mutating func advance(into effects: inout [Effect]) {
        guard cancellations.isEmpty, retirements.isEmpty, activity == nil else { return }
        if let pending, pending.phase == .visible {
            effects += commitVisible(pending)
            return
        }
        if pending == nil, let recovery {
            self.recovery = nil
            pending = .init(selection: recovery, phase: .prepared, recovery: true)
        }
        let ready = pending?.phase == .prepared
        if let committed, let executionID = committed.executionID {
            let desiredOutput = !ready && pending?.phase != .activating
            if committedOutputActive != desiredOutput {
                let operation = Activity(id: UUID(), executionID: executionID, active: desiredOutput)
                activity = operation
                effects.append(.output(operation))
                return
            }
        }
        guard ready, let selection = pending?.selection else { return }
        pending?.phase = .activating
        effects.append(.activate(selection))
    }
}
