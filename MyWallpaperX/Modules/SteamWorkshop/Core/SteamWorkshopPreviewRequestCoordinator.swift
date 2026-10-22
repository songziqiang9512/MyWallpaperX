import Foundation

nonisolated enum SteamWorkshopPreviewRequestPriority: Sendable {
    case userInitiated
    case visible
    case prefetch
}

nonisolated final class SteamWorkshopPreviewLoadCancellation: ThumbnailCacheLoadCancellation, @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var cancellationHandler: (@Sendable () -> Void)?

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let handler = cancellationHandler
        cancellationHandler = nil
        lock.unlock()
        handler?()
    }

    func installCancellationHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            handler()
            return
        }
        cancellationHandler = handler
        lock.unlock()
    }

    func clearCancellationHandler() {
        lock.lock()
        cancellationHandler = nil
        lock.unlock()
    }
}

final class SteamWorkshopPreviewRequestCoordinator {
    static let shared = SteamWorkshopPreviewRequestCoordinator()

    private let session: URLSession
    private let scheduler = SteamWorkshopPreviewRequestScheduler()
    private let stateQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.failures")
    private var failureStates: [String: FailureState] = [:]

    private struct FailureState {
        var attempts: Int
        var firstFailureAt: Date
        var retryAfter: Date
        var isPermanent: Bool
    }

    init(session: URLSession) { self.session = session }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func loadData(
        from url: URL,
        priority: SteamWorkshopPreviewRequestPriority,
        ignoringBackoff: Bool = false,
        cancellation: SteamWorkshopPreviewLoadCancellation? = nil,
        priorityProvider: (@Sendable () -> SteamWorkshopPreviewRequestPriority)? = nil
    ) async -> Data? {
        guard cancellation?.cancelled != true else { return nil }
        if !ignoringBackoff, !shouldAttemptLoad(for: url, priority: priorityProvider?() ?? priority) {
            return nil
        }
        do {
            let data = try await fetchData(
                from: url,
                priority: priority,
                cancellation: cancellation, priorityProvider: priorityProvider
            )
            noteSuccess(for: url)
            return data
        } catch {
            if error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || cancellation?.cancelled == true {
                return nil
            }
            noteFailure(for: url, error: error, priority: priorityProvider?() ?? priority)
            return nil
        }
    }

    func nextRetryDelay(
        for url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> TimeInterval? {
        stateQueue.sync {
            guard let state = failureStates[url.absoluteString] else { return nil }
            if hasExceededRetryWindow(state: state, priority: priority) {
                return nil
            }
            if priority == .userInitiated {
                return 0
            }
            return max(0, state.retryAfter.timeIntervalSinceNow)
        }
    }

    func resetFailureState(for url: URL) {
        stateQueue.async {
            self.failureStates.removeValue(forKey: url.absoluteString)
        }
    }

    /// The cache promotes a shared producer when its first visible consumer
    /// joins. The provider closes the race before scheduler registration.
    func promoteVisibleRequest(for url: URL) {
        Task { await scheduler.promoteVisible(key: url.absoluteString) }
    }

    private func fetchData(
        from url: URL,
        priority: SteamWorkshopPreviewRequestPriority,
        cancellation: SteamWorkshopPreviewLoadCancellation?,
        priorityProvider: (@Sendable () -> SteamWorkshopPreviewRequestPriority)?
    ) async throws -> Data {
        let requestTask = Task { [scheduler, session] in
            try await scheduler.run(priority: priority, key: url.absoluteString, priorityProvider: priorityProvider) {
                try Task.checkCancellation()
                let effectivePriority = priorityProvider?() ?? priority
                var request = URLRequest(url: url)
                request.timeoutInterval = self.timeout(for: effectivePriority)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0",
                    forHTTPHeaderField: "User-Agent"
                )
                switch effectivePriority {
                case .userInitiated:
                    request.networkServiceType = .responsiveData
                case .visible:
                    request.networkServiceType = .responsiveData
                case .prefetch:
                    request.networkServiceType = .background
                }

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        }
        cancellation?.installCancellationHandler {
            requestTask.cancel()
        }
        defer { cancellation?.clearCancellationHandler() }
        return try await withTaskCancellationHandler {
            try await requestTask.value
        } onCancel: {
            requestTask.cancel()
        }
    }

    nonisolated private func timeout(for priority: SteamWorkshopPreviewRequestPriority) -> TimeInterval {
        switch priority {
        case .userInitiated:
            return 12
        case .visible:
            return 10
        case .prefetch:
            return 8
        }
    }

    private func shouldAttemptLoad(
        for url: URL,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> Bool {
        stateQueue.sync {
            guard let state = failureStates[url.absoluteString] else { return true }
            if hasExceededRetryWindow(state: state, priority: priority) {
                return false
            }
            if priority == .userInitiated {
                return true
            }
            return Date() >= state.retryAfter
        }
    }

    private func noteSuccess(for url: URL) {
        stateQueue.async {
            self.failureStates.removeValue(forKey: url.absoluteString)
        }
    }

    private func noteFailure(
        for url: URL,
        error: Error,
        priority: SteamWorkshopPreviewRequestPriority
    ) {
        let key = url.absoluteString
        stateQueue.async {
            let now = Date()
            let prior = self.failureStates[key]
            let nextAttempts = (prior?.attempts ?? 0) + 1
            let firstFailureAt = prior?.firstFailureAt ?? now
            let nsError = error as NSError
            let statusCode = nsError.code
            let isPermanent = statusCode == 404 || statusCode == NSURLErrorFileDoesNotExist
            let delay: TimeInterval
            if isPermanent {
                delay = 60 * 10
            } else {
                switch priority {
                case .userInitiated:
                    delay = min(8, pow(2, Double(min(nextAttempts, 3))))
                case .visible:
                    delay = min(16, pow(2, Double(min(nextAttempts + 1, 4))))
                case .prefetch:
                    delay = min(24, pow(2, Double(min(nextAttempts + 2, 5))))
                }
            }
            self.failureStates[key] = FailureState(
                attempts: nextAttempts,
                firstFailureAt: firstFailureAt,
                retryAfter: now.addingTimeInterval(delay),
                isPermanent: isPermanent
            )
        }
    }

    private func hasExceededRetryWindow(
        state: FailureState,
        priority: SteamWorkshopPreviewRequestPriority
    ) -> Bool {
        guard !state.isPermanent else { return true }
        return Date().timeIntervalSince(state.firstFailureAt) >= maxRetryWindow(for: priority)
    }

    private func maxRetryWindow(for priority: SteamWorkshopPreviewRequestPriority) -> TimeInterval {
        switch priority {
        case .userInitiated:
            return 12
        case .visible:
            return 35
        case .prefetch:
            return 18
        }
    }
}

actor SteamWorkshopPreviewRequestScheduler {
    private struct Waiter {
        let id: UUID
        let key: String?
        var priority: SteamWorkshopPreviewRequestPriority
        let continuation: CheckedContinuation<SteamWorkshopPreviewRequestPriority?, Never>
    }
    private var activeUserRequests = 0
    private var activeVisibleRequests = 0
    private var activePrefetchRequests = 0
    private var waiting: [Waiter] = []

    func run<T>(
        priority: SteamWorkshopPreviewRequestPriority,
        key: String? = nil,
        priorityProvider: (@Sendable () -> SteamWorkshopPreviewRequestPriority)? = nil,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let acquired = await acquire(priority: priority, key: key, priorityProvider: priorityProvider)
        defer { if let acquired { release(priority: acquired) } }
        // Keep the existing rethrows contract: a cancelled operation receives
        // cancellation state immediately and its own throwing API decides exit.
        return try await operation()
    }

    func promoteVisible(key: String) {
        for index in waiting.indices where waiting[index].key == key && waiting[index].priority == .prefetch {
            waiting[index].priority = .visible
        }
        resumeNextIfPossible()
    }

    private func acquire(priority: SteamWorkshopPreviewRequestPriority, key: String?,
                         priorityProvider: (@Sendable () -> SteamWorkshopPreviewRequestPriority)?) async -> SteamWorkshopPreviewRequestPriority? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                // No await between current priority and insertion: a promotion
                // either appears here or updates this registered waiter later.
                let effective = priorityProvider?() ?? priority
                waiting.append(Waiter(id: id, key: key, priority: effective, continuation: continuation))
                resumeNextIfPossible()
            }
        } onCancel: {
            Task { await self.cancelWaiting(id: id) }
        }
    }

    private func cancelWaiting(id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: nil)
        resumeNextIfPossible()
    }

    private func canAcquire(priority: SteamWorkshopPreviewRequestPriority) -> Bool {
        switch priority {
        case .userInitiated:
            return activeUserRequests < 1 && (activeUserRequests + activeVisibleRequests) < 4
        case .visible:
            return activeVisibleRequests < 4 && activeUserRequests == 0
                && !waiting.contains { $0.priority == .userInitiated }
        case .prefetch:
            return activeUserRequests == 0 && activeVisibleRequests < 2 && activePrefetchRequests < 2
                && !waiting.contains { $0.priority == .userInitiated || $0.priority == .visible }
        }
    }

    private func release(priority: SteamWorkshopPreviewRequestPriority) {
        switch priority {
        case .userInitiated: activeUserRequests -= 1
        case .visible: activeVisibleRequests -= 1
        case .prefetch: activePrefetchRequests -= 1
        }
        resumeNextIfPossible()
    }

    private func resumeNextIfPossible() {
        for priority in [SteamWorkshopPreviewRequestPriority.userInitiated, .visible, .prefetch] {
            while canAcquire(priority: priority), let index = waiting.firstIndex(where: { $0.priority == priority }) {
                let waiter = waiting.remove(at: index)
                // Reserve the slot before resuming; awakened tasks cannot all
                // observe the same free slot during one actor turn.
                switch priority {
                case .userInitiated: activeUserRequests += 1
                case .visible: activeVisibleRequests += 1
                case .prefetch: activePrefetchRequests += 1
                }
                waiter.continuation.resume(returning: priority)
            }
        }
    }
}
