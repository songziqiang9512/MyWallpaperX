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
    /// SK2.3：已保存会话被服务端拒绝（过期/撤销）后的重登提示态。
    @Published private(set) var expired = false
    /// SK2.3：最近一次登录的令牌保存结果（Keychain 失败必须可见，不伪报已保存）。
    @Published private(set) var tokenSaveResult: SteamWorkshopTokenStore.TokenSaveResult = .notAttempted

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
        case expired
        case failed(message: String)
    }

    var displayState: DisplayState {
        if isOnline { return .online }
        if expired { return .expired }
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
    /// 已在线时（切换账号）先递增 epoch，旧账号会话作废（§3.3）。
    func loginPassword(username: String, password: String) async throws -> String {
        try await ensureHelperReady()
        if isOnline { client.accountEpoch += 1 }
        let id = try await accountSession.loginPassword(username: username, password: password)
        adoptOnline(steamId: id)
        persistTokenIfRemembered()
        return id
    }

    /// 二维码登录；成功返回 SteamID。
    func loginQR() async throws -> String {
        try await ensureHelperReady()
        if isOnline { client.accountEpoch += 1 }
        let id = try await accountSession.loginQR()
        adoptOnline(steamId: id)
        persistTokenIfRemembered()
        return id
    }

    /// 已保存令牌静默恢复；SteamID 与保存时不一致视为存错账号，立即登出。
    func restore(refreshToken: String, accountName: String?, expectedSteamId: String? = nil) async throws -> String {
        try await ensureHelperReady()
        let id = try await accountSession.restore(refreshToken: refreshToken, accountName: accountName)
        if let expectedSteamId, !expectedSteamId.isEmpty, expectedSteamId != id {
            await signOut()
            throw SteamServiceClient.RequestError.helperError(
                code: "authExpired",
                message: "恢复的会话与保存的账号不一致"
            )
        }
        adoptOnline(steamId: id)
        expired = false
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
        // 换号/退出统一递增 epoch，旧账号的迟到响应按旧 epoch 失效（§3.3）。
        client.accountEpoch += 1
        if client.currentIdentity != nil {
            _ = try? await client.request(command: "logout")
        }
        accountSession.clearSessionTokens()
        SteamWorkshopTokenStore.delete()
        SteamWorkshopTokenStore.clearDisplayMetadata()
        steamId = nil
        accountName = nil
        expired = false
        phase = .idle
    }

    /// 启动静默恢复被服务端拒绝（明确拒绝才标记过期并删令牌；网络失败保留）。
    func markExpired() {
        expired = true
    }

    /// SK2.3：恢复失败处置——明确拒绝删令牌；网络/其他失败保留令牌下次再试。
    enum RestoreFailureDisposition { case keepToken, deleteToken }

    nonisolated static func disposition(for error: Error) -> RestoreFailureDisposition {
        switch error as? SteamServiceClient.RequestError {
        case .helperError(let code, _):
            return (code == "authExpired" || code == "accessDenied") ? .deleteToken : .keepToken
        default:
            return .keepToken
        }
    }

    private func adoptOnline(steamId newId: String) {
        steamId = newId
        if case .online(let _, let name) = accountSession.phase {
            accountName = name
        }
    }

    /// 记住登录开启时原子保存令牌；未开启则清理该账号的持久凭据残留（§3.3）。
    private func persistTokenIfRemembered() {
        guard UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey) else {
            // 不记住：本次令牌仅驻内存，并清掉该账号可能的旧持久凭据。
            SteamWorkshopTokenStore.delete()
            tokenSaveResult = .notAttempted
            return
        }
        guard let tokens = accountSession.lastSessionTokens,
              !tokens.refreshToken.isEmpty else {
            tokenSaveResult = .failed
            return
        }
        // 持久化用真实账号名（private 包装回传）；掩码名仅供 UI 展示。
        let realAccountName = tokens.accountName ?? accountName ?? ""
        let payload = SteamWorkshopTokenStore.Payload(
            accountName: realAccountName,
            refreshToken: tokens.refreshToken,
            guardData: tokens.guardData,
            steamId: steamId ?? "",
            savedAt: Date()
        )
        if SteamWorkshopTokenStore.save(payload) {
            tokenSaveResult = .saved
            SteamWorkshopTokenStore.saveDisplayMetadata(accountName: realAccountName)
        } else {
            tokenSaveResult = .failed
        }
    }
}
