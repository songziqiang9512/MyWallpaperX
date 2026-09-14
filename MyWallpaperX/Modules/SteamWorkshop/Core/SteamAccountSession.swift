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

    private let client: SteamServiceClient

    init(client: SteamServiceClient) {
        self.client = client
        client.onEvent = { [weak self] frame in
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

    /// 取消当前认证流；login 调用将以 cancelled 失败收口。
    func cancel() async {
        guard activeAttemptId != nil else { return }
        _ = try? await client.request(command: "cancelAuthentication")
        activeAttemptId = nil
        phase = .cancelled
    }

    // MARK: - 私有

    private func beginAuth(
        command: String,
        payload: SteamServiceJSON?,
        privatePayload: SteamServiceJSON?
    ) async throws -> SteamServiceFrame {
        phase = .connecting
        let frame = try await client.request(
            command: command,
            payload: payload,
            private: privatePayload,
            timeout: nil
        )
        if let steamId = frame.root["data"]?.objectValue?["steamId"]?.stringValue {
            activeAttemptId = nil
            phase = .online(steamId: steamId, accountName: frame.root["data"]?.objectValue?["accountName"]?.stringValue)
        }
        return frame
    }

    private func handleEvent(_ frame: SteamServiceFrame) {
        guard frame.event == "authState" else { return }
        if let attemptId = frame.authAttemptId {
            activeAttemptId = attemptId
        }
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
            phase = .failed(code: "authExpired", message: state)
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
