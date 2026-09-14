//
//  SteamAuthRoute.swift
//  MyWallpaperX
//

import Foundation
import Combine

/// SK2.2：新登录路线（SteamKit helper）的产品权威。
///
/// 包装 SteamServiceClient + SteamAccountSession，向 UI 暴露可观察的登录状态。
/// 合同：登录只由用户主动触发；迟到的 phase 变更不得打开任何窗口（本类不持有
/// UI 引用，面板自行判断可见性）；令牌在 login 返回时交给 Keychain 调用方
/// （SK2.3），本类不持久化任何凭据。
@MainActor
final class SteamAuthRoute: ObservableObject {
    @Published private(set) var phase: SteamAccountSession.AuthPhase = .idle
    @Published private(set) var steamId: String?
    @Published private(set) var accountName: String?

    let client: SteamServiceClient
    private let accountSession: SteamAccountSession

    init(client: SteamServiceClient) {
        self.client = client
        self.accountSession = SteamAccountSession(client: client)
        accountSession.onPhaseChange = { [weak self] phase in
            self?.phase = phase
        }
    }

    var isOnline: Bool { steamId != nil }

    /// 工具栏展示态（§3.1）。
    enum DisplayState: Equatable {
        case signedOut
        case connecting
        case awaitingInput
        case online
        case failed(message: String)
    }

    var displayState: DisplayState {
        if isOnline { return .online }
        switch phase {
        case .idle, .cancelled, .failed:
            if case .failed(let code, let message) = phase {
                return .failed(message: "\(code): \(message)")
            }
            return .signedOut
        case .connecting, .authenticating, .qrChallenge:
            return .connecting
        case .awaitingDeviceConfirmation, .awaitingDeviceCode, .awaitingEmailCode:
            return .awaitingInput
        case .online:
            return .online
        }
    }

    /// 密码登录；成功返回 SteamID。首次调用负责把 helper 拉起（幂等）。
    func loginPassword(username: String, password: String) async throws -> String {
        try await ensureHelperReady()
        let id = try await accountSession.loginPassword(username: username, password: password)
        adoptOnline(steamId: id)
        return id
    }

    /// 二维码登录；成功返回 SteamID。
    func loginQR() async throws -> String {
        try await ensureHelperReady()
        let id = try await accountSession.loginQR()
        adoptOnline(steamId: id)
        return id
    }

    /// 已保存令牌静默恢复（SK2.3 接 Keychain 偏好后调用）。
    func restore(refreshToken: String, accountName: String?) async throws -> String {
        try await ensureHelperReady()
        let id = try await accountSession.restore(refreshToken: refreshToken, accountName: accountName)
        adoptOnline(steamId: id)
        return id
    }

    private func ensureHelperReady() async throws {
        if client.currentIdentity == nil {
            _ = try await client.start()
        }
    }

    func submit(code: String) async {
        await accountSession.submit(code: code)
    }

    func cancel() async {
        await accountSession.cancel()
        phase = .idle
    }

    func signOut() async {
        // 退出以本地状态清零为准；helper 不在线时 logout 请求失败可忽略。
        if client.currentIdentity != nil {
            _ = try? await client.request(command: "logout")
        }
        steamId = nil
        accountName = nil
        phase = .idle
    }

    private func adoptOnline(steamId newId: String) {
        steamId = newId
        if case .online(let _, let name) = accountSession.phase {
            accountName = name
        }
    }
}
