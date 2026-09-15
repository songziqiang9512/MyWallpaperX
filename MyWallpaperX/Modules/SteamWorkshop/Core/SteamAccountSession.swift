import Foundation

/// SK2.1：认证会话消费点（Swift 侧 AccountSession）。
///
/// 把 SteamServiceClient 的 loginPassword/loginQR/restoreSession/submitChallenge/
/// cancelAuthentication 命令族包装成带类型化阶段的 API；authState 事件在此映射为
/// AuthPhase。只封装命令与状态，不持有凭据（令牌由调用方交 Keychain，SK2.3），
/// 不做任何 UI 决策，也不存在自动登录路径。
@MainActor
final class SteamAccountSession {
    enum AuthPhase: Equatable {
        case idle
        case connecting
        case authenticating
        case awaitingDeviceConfirmation
        case awaitingDeviceCode(previousCodeWasIncorrect: Bool)
        case awaitingEmailCode(emailDomain: String?, previousCodeWasIncorrect: Bool)
        case qrChallenge(url: String)
        case online(steamId: String, accountName: String?)
        case failed(code: String, message: String)
        case cancelled
    }

    private(set) var phase: AuthPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }

    var onPhaseChange: ((AuthPhase) -> Void)?
    private(set) var activeAttemptId: String?
    private var completedAttemptId: String?
    private var activeRequest: Task<SteamServiceFrame, Error>?

    /// 最近一次登录成功返回的会话令牌（仅驻内存；持久化由 SteamAuthRoute/
    /// TokenStore 决定）。accountName 为真实名（private 包装），供令牌持久化。
    private(set) var lastSessionTokens: (refreshToken: String, guardData: String?, accountName: String?)?

    /// 登出/换号时清空内存令牌（不留旧账号会话状态）。
    func clearSessionTokens() {
        lastSessionTokens = nil
    }

    private let client: SteamServiceClient
    private var eventObserverID: UUID?

    init(client: SteamServiceClient) {
        self.client = client
        eventObserverID = client.addEventObserver { [weak self] frame in
            self?.handleEvent(frame)
        }
    }

    /// 密码登录。返回在线后的 SteamID；凭据仅经 private 包装出站。
    func loginPassword(username: String, password: String) async throws -> String {
        let payload = SteamServiceJSON.object(["username": .string(username)])
        let privatePayload = SteamServiceJSON.object(["password": .string(password)])
        let frame = try await beginAuth(
            command: "loginPassword",
            payload: payload,
            privatePayload: privatePayload
        )
        return try steamId(from: frame)
    }

    /// 二维码登录。阶段经 onPhaseChange(qrChallenge) 报出挑战链接。
    func loginQR() async throws -> String {
        let frame = try await beginAuth(command: "loginQR", payload: nil, privatePayload: nil)
        return try steamId(from: frame)
    }

    /// 已保存令牌静默恢复（Keychain 偏好允许时由 SK2.3 调用）。
    func restore(refreshToken: String, accountName: String?) async throws -> String {
        let payload = accountName.map { SteamServiceJSON.object(["accountName": .string($0)]) }
        let privatePayload = SteamServiceJSON.object(["refreshToken": .string(refreshToken)])
        let frame = try await beginAuth(
            command: "restoreSession",
            payload: payload,
            privatePayload: privatePayload
        )
        return try steamId(from: frame)
    }

    /// 提交 Guard 验证码（仅当前活动 attempt 接受）。
    func submit(code: String) async {
        guard let attemptId = activeAttemptId else { return }
        _ = try? await client.request(
            command: "submitChallenge",
            authAttemptId: attemptId,
            payload: .object(["code": .string(code)])
        )
    }

    /// Invalidate synchronously, before a window closes or another attempt starts.
    /// The detached control request targets this exact attempt, never its successor.
    @discardableResult
    func cancelCurrentAttempt(includingUnadoptedResult: Bool = false) -> Task<Void, Never>? {
        guard let attemptId = activeAttemptId ?? (includingUnadoptedResult ? completedAttemptId : nil) else { return nil }
        completedAttemptId = nil
        activeAttemptId = nil
        activeRequest?.cancel()
        activeRequest = nil
        lastSessionTokens = nil
        phase = .cancelled
        return sendCancellation(attemptId)
    }

    func cancel() async {
        await cancelCurrentAttempt()?.value
    }

    private func sendCancellation(_ attemptId: String) -> Task<Void, Never> {
        let client = client
        return Task {
            guard client.currentIdentity != nil else { return }
            _ = try? await client.request(command: "cancelAuthentication", authAttemptId: attemptId)
        }
    }

    private func beginAuth(
        command: String,
        payload: SteamServiceJSON?,
        privatePayload: SteamServiceJSON?
    ) async throws -> SteamServiceFrame {
        try Task.checkCancellation()
        cancelCurrentAttempt()
        let attemptId = UUID().uuidString
        activeAttemptId = attemptId
        completedAttemptId = nil
        lastSessionTokens = nil
        phase = .connecting
        let request = Task { [client] in
            try await client.request(command: command, authAttemptId: attemptId,
                                     payload: payload, private: privatePayload, timeout: nil)
        }
        activeRequest = request
        do {
            let frame = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: {
                request.cancel()
            }
            try Task.checkCancellation()
            guard activeAttemptId == attemptId, frame.authAttemptId == attemptId else {
                throw CancellationError()
            }
            let id = try steamId(from: frame)
            if let secrets = frame.root["private"]?.objectValue,
               let refreshToken = secrets["refreshToken"]?.stringValue {
                lastSessionTokens = (refreshToken, secrets["guardData"]?.stringValue,
                                     secrets["accountName"]?.stringValue)
            }
            completedAttemptId = attemptId
            activeAttemptId = nil
            activeRequest = nil
            phase = .online(steamId: id, accountName: frame.root["data"]?.objectValue?["accountName"]?.stringValue)
            return frame
        } catch {
            // Local request cancellation alone does not stop helper polling.
            if activeAttemptId == attemptId {
                _ = sendCancellation(attemptId)
                activeAttemptId = nil
                activeRequest = nil
                lastSessionTokens = nil
                if Task.isCancelled || error is CancellationError ||
                    error as? SteamServiceClient.RequestError == .cancelled {
                    phase = .cancelled
                } else if case SteamServiceClient.RequestError.helperError(let code, let message) = error {
                    phase = .failed(code: code, message: message)
                } else {
                    phase = .failed(code: "network", message: error.localizedDescription)
                }
            }
            throw error
        }
    }

    private func handleEvent(_ frame: SteamServiceFrame) {
        guard frame.event == "authState", let attemptId = activeAttemptId,
              frame.authAttemptId == attemptId else { return }
        guard let state = frame.root["state"]?.stringValue else { return }
        switch state {
        case "connecting":
            phase = .connecting
        case "authenticating":
            phase = .authenticating
        case "awaitingDeviceConfirmation":
            phase = .awaitingDeviceConfirmation
        case "awaitingDeviceCode":
            phase = .awaitingDeviceCode(
                previousCodeWasIncorrect: frame.root["previousCodeWasIncorrect"]?.boolValue ?? false)
        case "awaitingEmailCode":
            phase = .awaitingEmailCode(
                emailDomain: frame.root["emailDomain"]?.stringValue,
                previousCodeWasIncorrect: frame.root["previousCodeWasIncorrect"]?.boolValue ?? false)
        case "qrChallenge":
            if let url = frame.root["challengeUrl"]?.stringValue {
                phase = .qrChallenge(url: url)
            }
        case "online":
            break // online 以 login 调用的 terminal 为准
        case "failed":
            phase = .failed(
                code: "authExpired",
                message: frame.root["message"]?.stringValue ?? "认证失败"
            )
        default:
            break
        }
    }

    private func steamId(from frame: SteamServiceFrame) throws -> String {
        guard let steamId = frame.root["data"]?.objectValue?["steamId"]?.stringValue,
              !steamId.isEmpty else {
            throw SteamServiceClient.RequestError.connectionLost
        }
        return steamId
    }
}
