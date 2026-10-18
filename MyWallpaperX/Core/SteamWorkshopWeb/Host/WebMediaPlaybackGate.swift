import Foundation

/// Serializes the asynchronous native WebKit gate. A later desired policy may
/// supersede a waiter, but never races a second native call against the first.
@MainActor
final class WebMediaPlaybackGate {
    typealias Apply = (Bool, @escaping @MainActor @Sendable () -> Void) -> Void
    private let apply: Apply
    private var desired: Bool?
    private var applied: Bool?
    private var inFlight: (id: UUID, suspended: Bool)?
    private var waiters: [(suspended: Bool, completion: (Bool) -> Void)] = []
    private var valid = true
    private var generation: UInt64 = 0

    init(apply: @escaping Apply) { self.apply = apply }

    func setSuspended(_ suspended: Bool, completion: ((Bool) -> Void)? = nil) {
        guard valid else { completion?(false); return }
        desired = suspended
        let superseded = waiters.filter { $0.suspended != suspended }
        waiters.removeAll { $0.suspended != suspended }
        superseded.forEach { $0.completion(false) }
        if let completion { waiters.append((suspended, completion)) }
        drain()
    }

    func invalidate() {
        valid = false
        inFlight = nil
        let cancelled = waiters
        waiters.removeAll()
        cancelled.forEach { $0.completion(false) }
    }

    /// A navigation invalidates the cached acknowledgement, while its native
    /// call still drains before any call for the replacement document.
    func resetForNavigation() {
        generation &+= 1
        applied = nil
        let cancelled = waiters
        waiters.removeAll()
        cancelled.forEach { $0.completion(false) }
        drain()
    }

    private func drain() {
        guard valid, inFlight == nil, let desired else { return }
        if applied == desired {
            let completed = waiters
            waiters.removeAll()
            completed.forEach { $0.completion(true) }
            return
        }
        let id = UUID()
        let generation = generation
        inFlight = (id, desired)
        apply(desired) { [weak self] in
            guard let self, self.valid, self.inFlight?.id == id else { return }
            if self.generation == generation { self.applied = desired }
            self.inFlight = nil
            self.drain()
        }
    }
}
