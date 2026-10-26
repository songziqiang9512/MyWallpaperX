import Foundation

/// Stream-to-staging transport only. Source services own admission and publication.
nonisolated final class WallpaperFileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var expectedBytes: Int64
    let progressHandler: @MainActor (Double) -> Void
    private let stagingURL: URL
    private let configuration: URLSessionConfiguration?
    private let allowedHosts: Set<String>?
    private var completion: ((Result<URL, Error>) -> Void)?
    private let cancellationLock = NSLock()
    private var downloadTask: URLSessionDownloadTask?
    private var cancellationRequested = false
    private var finished = false
    /// 进度节流：didWriteData 每个 tick 都会回调，直发会驱动网格全量刷新；
    /// 只在距上次发出 ≥ 最小间隔、或百分比步进 ≥ 最小步进、或到达 100% 时发出。
    private static let progressEmitInterval: TimeInterval = 0.2
    private static let progressEmitStep = 0.02
    private var lastEmittedProgress: Double?
    private var lastEmittedAt: TimeInterval = 0

    init(
        expectedBytes: Int64,
        stagingURL: URL,
        configuration: URLSessionConfiguration? = nil,
        allowedHosts: Set<String>? = nil,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) {
        self.configuration = configuration
        self.allowedHosts = allowedHosts
        self.expectedBytes = expectedBytes
        self.stagingURL = stagingURL
        self.progressHandler = progressHandler
    }

    func start(from url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        start(request: URLRequest(url: url), completion: completion)
    }

    func start(request: URLRequest, completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        let configuration = self.configuration ?? URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        cancellationLock.lock()
        downloadTask = task
        let cancelled = cancellationRequested
        cancellationLock.unlock()
        if cancelled { task.cancel() }
        task.resume()
    }

    func cancel() {
        cancellationLock.lock()
        cancellationRequested = true
        let task = downloadTask
        cancellationLock.unlock()
        task?.cancel()
    }

    private var isCancelled: Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return cancellationRequested
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        guard total > 0 else { return }
        let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(total)))
        // URLSession 默认 delegate queue 串行回调，节流状态无需加锁（与 finished 同一假设）
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastEmittedProgress,
           now - lastEmittedAt < Self.progressEmitInterval,
           progress - last < Self.progressEmitStep,
           progress < 1.0 {
            return
        }
        lastEmittedProgress = progress
        lastEmittedAt = now
        Task { @MainActor in
            self.progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        do {
            guard !isCancelled else { throw URLError(.cancelled) }
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: stagingURL)
            if isCancelled {
                throw URLError(.cancelled)
            }
            finish(.success(stagingURL), session: session)
        } catch {
            finish(.failure(error), session: session)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(.failure(error), session: session)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let allowedHosts else { completionHandler(request); return }
        guard let url = request.url, url.scheme == "https", let host = url.host?.lowercased(),
              allowedHosts.contains(host) else { completionHandler(nil); return }
        completionHandler(request)
    }

    private func finish(_ result: Result<URL, Error>, session: URLSession) {
        guard !finished else { return }
        finished = true
        cancellationLock.lock()
        downloadTask = nil
        cancellationLock.unlock()
        session.finishTasksAndInvalidate()
        let callback = completion
        completion = nil
        callback?(result)
    }
}
