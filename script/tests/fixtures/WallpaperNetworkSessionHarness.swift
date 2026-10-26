import Foundation

private final class SessionProtocol: URLProtocol, @unchecked Sendable {
    nonisolated static let probe = RequestProbe()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.probe.started(request.url!)
        guard !request.url!.path.hasPrefix("/held") else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fixture".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.probe.stopped(request.url!) }
}

nonisolated private final class RequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = Set<URL>()
    private var stops = Set<URL>()
    private var waiting: [URL: CheckedContinuation<Void, Never>] = [:]

    func started(_ url: URL) {
        lock.lock()
        starts.insert(url)
        let continuation = waiting.removeValue(forKey: url)
        lock.unlock()
        continuation?.resume()
    }
    func stopped(_ url: URL) { lock.lock(); stops.insert(url); lock.unlock() }
    func didStart(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return starts.contains(url) }
    func didStop(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return stops.contains(url) }
    func waitForStart(_ url: URL) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if starts.contains(url) { lock.unlock(); continuation.resume() }
            else { waiting[url] = continuation; lock.unlock() }
        }
    }
}

nonisolated private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [ObjectIdentifier] = []
    func record(_ handle: WallpaperNetworkSession) { lock.lock(); handles.append(ObjectIdentifier(handle)); lock.unlock() }
    func count(for handle: WallpaperNetworkSession) -> Int {
        lock.lock(); defer { lock.unlock() }
        return handles.filter { $0 == ObjectIdentifier(handle) }.count
    }
}

private actor StartGate {
    private var open = false
    private var waiting: CheckedContinuation<Void, Never>?
    func wait() async { if !open { await withCheckedContinuation { waiting = $0 } } }
    func release() { open = true; waiting?.resume(); waiting = nil }
}

private final class TaskPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {}
private final class SessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {}

@main private struct Checks {
    nonisolated static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    nonisolated static func request(_ path: String) -> URLRequest { URLRequest(url: URL(string: "https://fixture.invalid/" + path)!) }
    static func makeSession(delegate: (any URLSessionDelegate)? = nil,
                            onCompletion: (@Sendable (WallpaperNetworkSession) -> Void)? = nil) -> (URLSession, WallpaperNetworkSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionProtocol.self]
        configuration.urlCache = nil
        let raw = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return (raw, WallpaperNetworkSession(raw, onCompletion: onCompletion))
    }
    static func expectCancellation(_ task: Task<(Data, URLResponse), Error>) async throws {
        do { _ = try await task.value; fatalError("canceled request returned data") }
        catch is CancellationError {}
        catch let error as URLError { expect(error.code == .cancelled, "cancellation keeps its error meaning") }
    }

    static func main() async throws {
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            fatalError("network-session lifetime fixture did not finish")
        }
        defer { watchdog.cancel() }

        let delegate = SessionDelegate()
        let (raw, lifetime) = makeSession(delegate: delegate)
        expect(raw.delegate === delegate, "original session delegate remains installed")
        let cookie = HTTPCookie(properties: [.domain: "fixture.invalid", .path: "/", .name: "fixture", .value: "local-only"])!
        lifetime.configuration.httpCookieStorage?.setCookie(cookie)
        expect(raw.configuration.httpCookieStorage?.cookies?.contains { $0.name == "fixture" } == true,
            "configuration preserves the source's isolated cookie storage")

        let policy = TaskPolicy()
        let delegatedRequest = request("held-delegate")
        let delegated = Task { try await lifetime.data(for: delegatedRequest, delegate: policy) }
        await SessionProtocol.probe.waitForStart(delegatedRequest.url!)
        let tasks = await withCheckedContinuation { continuation in raw.getAllTasks { continuation.resume(returning: $0) } }
        expect(tasks.first { $0.originalRequest?.url == delegatedRequest.url }?.delegate === policy,
            "per-task redirect policy is installed on the real Foundation task")
        delegated.cancel()
        try await expectCancellation(delegated)
        let (data, _) = try await lifetime.data(for: request("after-individual-cancel"))
        expect(data == Data("fixture".utf8), "canceling one consumer does not retire the session")

        let gate = StartGate()
        let earlyRequest = request("cancel-before-create")
        let early = Task { await gate.wait(); return try await lifetime.data(for: earlyRequest) }
        early.cancel()
        await gate.release()
        try await expectCancellation(early)
        expect(!SessionProtocol.probe.didStart(earlyRequest.url!), "pre-canceled calls do not start HTTP")

        let activeRequest = request("held-retirement")
        let active = Task { try await lifetime.data(for: activeRequest) }
        await SessionProtocol.probe.waitForStart(activeRequest.url!)
        lifetime.retire()
        lifetime.retire()
        try await expectCancellation(active)
        expect(SessionProtocol.probe.didStop(activeRequest.url!), "retirement cancels an already-created real task")
        let delayedRequest = request("delayed-after-retirement")
        do {
            _ = try await lifetime.data(for: delayedRequest)
            fatalError("retired lifetime admitted a new task")
        } catch is CancellationError {}
        expect(!SessionProtocol.probe.didStart(delayedRequest.url!), "delayed cached handles fail before Foundation task creation")

        let (_, racing) = makeSession()
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<24 {
                group.addTask {
                    do { _ = try await racing.data(for: request("race-\(index)")); return true }
                    catch is CancellationError { return true }
                    catch let error as URLError { return error.code == .cancelled }
                    catch { return false }
                }
            }
            group.addTask { racing.retire(); return true }
            for await result in group { expect(result, "creation/retirement race only succeeds or cancels") }
        }
        let completions = CompletionProbe()
        let (completionRaw, completionLifetime) = makeSession(onCompletion: { completions.record($0) })
        expect(completionRaw.delegate == nil, "completion hook needs no legacy session delegate")
        let nilDelegateRequest = request("completion-nil-task-delegate")
        _ = try await completionLifetime.data(for: nilDelegateRequest)
        expect(completions.count(for: completionLifetime) == 1, "nil task delegate emits one handle completion")
        let policyRequest = request("completion-explicit-task-delegate")
        _ = try await completionLifetime.data(for: policyRequest, delegate: TaskPolicy())
        expect(completions.count(for: completionLifetime) == 2, "explicit task policy still emits exactly one handle completion")
        let canceledRequest = request("held-completion-cancel")
        let canceled = Task { try await completionLifetime.data(for: canceledRequest) }
        await SessionProtocol.probe.waitForStart(canceledRequest.url!)
        canceled.cancel()
        try await expectCancellation(canceled)
        expect(completions.count(for: completionLifetime) == 3, "real task cancellation emits exactly one completion")
        completionLifetime.retire()
        do { _ = try await completionLifetime.data(for: request("completion-retired")); fatalError("retired completion lifetime admitted a task") }
        catch is CancellationError {}
        expect(completions.count(for: completionLifetime) == 3, "rejection without a Foundation task does not fabricate completion")
        weak var releasedHandle: WallpaperNetworkSession?
        do {
            let (_, temporary) = makeSession(onCompletion: { completions.record($0) })
            releasedHandle = temporary
            _ = try await temporary.data(for: request("completion-release"))
        }
        expect(releasedHandle == nil, "completion hook does not retain the handle in a cycle")
        print("Wallpaper network-session lifetime checks passed")
    }
}
