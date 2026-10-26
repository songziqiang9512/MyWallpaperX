import Foundation

/// Owns URLSession task creation and invalidation as one lifetime. A cached
/// handle may outlive retirement, but can never create a task on an invalid session.
nonisolated final class WallpaperNetworkSession: @unchecked Sendable {
    private let session: URLSession
    private let onCompletion: (@Sendable (WallpaperNetworkSession) -> Void)?
    private let lock = NSLock()
    private var retired = false

    /// The creator transfers invalidation authority to this handle. Consumers
    /// receive the handle rather than keeping or invalidating the raw session.
    init(_ session: URLSession, onCompletion: (@Sendable (WallpaperNetworkSession) -> Void)? = nil) {
        self.session = session
        self.onCompletion = onCompletion
    }

    convenience init(configuration: URLSessionConfiguration, delegate: (any URLSessionDelegate)? = nil,
                     onCompletion: (@Sendable (WallpaperNetworkSession) -> Void)? = nil) {
        self.init(URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil), onCompletion: onCompletion)
    }

    deinit { retire() }

    var configuration: URLSessionConfiguration { session.configuration }
    func retire() {
        lock.lock()
        guard !retired else { lock.unlock(); return }
        retired = true
        lock.unlock()
        // Every admitted task already exists; subsequent creation sees retired.
        // Invalidation and delegate delivery never run while holding our lock.
        session.invalidateAndCancel()
    }

    func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        defer { withExtendedLifetime(self) {} }
        let cancellation = WallpaperNetworkRequestCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !retired else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let task = session.dataTask(with: request) { [weak self] data, response, error in
                    // Completion-handler tasks do not deliver session didComplete.
                    // This is the one completion event used by source cookie owners.
                    if let self { self.onCompletion?(self) }
                    if let error { continuation.resume(throwing: error) }
                    else if let data, let response { continuation.resume(returning: (data, response)) }
                    else { continuation.resume(throwing: URLError(.badServerResponse)) }
                }
                task.delegate = delegate
                lock.unlock()
                cancellation.install(task)
                task.resume()
            }
            try Task.checkCancellation()
            return result
        } onCancel: { cancellation.cancel() }
    }
}

/// Cancellation may arrive before task creation/installation. It only cancels
/// this request; retiring all requests remains the session handle's authority.
nonisolated private final class WallpaperNetworkRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func install(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let mustCancel = cancelled
        lock.unlock()
        if mustCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
