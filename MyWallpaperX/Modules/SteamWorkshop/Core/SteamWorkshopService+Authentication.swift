import Foundation

private final class SteamWorkshopProcessCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var combinedOutput = ""
    nonisolated(unsafe) private var hasResumed = false
    nonisolated(unsafe) private var timeoutTask: Task<Void, Never>?

    nonisolated func append(_ text: String) {
        lock.lock()
        combinedOutput += text
        lock.unlock()
    }

    nonisolated func installTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        timeoutTask = task
        lock.unlock()
    }

    nonisolated func cancelTimeoutTask() {
        lock.lock()
        let task = timeoutTask
        timeoutTask = nil
        lock.unlock()
        task?.cancel()
    }

    nonisolated func finish() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return nil }
        hasResumed = true
        return combinedOutput
    }
}

enum SteamWorkshopInteractiveLoginResult {
    case none
    case passwordInvalid
    case guardRequested
    case guardInvalidRetry
    case guardRateLimited
    case success
}

extension SteamWorkshopService {
    func authenticateUser() {
        Task { @MainActor [weak self] in
            self?.authenticateUserImmediately()
        }
    }

    func authenticateUserImmediately() {
        guard !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authError = "请输入 Steam 用户名。"
            return
        }
        guard !steamPassword.isEmpty else {
            authError = "请输入 Steam 密码。"
            return
        }

        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = steamPassword
        cancelActiveLoginSession()
        isAnonymousBrowsing = false
        authPhase = .credentials
        authSessionState = .authenticating
        isAuthenticating = true
        authError = nil
        authStatusMessage = "正在启动内置 SteamCMD，并向 Steam 发起登录请求…"

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.beginInteractiveSteamLogin(username: username, password: password)
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func submitSteamGuardCode() {
        Task { @MainActor [weak self] in
            self?.submitSteamGuardCodeImmediately()
        }
    }

    func submitSteamGuardCodeImmediately() {
        let guardCode = steamGuardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authPhase == .awaitingGuardCode else {
            authError = "当前没有等待输入的 Steam Guard 验证。"
            return
        }
        guard !guardCode.isEmpty else {
            authError = "请输入 Steam Guard 令牌。"
            return
        }
        guard let inputHandle = loginInputHandle else {
            authError = "登录会话已失效，请重新输入账号和密码。"
            authPhase = .credentials
            authSessionState = .expired
            isAuthenticating = false
            return
        }

        authError = nil
        authSessionState = .authenticating
        isAuthenticating = true
        loginSubmittedGuardCode = true
        // Drop the original guard prompt so the next result is based on
        // the response to the submitted token instead of stale history.
        loginOutputBuffer = ""
        authStatusMessage = "正在验证 Steam Guard 令牌…"
        inputHandle.write(Data("\(guardCode)\r".utf8))
    }

    func browseAnonymously() {
        Task { @MainActor [weak self] in
            self?.browseAnonymouslyImmediately()
        }
    }

    func browseAnonymouslyImmediately() {
        cancelActiveLoginSession()
        requiresLogin = !hasSavedCredentials
        isAnonymousBrowsing = true
        authPhase = .credentials
        authSessionState = hasSavedCredentials ? .unknown : .expired
        authError = nil
        isAuthenticating = false
        isLoginSheetPresented = false
        authStatusMessage = "当前为匿名浏览模式：可以查看创意工坊视频列表，下载前需要先登录 Steam。"
        fetchBrowserItems()
    }

    func presentLoginGate() {
        Task { @MainActor [weak self] in
            self?.presentLoginGateImmediately()
        }
    }

    func clearPendingDownloadRequest() {
        pendingDownloadRequest = nil
        if authPhase == .authenticated, hasSavedCredentials {
            if let lastAuthenticatedAt = defaults.object(forKey: Constants.defaultsLastAuthenticatedAt) as? Date {
                authStatusMessage = "已检测到上次使用过的 Steam 凭据。下载前会先验证当前会话；如果远端会话已失效，再提示你继续登录。上次成功登录时间：\(lastAuthenticatedAt.formatted(date: .abbreviated, time: .shortened))。"
            } else {
                authStatusMessage = "已检测到已保存的 Steam 凭据。下载前会先验证当前会话；如果远端会话失效，再提示继续登录。"
            }
        }
    }

    func presentLoginGateImmediately() {
        if authPhase == .awaitingGuardCode, loginInputHandle != nil {
            authError = nil
            isLoginSheetPresented = true
            authStatusMessage = "Steam 已要求进行 Steam Guard 验证，请输入刚收到的令牌以继续当前登录。"
            return
        }

        cancelActiveLoginSession()
        authPhase = .credentials
        authSessionState = hasSavedCredentials ? .unknown : .expired
        isAuthenticating = false
        steamGuardCode = ""
        authError = nil
        isLoginSheetPresented = false

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isPreparingRuntime = true
                self.authStatusMessage = "正在准备 SteamCMD 运行环境…"
            }

            do {
                try await self.ensureManagedSteamRuntime()
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authStatusMessage = "请输入 Steam 账号密码。若 Steam 要求验证，下一步再填写 Guard 令牌。"
                    self.isLoginSheetPresented = true
                }
            } catch {
                await MainActor.run {
                    self.isPreparingRuntime = false
                    self.authError = error.localizedDescription
                    self.authStatusMessage = "SteamCMD 启动失败，请检查随 App 打包的运行资源。"
                }
            }
        }
    }

    func logout() {
        Task { @MainActor [weak self] in
            self?.logoutImmediately()
        }
    }

    func logoutImmediately() {
        cancelActiveLoginSession()
        clearCommunitySession()
        cancelDownloadImmediately(showFeedback: false)
        defaults.removeObject(forKey: Constants.defaultsLastUsername)
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.deletePassword()
        pendingDownloadRequest = nil
        steamUsername = ""
        steamPassword = ""
        steamGuardCode = ""
        requiresLogin = true
        isAnonymousBrowsing = true
        authPhase = .credentials
        authSessionState = .expired
        lastSuccessfulSessionValidationAt = nil
        isLoginSheetPresented = false
        authError = nil
        authStatusMessage = "已退出当前 Steam 登录态。"
    }
    func loadAuthenticationState() {
        let storedUsername = defaults.string(forKey: Constants.defaultsLastUsername) ?? ""
        let storedPassword = SteamWorkshopCredentialStore.loadPassword() ?? ""
        steamUsername = storedUsername
        steamPassword = storedPassword
        requiresLogin = storedUsername.isEmpty || storedPassword.isEmpty
        isAnonymousBrowsing = requiresLogin
        authPhase = requiresLogin ? .credentials : .authenticated
        authSessionState = requiresLogin ? .expired : .unknown
        lastSuccessfulSessionValidationAt = nil
        if requiresLogin {
            authStatusMessage = "当前还没有可复用的 Steam 登录凭据。可以先匿名浏览，需要下载时再登录。"
        } else if let lastAuthenticatedAt = defaults.object(forKey: Constants.defaultsLastAuthenticatedAt) as? Date {
            authStatusMessage = "已检测到上次使用过的 Steam 凭据。下载前会先验证当前会话；如果远端会话已失效，再提示你继续登录。上次成功登录时间：\(lastAuthenticatedAt.formatted(date: .abbreviated, time: .shortened))。"
        } else {
            authStatusMessage = "已检测到已保存的 Steam 凭据。下载前会先验证当前会话；如果远端会话失效，再提示继续登录。"
        }
    }

    func saveAuthenticationState(username: String, password: String) {
        defaults.set(username, forKey: Constants.defaultsLastUsername)
        defaults.set(Date(), forKey: Constants.defaultsLastAuthenticatedAt)
        SteamWorkshopCredentialStore.save(password: password)
        requiresLogin = false
        isAnonymousBrowsing = false
        authPhase = .authenticated
        authSessionState = .valid
        lastSuccessfulSessionValidationAt = Date()
    }

    var hasSavedCredentials: Bool {
        !steamUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steamPassword.isEmpty
    }

    func prepareRuntimeIfNeeded() async {
        await MainActor.run {
            self.isPreparingRuntime = true
            self.statusMessage = "正在检查 SteamCMD 环境…"
        }

        do {
            try await ensureManagedSteamRuntime()
            await MainActor.run {
                self.isPreparingRuntime = false
                if self.browserState == .idle {
                    self.statusMessage = "SteamCMD 环境已就绪，正在加载创意工坊列表…"
                }
            }
        } catch {
            await MainActor.run {
                self.isPreparingRuntime = false
                self.requiresLogin = true
                self.isAnonymousBrowsing = true
                self.authPhase = .credentials
                self.authSessionState = .expired
                self.authError = error.localizedDescription
                self.authStatusMessage = "SteamCMD 环境准备失败。"
            }
            return
        }
    }

    func ensureManagedSteamRuntime() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: libraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: videoLibraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: webLibraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sceneLibraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runtimeInstallRootURL, withIntermediateDirectories: true)

        guard let bundledSteamRootURL,
              validateSteamRuntime(at: bundledSteamRootURL) else {
            throw NSError(domain: "SteamWorkshop", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "App 包内没有找到可用的 SteamCMD 基线资源。"
            ])
        }

        steamRuntimeUpdateStatus = "当前直接运行 App 内置 SteamCMD 基线版本。后续 SteamCMD 升级将随应用更新一起分发。"
    }

    func runSteamProcess(arguments: [String], stdinText: String? = nil, timeout: TimeInterval? = nil) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.currentDirectoryURL = steamRootURL
            process.arguments = ["./steamcmd.sh"] + arguments
            process.environment = steamProcessEnvironment()

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            let inputPipe = Pipe()
            process.standardInput = inputPipe
            let captureState = SteamWorkshopProcessCaptureState()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                captureState.append(String(data: data, encoding: .utf8) ?? "")
            }

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                captureState.cancelTimeoutTask()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                captureState.append(String(data: data, encoding: .utf8) ?? "")
                guard let combinedOutput = captureState.finish() else { return }
                if process.terminationStatus == 0 {
                    continuation.resume(returning: combinedOutput)
                } else {
                    continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: combinedOutput.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : combinedOutput
                    ]))
                }
            }

            do {
                try process.run()
                if let timeout, timeout > 0 {
                    let timeoutTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    captureState.installTimeoutTask(timeoutTask)
                }
                if let stdinText, !stdinText.isEmpty {
                    inputPipe.fileHandleForWriting.write(Data(stdinText.utf8))
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func shouldReuseValidatedSession() -> Bool {
        guard authSessionState == .valid,
              let lastSuccessfulSessionValidationAt else { return false }
        return Date().timeIntervalSince(lastSuccessfulSessionValidationAt) < Constants.authProbeCacheTTL
    }

    func validateSavedAuthenticationSessionIfNeeded(force: Bool = false) async -> Bool {
        guard hasSavedCredentials else {
            authSessionState = .expired
            return false
        }
        if !force, shouldReuseValidatedSession() {
            return true
        }

        authSessionState = .authenticating
        authStatusMessage = "正在验证当前 Steam 会话…"
        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let output = try await runSteamProcess(
                arguments: ["+login", username, "+quit"],
                timeout: Constants.authProbeTimeout
            )
            let lowered = output.localizedLowercase
            if outputIndicatesLoginSuccess(lowered) {
                authSessionState = .valid
                lastSuccessfulSessionValidationAt = Date()
                requiresLogin = false
                authPhase = .authenticated
                authStatusMessage = "已验证当前 Steam 会话，下载时会直接复用。"
                return true
            }
            if outputIndicatesBenignSteamBootstrap(output) {
                authSessionState = .unknown
                authStatusMessage = "SteamCMD 已就绪，下载时会继续复用当前会话。"
                return true
            }
            if outputRequestsGuardCode(lowered) || outputRequestsPassword(lowered) || outputIndicatesAuthenticationFailure(output) {
                authSessionState = .expired
                authStatusMessage = "当前 Steam 会话需要重新验证。请继续输入账号密码，若 Steam 要求，再输入 Guard 令牌。"
                return false
            }
            authSessionState = .unknown
            authStatusMessage = "暂时无法确认 Steam 会话状态，下载时会继续尝试。"
            return true
        } catch {
            let lowered = error.localizedDescription.localizedLowercase
            if outputIndicatesBenignSteamBootstrap(error.localizedDescription) {
                authSessionState = .unknown
                authStatusMessage = "SteamCMD 已就绪，下载时会继续复用当前会话。"
                return true
            }
            if outputRequestsGuardCode(lowered) || outputRequestsPassword(lowered) || outputIndicatesAuthenticationFailure(error.localizedDescription) {
                authSessionState = .expired
                authStatusMessage = "当前 Steam 会话需要重新验证。请继续输入账号密码，若 Steam 要求，再输入 Guard 令牌。"
                return false
            }
            authSessionState = .unknown
            authStatusMessage = "Steam 会话探测未完成，下载时会继续尝试。"
            return true
        }
    }

    func outputRequestsPassword(_ output: String) -> Bool {
        output.contains("please enter your password")
            || output.contains("password:")
            || output.contains("please enter the account password")
    }

    func beginInteractiveSteamLogin(username: String, password: String) {
        resetSteamAuthDebugLog()
        loginSessionID = UUID().uuidString.lowercased()
        appendSteamAuthDebugLog("=== Steam login session started ===")
        appendSteamAuthDebugLog("Session ID: \(loginSessionID)")
        appendSteamAuthDebugLog("Local time: \(Date().formatted(date: .complete, time: .standard))")
        appendSteamAuthDebugLog("Bundle path: \(Bundle.main.bundleURL.path)")
        appendSteamAuthDebugLog("Log file path: \(steamAuthDebugLogURL.path)")
        appendSteamAuthDebugLog("Execution mode: app -> /bin/bash ./steamcmd.sh")
        pendingLoginUsername = username
        pendingLoginPassword = password
        pendingLoginCommand = "login \(username) \(password)\r"
        appendSteamAuthDebugLog("Prepared command: \(redactedLoginCommand(username: username, password: password))")
        steamGuardCode = ""
        loginPasswordSent = false
        loginSucceeded = false
        loginSubmittedGuardCode = false
        loginOutputBuffer = ""

        let process = Process()
        let steamRootURL: URL
        do {
            steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
            appendSteamAuthDebugLog("Resolved runtime root: \(steamRootURL.path)")
        } catch {
            appendSteamAuthDebugLog("Failed to resolve runtime root: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        let pty: SteamWorkshopPTYSession
        do {
            pty = try makeSteamPTYSession()
            appendSteamAuthDebugLog("Created local PTY session for interactive login.")
        } catch {
            appendSteamAuthDebugLog("Failed to create local PTY: \(error.localizedDescription)")
            isAuthenticating = false
            authError = "无法创建 SteamCMD 交互会话。"
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
            return
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"]
        process.environment = steamProcessEnvironment()
        process.standardInput = pty.slave
        process.standardOutput = pty.slave
        process.standardError = pty.slave
        appendSteamAuthDebugLog("Launch path: /bin/bash")
        appendSteamAuthDebugLog("Launch arguments: ./steamcmd.sh")

        pty.master.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                self?.handleInteractiveLoginOutput(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.appendSteamAuthDebugLog("Process terminated with status \(process.terminationStatus).")
                try? pty.master.close()
                try? pty.slave.close()
                self?.handleInteractiveLoginTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            appendSteamAuthDebugLog("Process started successfully.")
            loginProcess = process
            loginInputHandle = pty.master
            loginOutputHandle = pty.master
            authStatusMessage = "SteamCMD 已启动，正在等待控制台就绪…"
            loginBootstrapTimeoutTask?.cancel()
            loginBootstrapTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          !self.loginPasswordSent,
                          self.authPhase == .credentials else { return }
                    self.appendSteamAuthDebugLog("Bootstrap timeout reached before Steam prompt was observed.")
                    self.finalizeInteractiveLoginFailure(message: "SteamCMD 控制台未进入可登录状态，登录命令没有被执行。")
                }
            }
        } catch {
            try? pty.master.close()
            try? pty.slave.close()
            appendSteamAuthDebugLog("Process start failed: \(error.localizedDescription)")
            isAuthenticating = false
            authError = error.localizedDescription
            authStatusMessage = "SteamCMD 启动失败。"
            cancelActiveLoginSession()
        }
    }

    func resetSteamAuthDebugLog() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? Data().write(to: steamAuthDebugLogURL, options: [.atomic])
    }

    func appendSteamAuthDebugLog(_ message: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: steamAuthDebugLogURL.path),
           let handle = try? FileHandle(forWritingTo: steamAuthDebugLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: steamAuthDebugLogURL, options: [.atomic])
        }
    }

    func redactedLoginCommand(username: String, password: String) -> String {
        "login \(username) \(String(repeating: "*", count: max(8, password.count)))\\r"
    }

    func redactedCommand(_ command: String) -> String {
        if command.hasPrefix("login ") {
            let parts = command.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 {
                return "login \(parts[1]) \(String(repeating: "*", count: 8))\\r"
            }
        }
        return sanitizeSteamOutput(command)
    }

    func sanitizeSteamOutput(_ text: String) -> String {
        let sanitizedLogin = text.replacingOccurrences(
            of: #"login\s+(\S+)\s+([^\r\n]+)"#,
            with: "login $1 ********",
            options: .regularExpression
        )

        return sanitizedLogin
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validateSteamRuntime(at rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard Constants.requiredBundledItems.allSatisfy({ name in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path)
        }) else {
            return false
        }

        for executableName in ["steamcmd.sh", "steamcmd"] {
            let executablePath = rootURL.appendingPathComponent(executableName).path
            guard fileManager.isExecutableFile(atPath: executablePath) else {
                return false
            }
        }
        return true
    }

    func makeSteamPTYSession() throws -> SteamWorkshopPTYSession {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
            )
        }

        return SteamWorkshopPTYSession(
            master: FileHandle(fileDescriptor: masterFD, closeOnDealloc: true),
            slave: FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        )
    }

    func resolvedSteamRuntimeExecutionRootURL() throws -> URL {
        if let activeSteamRootURL {
            return activeSteamRootURL
        }
        throw NSError(domain: "SteamWorkshop", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "内置 SteamCMD 运行目录无效，未执行任何旧缓存回退。请确认应用包中的 SteamCMDRuntime.bundle 完整存在。"
        ])
    }

    func steamProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        return environment
    }

    func refreshSteamRuntimeStatus() {
        if let metadataURL = bundledSteamMetadataURL,
           let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SteamWorkshopBundledRuntimeMetadata.self, from: data) {
            steamRuntimeVersion = metadata.version
            steamRuntimeUpdateStatus = "当前内置基线版本为 \(metadata.version)。运行时直接使用 App 内置 SteamCMD，后续版本更新随应用更新一起分发。"
        } else {
            steamRuntimeVersion = "未知"
            steamRuntimeUpdateStatus = "未读取到 SteamCMD 基线版本信息。"
        }
    }

    func outputRequestsGuardCode(_ output: String) -> Bool {
        output.contains("steam guard")
        || output.contains("two-factor code")
        || output.contains("two factor code")
        || output.contains("access code")
        || output.contains("email code")
        || output.contains("steam guard code:")
    }

    func outputIndicatesLoginSuccess(_ output: String) -> Bool {
        output.contains("logged in ok")
        || output.contains("successfully logged in")
        || output.contains("waiting for user info...ok")
        || outputIndicatesUsernamePasswordLoginSuccess(output)
        || outputIndicatesGuardLoginSuccess(output)
    }

    func outputIndicatesUsernamePasswordLoginSuccess(_ output: String) -> Bool {
        output.contains("logging in using username/password.")
            && output.contains("logging in user")
            && output.contains("to steam public...ok")
            && output.contains("waiting for client config...ok")
            && output.contains("waiting for user info...ok")
            && output.contains("steam>")
    }

    func outputIndicatesGuardLoginSuccess(_ output: String) -> Bool {
        guard loginSubmittedGuardCode else { return false }

        let completedGuardLogin = output.contains("waiting for client config...ok")
            && output.contains("waiting for user info...ok")
        let returnedToPrompt = output.contains("steam>") && output.contains("ok")

        return (completedGuardLogin || returnedToPrompt)
            && !outputIndicatesRateLimitExceeded(output)
            && !outputIndicatesInvalidPassword(output)
            && !outputIndicatesGuardRetryPrompt(output)
    }

    func outputIndicatesInvalidPassword(_ output: String) -> Bool {
        output.contains("invalid password")
    }

    func outputIndicatesRateLimitExceeded(_ output: String) -> Bool {
        output.contains("rate limit exceeded")
    }

    func outputIndicatesGuardRetryPrompt(_ output: String) -> Bool {
        output.contains("please check your email for the message from steam")
            && output.contains("steam guard code:")
    }

    func resolveInteractiveLoginResult(from output: String, latestChunk: String) -> SteamWorkshopInteractiveLoginResult {
        if outputIndicatesRateLimitExceeded(output) {
            return .guardRateLimited
        }
        if outputIndicatesInvalidPassword(output) {
            return .passwordInvalid
        }
        if outputIndicatesLoginSuccess(output) {
            return .success
        }
        // Guard prompts must come from newly received output, otherwise
        // previously buffered prompts can incorrectly override a later success.
        if outputIndicatesGuardRetryPrompt(latestChunk) {
            return .guardInvalidRetry
        }
        if outputRequestsGuardCode(latestChunk) {
            return .guardRequested
        }
        return .none
    }

    func friendlyAuthFailureMessage(from output: String) -> String {
        let lowered = output.localizedLowercase
        if outputIndicatesRateLimitExceeded(lowered) {
            return "Steam Guard 验证超出速率限制，请稍后再试。"
        }
        if outputIndicatesInvalidPassword(lowered) {
            return "Steam 用户名或密码不正确。"
        }
        if outputIndicatesGuardRetryPrompt(lowered) {
            return "Steam Guard 令牌错误，请重新输入。"
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Steam 登录失败，请重试。"
        }
        return "Steam 登录未完成，请重试。"
    }
}
