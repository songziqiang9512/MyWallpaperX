import Foundation
import Combine

/// Shared account-scoped truth. Unknown/unconfirmed can only trigger a read, never a write.
@MainActor
final class SteamWorkshopSubscriptionStore: ObservableObject {
    enum State: Equatable {
        case unknown, loading, known(Bool), writing, reconciling, unconfirmed(String)
    }
    @Published private(set) var states: [String: State] = [:]
    private var epoch: Int?
    private var tasks: [String: Task<Void, Never>] = [:]
    var didReconcileWrite: ((String, Bool) -> Void)?
    private let identity: () -> Int?
    private let read: (String) async throws -> Bool
    private let write: (String, Bool) async throws -> Void

    init(identity: @escaping () -> Int?, read: @escaping (String) async throws -> Bool,
         write: @escaping (String, Bool) async throws -> Void) {
        self.identity = identity
        self.read = read
        self.write = write
    }

    func synchronizeAccount() {
        let current = identity()
        guard epoch != current else { return }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        states.removeAll()
        epoch = current
    }

    func state(for id: String) -> State {
        synchronizeAccount()
        return states[id] ?? .unknown
    }

    /// A successful current-account subscribed page proves positive membership.
    /// Never overwrite an in-flight mutation or a newer known/readback result.
    func observeSubscribedIDs(_ ids: [String]) {
        synchronizeAccount()
        guard epoch != nil else { return }
        for id in ids where tasks[id] == nil && states[id] == nil {
            states[id] = .known(true)
        }
    }

    func refresh(_ id: String) {
        synchronizeAccount()
        guard let epoch, tasks[id] == nil else { return }
        states[id] = .loading
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await self.read(id)
                guard self.isCurrent(epoch) else { return }
                self.states[id] = .known(value)
            } catch {
                guard self.isCurrent(epoch) else { return }
                self.states[id] = .unconfirmed("订阅状态暂时无法确认，请点击重新查询。")
            }
            self.tasks[id] = nil
        }
    }

    func toggle(_ id: String) {
        synchronizeAccount()
        guard let epoch, tasks[id] == nil, case .known(let old) = state(for: id) else { return }
        let desired = !old
        states[id] = .writing
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            // Timeout/connection failure is an ambiguous write, so always reconcile once.
            // Never automatically repeat a write, even when the read fails.
            do { try await self.write(id, desired) } catch { }
            guard self.isCurrent(epoch) else { return }
            self.states[id] = .reconciling
            do {
                let actual = try await self.read(id)
                guard self.isCurrent(epoch) else { return }
                self.states[id] = .known(actual)
                self.didReconcileWrite?(id, actual)
            } catch {
                guard self.isCurrent(epoch) else { return }
                self.states[id] = .unconfirmed("操作结果待确认，请重新查询后再操作。")
            }
            self.tasks[id] = nil
        }
    }

    private func isCurrent(_ captured: Int) -> Bool {
        !Task.isCancelled && captured == epoch && identity() == captured
    }
}
