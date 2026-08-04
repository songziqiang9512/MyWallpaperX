import Foundation
import Metal

/// Keeps CPU-side source producer state aligned with one Metal submission.
/// Producers remain speculative until that command buffer completes.
final class SceneSourceUpdateTransaction: @unchecked Sendable {
    private enum State {
        case pending
        case armed
        case submitted
        case resolved
    }

    private struct ResolutionAction {
        let completed: (() -> Void)?
        let rollback: () -> Void
    }

    private let lock = NSLock()
    private var state = State.pending
    private var actions: [ResolutionAction] = []

    func registerRollback(_ rollback: @escaping () -> Void) {
        registerResolution(completed: nil, rollback: rollback)
    }

    func registerResolution(
        completed: (() -> Void)?,
        rollback: @escaping () -> Void
    ) {
        lock.lock()
        guard state == .pending else {
            lock.unlock()
            preconditionFailure("source update transaction is already armed")
        }
        actions.append(.init(completed: completed, rollback: rollback))
        lock.unlock()
    }

    func arm(on commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard state == .pending else {
            lock.unlock()
            preconditionFailure("source update transaction cannot be re-armed")
        }
        state = .armed
        lock.unlock()
        commandBuffer.addCompletedHandler { [self] buffer in
            resolveSubmitted(succeeded: buffer.status == .completed)
        }
    }

    func didSubmit() {
        lock.lock()
        switch state {
        case .armed:
            state = .submitted
        case .resolved:
            break
        case .pending, .submitted:
            lock.unlock()
            preconditionFailure("source update transaction was not armed exactly once")
        }
        lock.unlock()
    }

    func cancel() {
        let rollbacks: [() -> Void]
        lock.lock()
        switch state {
        case .pending, .armed:
            state = .resolved
            rollbacks = actions.map(\.rollback)
            actions.removeAll(keepingCapacity: false)
        case .submitted, .resolved:
            rollbacks = []
        }
        lock.unlock()
        for rollback in rollbacks.reversed() { rollback() }
    }

    private func resolveSubmitted(succeeded: Bool) {
        let resolutionActions: [ResolutionAction]
        lock.lock()
        guard state == .armed || state == .submitted else {
            lock.unlock()
            return
        }
        state = .resolved
        resolutionActions = actions
        actions.removeAll(keepingCapacity: false)
        lock.unlock()

        if succeeded {
            for completed in resolutionActions.compactMap(\.completed) {
                completed()
            }
        } else {
            for action in resolutionActions.reversed() {
                action.rollback()
            }
        }
    }
}

/// Maintains one speculative state chain for a source producer. Submitted
/// ancestors stay intact when a later unsubmitted candidate is cancelled.
final class SceneSourceUpdateStateFIFO<Value>: @unchecked Sendable {
    private final class Token {}

    private struct Pending {
        let token: Token
        let candidate: Value
        var completed = false
    }

    private let lock = NSLock()
    private var committed: Value
    private var scheduled: Value
    private var pending: [Pending] = []

    init(initial: Value) {
        committed = initial
        scheduled = initial
    }

    func update<Result>(
        transaction: SceneSourceUpdateTransaction,
        _ makeCandidate: (inout Value) -> Result
    ) -> Result {
        lock.lock()
        var candidate = scheduled
        let result = makeCandidate(&candidate)
        let token = Token()
        pending.append(.init(token: token, candidate: candidate))
        scheduled = candidate
        transaction.registerResolution(
            completed: { [weak self] in
                self?.resolve(token: token, succeeded: true)
            },
            rollback: { [weak self] in
                self?.resolve(token: token, succeeded: false)
            }
        )
        lock.unlock()
        return result
    }

    private func resolve(token: Token, succeeded: Bool) {
        lock.lock()
        guard let index = pending.firstIndex(where: { $0.token === token }) else {
            lock.unlock()
            return
        }
        guard succeeded else {
            scheduled = index > 0 ? pending[index - 1].candidate : committed
            pending.removeSubrange(index...)
            lock.unlock()
            return
        }
        pending[index].completed = true
        while pending.first?.completed == true {
            committed = pending.removeFirst().candidate
        }
        if pending.isEmpty { scheduled = committed }
        lock.unlock()
    }
}
