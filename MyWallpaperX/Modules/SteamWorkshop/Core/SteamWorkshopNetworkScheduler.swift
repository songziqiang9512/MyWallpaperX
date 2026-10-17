import Foundation

nonisolated enum SteamWorkshopDetailRequestPriority {
    case userInitiated
    case background
}

actor SteamWorkshopDetailRequestScheduler {
    static let shared = SteamWorkshopDetailRequestScheduler()
    private let maxConcurrentUserRequests = 1
    private let maxConcurrentBackgroundRequests = 2
    private let maxConcurrentRequestsWhileUserActive = 2

    // Includes permits handed to resumed waiters that have not run yet.
    private var activeUserRequests = 0
    private var activeBackgroundRequests = 0
    private var waitingUserRequests: [CheckedContinuation<Void, Never>] = []
    private var waitingBackgroundRequests: [CheckedContinuation<Void, Never>] = []

    func run<T>(
        priority: SteamWorkshopDetailRequestPriority,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire(priority: priority)
        defer { release(priority: priority) }
        return try await operation()
    }

    private func acquire(priority: SteamWorkshopDetailRequestPriority) async {
        if canAcquire(priority: priority) {
            reserve(priority: priority)
            return
        }
        await withCheckedContinuation { continuation in
            switch priority {
            case .userInitiated:
                waitingUserRequests.append(continuation)
            case .background:
                waitingBackgroundRequests.append(continuation)
            }
        }
        // release transfers an already reserved permit to this waiter.
    }

    private func reserve(priority: SteamWorkshopDetailRequestPriority) {
        switch priority {
        case .userInitiated:
            activeUserRequests += 1
        case .background:
            activeBackgroundRequests += 1
        }
    }

    private func canAcquire(priority: SteamWorkshopDetailRequestPriority) -> Bool {
        switch priority {
        case .userInitiated:
            return activeUserRequests < maxConcurrentUserRequests
                && (activeUserRequests + activeBackgroundRequests) < maxConcurrentRequestsWhileUserActive
        case .background:
            return activeBackgroundRequests < maxConcurrentBackgroundRequests
                && activeUserRequests == 0
                && waitingUserRequests.isEmpty
        }
    }

    private func release(priority: SteamWorkshopDetailRequestPriority) {
        switch priority {
        case .userInitiated:
            activeUserRequests = max(0, activeUserRequests - 1)
        case .background:
            activeBackgroundRequests = max(0, activeBackgroundRequests - 1)
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        if canAcquire(priority: .userInitiated), let continuation = waitingUserRequests.first {
            waitingUserRequests.removeFirst()
            // Count the handoff before resuming so background work cannot
            // consume the user's permit while its task is waiting to run.
            reserve(priority: .userInitiated)
            continuation.resume()
        }

        while canAcquire(priority: .background),
              let continuation = waitingBackgroundRequests.first {
            waitingBackgroundRequests.removeFirst()
            reserve(priority: .background)
            continuation.resume()
        }
    }
}
