import Foundation

extension SteamWorkshopService {
    func handleInteractiveLoginOutput(_ chunk: String) {
        loginOutputBuffer.append(chunk)
        let lowered = loginOutputBuffer.localizedLowercase
        let latestChunk = chunk.localizedLowercase
        appendSteamAuthDebugLog("STDOUT chunk: \(sanitizeSteamOutput(chunk))")

        if lowered.contains("createboundsocket") {
            appendSteamAuthDebugLog("Observed network socket bind failure while SteamCMD attempted to connect.")
        }

        if lowered.contains("error (no connection)") {
            appendSteamAuthDebugLog("SteamCMD reported ERROR (No Connection) and returned to the Steam prompt.")
        }

        if !loginPasswordSent,
           lowered.contains("steam>") {
            appendSteamAuthDebugLog("Detected Steam prompt. About to send login command.")
            sendPendingLoginCommandIfPossible()
        }

        switch resolveInteractiveLoginResult(from: lowered, latestChunk: latestChunk) {
        case .none:
            return
        case .passwordInvalid:
            finalizeInteractiveLoginFailure(message: "Steam 用户名或密码不正确。")
        case .guardRequested:
            presentGuardPrompt(message: "Steam 已要求进行 Steam Guard 验证，请输入刚收到的令牌。")
        case .guardInvalidRetry:
            presentGuardPrompt(message: "Steam Guard 令牌错误，请重新输入。")
        case .guardRateLimited:
            finalizeInteractiveLoginFailure(
                message: "Steam Guard 验证超出速率限制，请稍后再试。",
                closeLoginSheet: true
            )
        case .success:
            finalizeInteractiveLoginSuccess()
        }
    }

    func handleInteractiveLoginTermination(status: Int32) {
        loginOutputHandle?.readabilityHandler = nil
        appendSteamAuthDebugLog("Handling process termination. status=\(status), loginSucceeded=\(loginSucceeded), authPhase=\(authPhase)")

        if loginSucceeded {
            cancelActiveLoginSession(keepStatus: true)
            return
        }

        if status == 0, outputIndicatesLoginSuccess(loginOutputBuffer.localizedLowercase) {
            finalizeInteractiveLoginSuccess()
            return
        }

        if authPhase == .awaitingGuardCode {
            finalizeInteractiveLoginFailure(message: "Steam Guard 验证会话已结束，请重新输入账号和密码。")
            return
        }

        finalizeInteractiveLoginFailure(message: friendlyAuthFailureMessage(from: loginOutputBuffer))
    }

    func finalizeInteractiveLoginSuccess() {
        guard !loginSucceeded else { return }
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked successful.")
        loginSucceeded = true
        saveAuthenticationState(username: pendingLoginUsername, password: pendingLoginPassword)
        steamGuardCode = ""
        isAuthenticating = false
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "Steam 登录已建立。当前会记住你的凭据，后续下载前会先验证当前会话；如果远端会话失效，再提示继续登录。"
        loginInputHandle?.write(Data("quit\r".utf8))
        fetchBrowserItems()
        // §1 规则 3：登录成功不自动执行登录前的下载点击——用户重新确认。
    }

    func finalizeInteractiveLoginFailure(message: String, closeLoginSheet: Bool = false) {
        loginBootstrapTimeoutTask?.cancel()
        appendSteamAuthDebugLog("Login marked failed: \(sanitizeSteamOutput(message))")
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        authSessionState = .expired
        lastSuccessfulSessionValidationAt = nil
        isAuthenticating = false
        authError = message.trimmingCharacters(in: .whitespacesAndNewlines)
        steamGuardCode = ""
        loginSubmittedGuardCode = false
        isLoginSheetPresented = !closeLoginSheet
        authStatusMessage = "Steam 登录失败，请重新输入账号密码后再试。"
        cancelActiveLoginSession(keepStatus: true)
    }

    func cancelActiveLoginSession(keepStatus: Bool = false) {
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
        appendSteamAuthDebugLog("Cancelling login session. keepStatus=\(keepStatus)")
        loginOutputHandle?.readabilityHandler = nil
        try? loginOutputHandle?.close()
        try? loginInputHandle?.close()
        if let process = loginProcess, process.isRunning {
            process.terminate()
        }
        loginProcess = nil
        loginInputHandle = nil
        loginOutputHandle = nil
        loginOutputBuffer = ""
        loginPasswordSent = false
        loginSucceeded = false
        loginSubmittedGuardCode = false
        pendingLoginUsername = ""
        pendingLoginPassword = ""
        pendingLoginCommand = nil
        if !keepStatus, authPhase != .authenticated {
            authPhase = .credentials
        }
    }

    func sendPendingLoginCommandIfPossible() {
        guard !loginPasswordSent,
              let command = pendingLoginCommand,
              let loginInputHandle else { return }
        appendSteamAuthDebugLog("Writing login command to PTY: \(redactedCommand(command))")
        loginInputHandle.write(Data(command.utf8))
        loginPasswordSent = true
        authStatusMessage = "SteamCMD 控制台已就绪，正在向 Steam 发起账号登录请求…"
        loginBootstrapTimeoutTask?.cancel()
        loginBootstrapTimeoutTask = nil
    }

    func presentGuardPrompt(message: String) {
        loginSubmittedGuardCode = false
        steamGuardCode = ""
        authPhase = .awaitingGuardCode
        authSessionState = .authenticating
        isAuthenticating = false
        authError = nil
        isLoginSheetPresented = true
        authStatusMessage = message
    }
}
