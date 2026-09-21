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
/// UI 引用，面板自行判断可见性）；只有当前账号代际可以采纳或清理凭据。
@MainActor
final class SteamAuthRoute: ObservableObject {
    @Published private(set) var phase: SteamAccountSession.AuthPhase = .idle
    @Published private(set) var steamId: String?
    @Published private(set) var accountName: String?
    /// SK2.3：已保存会话被服务端拒绝（过期/撤销）后的重登提示态。
    @Published private(set) var expired = false
    /// SK2.3：最近一次登录的令牌保存结果（Keychain 失败必须可见，不伪报已保存）。
    @Published private(set) var tokenSaveResult: SteamWorkshopTokenStore.TokenSaveResult = .notAttempted

    @Published private(set) var tokenDeletionFailed = false

    /// Injectable storage effects keep auth race tests away from the user's Keychain/defaults.
    struct Persistence {
        var remember: () -> Bool
        var setRemember: (Bool) -> Void
        var setRestoreAuthorized: (Bool) -> Void
        var save: (SteamWorkshopTokenStore.Payload) -> Bool
        var delete: () -> Bool
        var saveMetadata: (String) -> Void
        var clearMetadata: () -> Void

        static var live: Self {
            Self(remember: { UserDefaults.standard.bool(forKey: SteamWorkshopTokenStore.rememberPreferenceKey) },
                 setRemember: { UserDefaults.standard.set($0, forKey: SteamWorkshopTokenStore.rememberPreferenceKey) },
                 setRestoreAuthorized: { UserDefaults.standard.set($0, forKey: SteamWorkshopTokenStore.restoreAuthorizedKey) },
                 save: { SteamWorkshopTokenStore.save($0) }, delete: { SteamWorkshopTokenStore.delete() },
                 saveMetadata: { SteamWorkshopTokenStore.saveDisplayMetadata(accountName: $0) },
                 clearMetadata: { SteamWorkshopTokenStore.clearDisplayMetadata() })
        }
    }

    let client: SteamServiceClient
    private let persistence: Persistence
    private var eventObserverID: UUID?
    private let accountSession: SteamAccountSession

    init(client: SteamServiceClient, persistence: Persistence? = nil) {
        self.client = client
        self.persistence = persistence ?? .live
        self.accountSession = SteamAccountSession(client: client)
        accountSession.onPhaseChange = { [weak self] phase in
            // Online is published only after identity and persistence adoption below.
            if case .online = phase { return }
            self?.phase = phase
        }
        client.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready, .connecting, .idle: break
            default:
                // Public browse shares the helper but is not an authentication
                // attempt. A public-query startup/protocol failure must not
                // project a signed-out account as a failed login.
                guard self.hasAccountConnectionIntent else { return }
                self.connectionLost()
            }
        }
        eventObserverID = client.addEventObserver { [weak self] frame in
            guard let self, frame.event == "accountState", frame.accountEpoch == self.client.accountEpoch,
                  frame.root["state"]?.stringValue == "disconnected" else { return }
            // Anonymous public browse owns no account session. Its Steam
            // connection can drop without creating a failed-login state or
            // advancing the account epoch used to reject stale private work.
            guard self.hasAccountConnectionIntent else { return }
            self.connectionLost()
        }
    }

    var isOnline: Bool { steamId != nil }

    private var hasAccountConnectionIntent: Bool {
        if isOnline { return true }
        switch phase {
        case .connecting, .authenticating, .awaitingDeviceConfirmation,
             .awaitingDeviceCode, .awaitingEmailCode, .qrChallenge, .online:
            return true
        case .idle, .failed, .cancelled:
            return false
        }
    }

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

    private func beginAccountIntent() -> Int {
        accountSession.cancelCurrentAttempt()
        client.accountEpoch += 1
        steamId = nil
        accountName = nil
        expired = false
        tokenSaveResult = .notAttempted
        phase = .connecting
        return client.accountEpoch
    }

    private func checkIntent(_ epoch: Int) throws {
        try Task.checkCancellation()
        guard epoch == client.accountEpoch else { throw CancellationError() }
    }

    func loginPassword(username: String, password: String) async throws -> String {
        let epoch = beginAccountIntent()
        persistence.setRestoreAuthorized(false)
        do {
            try await ensureHelperReady()
            try checkIntent(epoch)
            let id = try await accountSession.loginPassword(username: username, password: password)
            try checkIntent(epoch)
            adoptOnline(steamId: id)
            persistTokenIfRemembered()
            phase = accountSession.phase
            return id
        } catch {
            if Task.isCancelled && epoch == client.accountEpoch {
                accountSession.cancelCurrentAttempt(includingUnadoptedResult: true)
            }
            try checkIntent(epoch)
            throw error
        }
    }

    func loginQR() async throws -> String {
        let epoch = beginAccountIntent()
        persistence.setRestoreAuthorized(false)
        do {
            try await ensureHelperReady()
            try checkIntent(epoch)
            let id = try await accountSession.loginQR()
            try checkIntent(epoch)
            adoptOnline(steamId: id)
            persistTokenIfRemembered()
            phase = accountSession.phase
            return id
        } catch {
            if Task.isCancelled && epoch == client.accountEpoch {
                accountSession.cancelCurrentAttempt(includingUnadoptedResult: true)
            }
            try checkIntent(epoch)
            throw error
        }
    }

    func restore(refreshToken: String, accountName: String?, expectedSteamId: String? = nil) async throws -> String {
        let epoch = beginAccountIntent()
        var mismatchEpoch: Int?
        do {
            try await ensureHelperReady()
            try checkIntent(epoch)
            let id = try await accountSession.restore(refreshToken: refreshToken, accountName: accountName)
            try checkIntent(epoch)
            if let expectedSteamId, !expectedSteamId.isEmpty, expectedSteamId != id {
                // Cleanup belongs to this epoch and runs before any suspension.
                _ = revokeStoredSession()
                accountSession.clearSessionTokens()
                expired = true
                phase = .failed(code: "authExpired", message: "恢复的会话与保存的账号不一致")
                client.accountEpoch += 1
                mismatchEpoch = client.accountEpoch
                _ = try? await client.request(command: "logout")
                throw SteamServiceClient.RequestError.helperError(code: "authExpired", message: "恢复的会话与保存的账号不一致")
            }
            adoptOnline(steamId: id)
            phase = accountSession.phase
            return id
        } catch {
            if Task.isCancelled && epoch == client.accountEpoch {
                accountSession.cancelCurrentAttempt(includingUnadoptedResult: true)
            }
            try checkIntent(mismatchEpoch ?? epoch)
            if mismatchEpoch == nil && Self.disposition(for: error) == .deleteToken {
                _ = revokeStoredSession()
                expired = true
            }
            throw error
        }
    }

    private func ensureHelperReady() async throws {
        if client.currentIdentity == nil { _ = try await client.start() }
    }

    func submit(code: String) async { await accountSession.submit(code: code) }

    func cancelPendingAuthentication() {
        guard accountSession.activeAttemptId != nil || phase == .connecting else { return }
        accountSession.cancelCurrentAttempt(includingUnadoptedResult: true)
        client.accountEpoch += 1
        phase = .cancelled
    }

    func cancel() async { cancelPendingAuthentication() }

    private func connectionLost() {
        accountSession.cancelCurrentAttempt()
        accountSession.clearSessionTokens()
        client.accountEpoch += 1
        steamId = nil
        accountName = nil
        phase = .failed(code: "network", message: "Steam 连接已断开，请使用工具栏重新登录。")
    }

    /// Stop restoration before touching Keychain; failed deletion cannot authorize startup login.
    @discardableResult
    private func revokeStoredSession() -> Bool {
        persistence.setRemember(false)
        persistence.setRestoreAuthorized(false)
        tokenDeletionFailed = !persistence.delete()
        persistence.clearMetadata()
        return !tokenDeletionFailed
    }

    @discardableResult
    func signOut() async -> Bool {
        accountSession.cancelCurrentAttempt()
        client.accountEpoch += 1
        accountSession.clearSessionTokens()
        let cleared = revokeStoredSession()
        steamId = nil
        accountName = nil
        expired = false
        phase = .idle
        if client.currentIdentity != nil { _ = try? await client.request(command: "logout") }
        return cleared
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
        if case .online(_, let name) = accountSession.phase {
            accountName = name
        }
    }

    /// 记住登录开启时原子保存令牌；未开启则清理该账号的持久凭据残留（§3.3）。
    private func persistTokenIfRemembered() {
        guard persistence.remember() else {
            // 不记住：本次令牌仅驻内存，并清掉该账号可能的旧持久凭据。
            tokenDeletionFailed = !persistence.delete()
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
        if persistence.save(payload) {
            persistence.setRestoreAuthorized(true)
            tokenDeletionFailed = false
            tokenSaveResult = .saved
            persistence.saveMetadata(realAccountName)
        } else {
            tokenSaveResult = .failed
        }
    }
}
