import Foundation
import Darwin

/// Steam helper 的双管道传输抽象：生产走 DaemonProcessTransport 适配，
/// 离线测试注入 fake（SK1.2）。帧由 SteamServiceFrameReader 层负责，传输只看字节。
protocol SteamServiceTransporting: AnyObject {
    var isRunning: Bool { get }
    var onOutput: ((Data) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onTermination: ((Int32) -> Void)? { get set }

    func start() throws
    @discardableResult func send(_ data: Data) -> Bool
    func closeInput()
    func terminate()
    func scheduleForcedTermination(after delay: TimeInterval)
}

/// DaemonProcessTransport 的协议适配（同一进程模型，不引入第二套传输实现）。
final class SteamServiceProcessTransport: SteamServiceTransporting {
    private let daemonTransport: DaemonProcessTransport

    var onOutput: ((Data) -> Void)? {
        get { daemonTransport.onOutput }
        set { daemonTransport.onOutput = newValue }
    }

    var onError: ((String) -> Void)? {
        get { daemonTransport.onError }
        set { daemonTransport.onError = newValue }
    }

    var onTermination: ((Int32) -> Void)? {
        get { daemonTransport.onTermination }
        set { daemonTransport.onTermination = newValue }
    }

    var isRunning: Bool { daemonTransport.isRunning }

    init(executableURL: URL, arguments: [String]) {
        daemonTransport = DaemonProcessTransport(executableURL: executableURL, arguments: arguments)
    }

    func start() throws { try daemonTransport.start() }

    func send(_ data: Data) -> Bool { daemonTransport.send(data) }

    func closeInput() { daemonTransport.closeInput() }

    func terminate() { daemonTransport.terminate() }

    func scheduleForcedTermination(after delay: TimeInterval) {
        let target = daemonTransport
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            guard target.process.isRunning else { return }
            kill(target.process.processIdentifier, SIGKILL)
        }
    }
}

/// Steam helper 生命周期客户端（SK1.2）。
///
/// 职责：spawn/握手（binary+protocol identity）、request correlation、超时/取消、
/// EOF/崩溃 typed state、有界重启（DaemonRestartBackoff）。由 SteamWorkshop 模块统一
/// 持有；不接 playback multiplexer，不承担登录/查询/下载业务。
/// 陈旧回包防线：requestId 与 session generation 绑定，重启后旧代 pending 全部
/// typed 失败，旧 requestId 的迟到回包直接丢弃。
@MainActor
final class SteamServiceClient {
    struct HelperIdentity: Equatable {
        let protocolVersion: Int
        let helperVersion: String
        let capabilities: [String]
        let sessionGeneration: UInt64
    }

    enum ClientState: Equatable {
        case idle
        case connecting
        case ready(HelperIdentity)
        case incompatibleProtocol(reportedVersion: Int?)
        case executableMissing(executablePath: String)
        case connectionLost(reason: String)
        case terminated
    }

    enum RequestError: LocalizedError, Equatable {
        case notReady
        case cancelled
        case requestTimedOut
        case connectionLost
        case incompatibleProtocol
        case helperError(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .notReady:
                return "Steam 服务组件不可用，请重新安装或更新 App 后重试。"
            case .cancelled:
                return "操作已取消。"
            case .requestTimedOut:
                return "Steam 服务响应超时，请稍后重试。"
            case .connectionLost:
                return "Steam 服务连接已中断，请重试。"
            case .incompatibleProtocol:
                return "Steam 服务版本不兼容，请更新或重新安装 App。"
            case .helperError(_, let message):
                return message
            }
        }
    }

    var state: ClientState = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((ClientState) -> Void)?
    // 非终态事件（authState/downloadProgress 等）统一走观察者注册表
    // （addEventObserver；SK4.2 起不再保留单观察者属性作为第二真值）。
    private var eventObservers: [UUID: (SteamServiceFrame) -> Void] = [:]

    /// SK4.2：多观察者事件订阅（下载进度与认证状态并存）。
    @discardableResult
    func addEventObserver(_ handler: @escaping (SteamServiceFrame) -> Void) -> UUID {
        let id = UUID()
        eventObservers[id] = handler
        return id
    }

    func removeEventObserver(_ id: UUID) {
        eventObservers[id] = nil
    }

    private func dispatchEvent(_ frame: SteamServiceFrame) {
        for handler in eventObservers.values {
            handler(frame)
        }
    }

    /// SK2.3：账号代际。换号/退出递增，随请求出站；旧账号迟到响应据此判废。
    var accountEpoch = 0 {
        didSet {
            guard oldValue != accountEpoch else { return }
            for id in pendingRequests.compactMap({ $0.value.accountEpoch != nil ? $0.key : nil }) {
                failPending(requestId: id, error: .cancelled)
            }
        }
    }

    var currentIdentity: HelperIdentity? {
        if case .ready(let identity) = state { return identity }
        return nil
    }

    private let executablePath: String?
    private let handshakeTimeout: TimeInterval
    private let maximumRestartAttempts: Int
    private let transportFactory: (URL) -> any SteamServiceTransporting
    private var transport: (any SteamServiceTransporting)?
    private var frames = DaemonNewlineFrameBuffer()
    private var sessionGeneration: UInt64 = 0
    private var requestSequence = 0
    private var restartBackoff = DaemonRestartBackoff(maximumDelay: 8)
    private var restartWorkItem: DispatchWorkItem?
    private var handshakeTimeoutWorkItem: DispatchWorkItem?
    private var isStopping = false
    private var timeoutWorkItems: [String: DispatchWorkItem] = [:]

    private struct PendingRequest {
        let generation: UInt64
        let accountEpoch: Int?
        let continuation: CheckedContinuation<SteamServiceFrame, Error>
    }

    private var pendingRequests: [String: PendingRequest] = [:]

    /// - Parameters:
    ///   - executablePath: helper 启动可执行文件；nil 时走 HelperLocator 定位。
    ///   - transportFactory: 可注入 fake transport（离线测试）。
    init(
        executablePath: String? = nil,
        handshakeTimeout: TimeInterval = 12,
        maximumRestartAttempts: Int = 3,
        transportFactory: ((URL) -> any SteamServiceTransporting)? = nil
    ) {
        self.executablePath = executablePath
        self.handshakeTimeout = handshakeTimeout
        self.maximumRestartAttempts = maximumRestartAttempts
        self.transportFactory = transportFactory ?? { url in
            SteamServiceProcessTransport(executableURL: url, arguments: [])
        }
    }

    deinit {
        restartWorkItem?.cancel()
        handshakeTimeoutWorkItem?.cancel()
    }

    // MARK: - 生命周期

    /// 按需启动：spawn helper 并等待握手。已在 ready/connecting 时幂等返回。
    func start() async throws -> HelperIdentity {
        switch state {
        case .ready:
            guard let identity = currentIdentity else { break }
            return identity
        case .connecting:
            return try await waitForHandshake()
        case .incompatibleProtocol:
            throw RequestError.incompatibleProtocol
        case .terminated:
            // A new explicit start can recover after the automatic retry budget
            // is exhausted; automatic retries never enter through this state.
            restartBackoff.reset()
        default:
            break
        }

        guard let resolvedPath = executablePath ?? Self.locateHelperExecutable() else {
            state = .executableMissing(executablePath: executablePath ?? "(unset)")
            throw RequestError.notReady
        }

        isStopping = false
        sessionGeneration += 1
        let generation = sessionGeneration
        state = .connecting
        frames = DaemonNewlineFrameBuffer()

        let transport = transportFactory(URL(fileURLWithPath: resolvedPath))
        transport.onOutput = { [weak self] data in
            MainActor.assumeIsolated {
                guard self?.sessionGeneration == generation else { return }
                self?.handleOutput(data)
            }
        }
        transport.onError = { [weak self] text in
            MainActor.assumeIsolated {
                // stderr 仅诊断；协议面不消费。
                _ = self
            }
        }
        transport.onTermination = { [weak self] status in
            MainActor.assumeIsolated {
                guard self?.sessionGeneration == generation else { return }
                self?.handleTermination(exitStatus: status)
            }
        }

        do {
            try transport.start()
        } catch {
            self.transport = nil
            state = .executableMissing(executablePath: resolvedPath)
            throw RequestError.notReady
        }
        self.transport = transport
        armHandshakeTimeout()

        return try await waitForHandshake()
    }

    /// 显式停止：发送 shutdown，超时强杀；所有 pending 以 cancelled 收口，不重启。
    func stop(shutdownTimeout: TimeInterval = 5) async {
        restartWorkItem?.cancel()
        handshakeTimeoutWorkItem?.cancel()
        isStopping = true
        failAllPending(.cancelled)

        guard let transport else {
            state = .terminated
            return
        }
        self.transport = nil
        let wasRunning = transport.isRunning
        let sentTerminal = wasRunning && transport.send(frameData(
            SteamServiceRequestBuilder.shutdown(
                requestId: nextRequestIdText(),
                processEpoch: 1,
                accountEpoch: 0
            )
        ))
        if wasRunning {
            transport.scheduleForcedTermination(after: shutdownTimeout)
            if sentTerminal {
                // 给 helper 一个有界的退出窗口；等待与其自然终止。
                await waitBriefly(forTerminationOf: transport, limit: shutdownTimeout)
            }
        }
        transport.terminate()
        state = .terminated
    }

    // MARK: - 请求

    /// 发送一条命令并等待其唯一 terminal；每 requestId 至多消费一个回包。
    /// timeout 为 nil 表示无限等待（认证等长流程），取消走 cancel 路径。
    func request(
        command: String,
        authAttemptId: String? = nil,
        queryGeneration: Int? = nil,
        cursor: String? = nil,
        jobId: String? = nil,
        attempt: Int? = nil,
        payload: SteamServiceJSON? = nil,
        private privatePayload: SteamServiceJSON? = nil,
        timeout: TimeInterval? = SteamServiceProtocol.requestTimeout,
        awaitRemoteTerminalAcrossAccountEpochChanges: Bool = false
    ) async throws -> SteamServiceFrame {
        let capturedEpoch = accountEpoch
        let accountScoped = ["loginPassword", "loginQR", "restoreSession", "listSubscriptions",
                             "listFavorites", "querySubscriptionStates", "setSubscription", "startDownload"].contains(command)
        try Task.checkCancellation()
        // Process readiness is independent of account authentication. Public queries
        // can start the helper without creating a login attempt or opening UI.
        if state == .idle || state == .connecting {
            _ = try await start()
        }
        try Task.checkCancellation()
        guard case .ready = state, let transport else {
            throw RequestError.notReady
        }
        guard !accountScoped || capturedEpoch == accountEpoch else { throw RequestError.cancelled }
        let isControl = ["shutdown", "logout", "cancelAuthentication", "cancelDownload", "submitChallenge"].contains(command)
        // Keep teardown/Guard responsive even when all business slots are occupied.
        let requestLimit = SteamServiceProtocol.maxPendingRequests + (isControl ? 8 : 0)
        guard pendingRequests.count < requestLimit else {
            throw RequestError.helperError(code: "rateLimited", message: "request capacity exceeded")
        }
        requestSequence += 1
        let requestId = "req-\(sessionGeneration)-\(requestSequence)"
        guard let data = SteamServiceRequestBuilder.request(
            requestId: requestId,
            command: command,
            processEpoch: 1,
            accountEpoch: accountEpoch,
            authAttemptId: authAttemptId,
            queryGeneration: queryGeneration,
            cursor: cursor,
            jobId: jobId,
            attempt: attempt,
            payload: payload,
            private: privatePayload
        ) else {
            throw RequestError.notReady
        }
        guard data.count <= SteamServiceProtocol.maxFrameBytes + 1 else {
            throw RequestError.helperError(code: "protocolMismatch", message: "request frame exceeds limit")
        }
        return try await withTaskCancellationHandler(operation: {
          try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = PendingRequest(
                generation: sessionGeneration,
                accountEpoch: accountScoped && !awaitRemoteTerminalAcrossAccountEpochChanges
                    ? capturedEpoch
                    : nil,
                continuation: continuation
            )
            // Register before send: an injectable transport may reply synchronously.
            guard transport.send(data) else {
                failPending(requestId: requestId, error: .connectionLost)
                return
            }
            guard pendingRequests[requestId] != nil else { return }
            guard let timeout else { return }
            let workItem = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.failPending(requestId: requestId, error: .requestTimedOut)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
            timeoutWorkItems[requestId] = workItem
          }
        }, onCancel: { [weak self] in
            guard let client = self else { return }
            Task { @MainActor in client.failPending(requestId: requestId, error: .cancelled) }
        })
    }

    // MARK: - 定位（开发 route：env 覆盖；产品 route：app bundle Helpers）

    static func locateHelperExecutable() -> String? {
        if let override = ProcessInfo.processInfo.environment["MWX_STEAM_HELPER_COMMAND"] {
            return override.isEmpty ? nil : override
        }
        if let bundled = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("SteamService", isDirectory: true)
            .appendingPathComponent("SteamService")
            .path,
           FileManager.default.isExecutableFile(atPath: bundled)
        {
            return bundled
        }
        return nil
    }

    // MARK: - 私有状态机

    private func handleOutput(_ data: Data) {
        for frame in frames.append(data) {
            guard frame.count <= SteamServiceProtocol.maxFrameBytes else {
                failProtocolConnection(reason: "frame exceeded 1 MiB limit")
                return
            }
            guard let line = String(data: frame, encoding: .utf8) else { continue }
            switch SteamServiceFrameDecoder.decode(line) {
            case .failure(let error):
                // 单个坏帧不锁死连接；只记诊断并丢弃。
                NSLog("[SteamServiceClient] dropped malformed frame: \(error)")
            case .success(let decoded):
                handleFrame(decoded)
            }
        }
        if frames.pendingByteCount > SteamServiceProtocol.maxFrameBytes {
            // §6 帧上限：上限内无换行边界即视为协议破坏，有界断开。
            failProtocolConnection(reason: "frame buffer exceeded 1 MiB limit")
        }
    }

    private func handleFrame(_ frame: SteamServiceFrame) {
        if case .connecting = state {
            resolveHandshake(frame)
            return
        }
        guard case .ready = state else { return }

        guard frame.frameType == "event" else {
            // result：只消费当前代 pending 中已知的 requestId；其余视为陈旧丢弃。
            guard let requestId = frame.requestId,
                  let pending = pendingRequests.removeValue(forKey: requestId) else {
                return
            }
            if let workItem = timeoutWorkItems.removeValue(forKey: requestId) {
                workItem.cancel()
            }
            if let epoch = pending.accountEpoch,
               epoch != accountEpoch || (frame.accountEpoch != nil && frame.accountEpoch != epoch)
                || (frame.ok == true && frame.accountEpoch == nil) {
                pending.continuation.resume(throwing: RequestError.cancelled)
            } else if frame.ok == true {
                pending.continuation.resume(returning: frame)
            } else if let error = frame.error {
                pending.continuation.resume(throwing: RequestError.helperError(
                    code: error.code,
                    message: error.message
                ))
            } else {
                pending.continuation.resume(throwing: RequestError.connectionLost)
            }
            return
        }

        // 事件：进行中任务的进度照常投递；未知 requestId 的事件也投递给业务侧过滤。
        dispatchEvent(frame)
    }

    private func resolveHandshake(_ frame: SteamServiceFrame) {
        handshakeTimeoutWorkItem?.cancel()
        if frame.frameType == "ready" {
            let version = frame.protocolVersion ?? -1
            guard version == SteamServiceProtocol.version, let helperVersion = frame.helperVersion else {
                state = .incompatibleProtocol(reportedVersion: version == -1 ? nil : version)
                retireTransport()
                return
            }
            let identity = HelperIdentity(
                protocolVersion: version,
                helperVersion: helperVersion,
                capabilities: frame.capabilities ?? [],
                sessionGeneration: sessionGeneration
            )
            state = .ready(identity)
            return
        }
        // 握手期收到非 ready 帧：视为协议失配。
        state = .incompatibleProtocol(reportedVersion: nil)
        retireTransport()
    }

    private func waitForHandshake() async throws -> HelperIdentity {
        while true {
            try Task.checkCancellation()
            switch state {
            case .ready(let identity):
                return identity
            case .incompatibleProtocol:
                throw RequestError.incompatibleProtocol
            case .connectionLost, .terminated, .executableMissing:
                throw RequestError.connectionLost
            default:
                break
            }
            await waitBriefly()
        }
    }

    private func armHandshakeTimeout() {
        handshakeTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .connecting = self.state else { return }
                self.retireTransport()
                self.state = .connectionLost(reason: "handshake timeout")
                self.handleUnexpectedStop()
            }
        }
        handshakeTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout, execute: workItem)
    }

    private func handleTermination(exitStatus: Int32) {
        // stop() 之后的终止回调（含强制杀进程）按预期关停处理，不再触发重启。
        let expectedShutdown = isStopping
        transport = nil
        if expectedShutdown {
            return
        }
        state = .connectionLost(reason: "helper exited with status \(exitStatus)")
        failAllPending(.connectionLost)
        handleUnexpectedStop()
    }

    /// 有界重启：ready 不重置失败计数，防止 ready/崩溃循环无限重启。
    private func handleUnexpectedStop() {
        guard !isStopping else { return }
        restartWorkItem?.cancel()
        guard restartBackoff.consecutiveFailureCount < maximumRestartAttempts else {
            state = .terminated
            return
        }
        let delay = restartBackoff.nextDelay()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopping else { return }
                self.state = .idle
                Task { @MainActor in
                    _ = try? await self.start()
                }
            }
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func retireTransport() {
        guard let previous = transport else { return }
        transport = nil
        previous.onOutput = nil
        previous.onError = nil
        previous.onTermination = nil
        previous.scheduleForcedTermination(after: 1)
        previous.terminate()
    }

    private func failProtocolConnection(reason: String) {
        retireTransport()
        state = .connectionLost(reason: reason)
        failAllPending(.connectionLost)
        handleUnexpectedStop()
    }

    private func failPending(requestId: String, error: RequestError) {
        guard let pending = pendingRequests.removeValue(forKey: requestId) else { return }
        if let workItem = timeoutWorkItems.removeValue(forKey: requestId) {
            workItem.cancel()
        }
        pending.continuation.resume(throwing: error)
    }

    private func failAllPending(_ error: RequestError) {
        let requests = pendingRequests
        pendingRequests.removeAll()
        timeoutWorkItems.values.forEach { $0.cancel() }
        timeoutWorkItems.removeAll()
        for pending in requests.values {
            pending.continuation.resume(throwing: error)
        }
    }

    private func nextRequestIdText() -> String {
        requestSequence += 1
        return "req-\(sessionGeneration)-\(requestSequence)"
    }

    private func frameData(_ data: Data?) -> Data { data ?? Data() }

    /// 轮询等待（仅测试/关停窗口用；产品请求路径走 continuation）。
    private func waitBriefly(forTerminationOf target: (any SteamServiceTransporting)? = nil, limit: TimeInterval) async {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if let target {
                if !target.isRunning { return }
            } else if case .ready = state {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitBriefly() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
