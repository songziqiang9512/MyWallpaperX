import Foundation
import AppKit

private final class SteamWorkshopDownloadCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var combinedOutput = ""

    nonisolated func append(_ text: String) {
        lock.lock()
        combinedOutput += text
        lock.unlock()
    }

    nonisolated func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return combinedOutput
    }
}

extension SteamWorkshopService {
    func requestDownloadForBrowserItem(_ item: SteamWorkshopBrowserItem) {
        downloadWorkshopItem(id: item.id, pageTitle: item.title, item: item)
    }

    func requestMissingDependencyDownload(for record: SteamWorkshopDownloadRecord) {
        guard case let .missing(rawItemID) = record.dependencyStatus else { return }

        let itemID = rawItemID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidWorkshopItemID(itemID), itemID != record.id else {
            let message = "`\(record.title)` 声明的依赖项 ID 无效，无法下载。"
            downloadError = message
            statusMessage = message
            return
        }

        downloadWorkshopItem(
            id: itemID,
            pageTitle: browserItemForDownload(id: itemID)?.title
        )
    }

    func downloadWorkshopItem(id: String, pageTitle: String? = nil, item: SteamWorkshopBrowserItem? = nil) {
        let title = pageTitle ?? "Workshop #\(id)"
        let requestItem = item ?? browserItemForDownload(id: id)

        guard canRequestDownload(id: id) else {
            // SK4.1：目标仍在 queued 且执行器空闲（如重启恢复的任务）时，
            // 本次点击直接推活出队，而不是让任务永远不可见地滞留。
            if downloadJobStore.activeJob(forWorkshopItemId: id)?.state == .queued {
                processNextQueuedDownloadIfPossible()
            }
            if activeDownloadItemID != id {
                statusMessage = "\(title) 已在下载任务中。"
                appendSteamAuthDebugLog("DOWNLOAD BLOCKED: duplicate active/queued request. requestedID=\(id)")
            }
            return
        }

        guard !isDownloadWorkflowBusy else {
            enqueueDownloadRequest(id: id, pageTitle: pageTitle, item: requestItem)
            return
        }

        // SK4.1：执行器空闲但同账号还有更早的 queued 意图（持久化恢复场景）
        // 时先按 FIFO 出队，本次点击排在被出队任务之后——持久化队列不能被
        // 新点击永久饿死。
        processNextQueuedDownloadIfPossible()
        if activeDownloadItemID != nil {
            enqueueDownloadRequest(id: id, pageTitle: pageTitle, item: requestItem)
            return
        }
        startDownloadRequest(SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle, item: requestItem))
    }

    func canRequestDownload(id: String) -> Bool {
        activeDownloadItemID != id
            && !isQueuedDownloadRequest(id: id)
    }

    private func isValidWorkshopItemID(_ itemID: String) -> Bool {
        itemID.count >= 6
            && itemID.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 48 && scalar.value <= 57
            }
    }

    /// SK4.1：执行器占用/认证忙碌判定。queued 任务不算忙碌——持久化队列
    /// 的排空只走 processNextQueuedDownloadIfPossible（含上面 downloadWorkshopItem
    /// 的 FIFO 推活），否则重启恢复的 queued 任务会永久堵死新下载。
    private var isDownloadWorkflowBusy: Bool {
        activeDownloadItemID != nil
            || activeDownloadTask != nil
            || activeDownloadProcess != nil
            || isAuthenticating
            || isLoginSheetPresented
            || authPhase == .awaitingGuardCode
    }

    func startDownloadRequest(_ request: SteamWorkshopPendingDownloadRequest) {
        // SK4.1：直接点击与出队续跑共用同一入队/启动语义——
        // 已在队列/执行中的任务不会被重复入队或二次 started。
        let (job, _) = downloadJobStore.enqueue(
            workshopItemId: request.id,
            title: request.pageTitle ?? "Workshop #\(request.id)",
            accountSteamId: steamAuth.steamId ?? "anonymous"
        )
        if job.state == .queued {
            downloadJobStore.apply(.started, toID: job.id)
        }
        beginDownloadWorkflow(request)
    }

    private func beginDownloadWorkflow(_ request: SteamWorkshopPendingDownloadRequest) {
        let id = request.id
        let pageTitle = request.pageTitle
        let title = pageTitle ?? "Workshop #\(id)"
        activeDownloadItemID = id
        activeDownloadWasCancelled = false
        statusMessage = "已向 SteamCMD 提交 \(title) 的下载请求。"
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: downloadStatusSizeText(for: id))
        statusMessage = "正在确认 Steam 下载环境…"
        appendSteamAuthDebugLog("=== Workshop download requested ===")
        appendSteamAuthDebugLog("Requested item id=\(id), title=\(pageTitle ?? "Workshop #\(id)")")

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: ensureManagedSteamRuntime")
                }
                try await self.ensureManagedSteamRuntime()
                try Task.checkCancellation()
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP OK: ensureManagedSteamRuntime")
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: ensureAuthenticatedSessionForDownload")
                }
                try await self.ensureAuthenticatedSessionForDownload(request)
                try Task.checkCancellation()
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP OK: ensureAuthenticatedSessionForDownload")
                    self.appendSteamAuthDebugLog("DOWNLOAD STEP: performWorkshopDownload")
                }
                try await self.performWorkshopDownload(request)
            } catch {
                await MainActor.run {
                    self.appendSteamAuthDebugLog("DOWNLOAD FAILED: id=\(id), error=\(self.sanitizeSteamOutput(error.localizedDescription))")
                    self.finishActiveDownloadState()
                    let message = error.localizedDescription
                    if error is SteamWorkshopDownloadControlError || error is CancellationError {
                        // SK4.1：执行器取消结果写回 JobStore（用户取消/登出）。
                        self.finishDownloadJob(id: id, event: .cancelled)
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.removeTransientRecord(id: id)
                        self.processNextQueuedDownloadIfPossible()
                        return
                    }
                    let nsError = error as NSError
                    if nsError.domain == "SteamWorkshop", nsError.code == 11 {
                        // SK2.2：登录被拒不是任务；清理现场并移除瞬态记录（§9 任务数不增长）。
                        self.finishDownloadJob(id: id, event: .failed(message))
                        self.cleanupStagedDownload(id: id)
                        self.statusMessage = message
                        self.removeTransientRecord(id: id)
                        return
                    }
                    // SK4.1：执行器失败结果写回 JobStore，保持去重/忙碌真值一致。
                    self.finishDownloadJob(id: id, event: .failed(message))
                    self.cleanupStagedDownload(id: id)
                    self.downloadError = message
                    self.statusMessage = message
                    self.upsertTransientRecord(id: id, title: pageTitle ?? "Workshop #\(id)", status: .failed(message))
                    self.processNextQueuedDownloadIfPossible()
                }
            }
        }
        activeDownloadTask = task
    }

    func ensureAuthenticatedSessionForDownload(_ request: SteamWorkshopPendingDownloadRequest) async throws {
        // SK2.2 合同（§1 规则 3）：所有未登录/未验证分支一律就地提示，
        // 不自动弹登录、不置旧登录 sheet、不创建 pending 副作用。
        if authPhase == .awaitingGuardCode {
            statusMessage = "需要登录 Steam。请使用工具栏的「登录 Steam」。"
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "需要登录 Steam。请使用工具栏的「登录 Steam」。"
            ])
        }

        if isAuthenticating {
            statusMessage = "正在验证 Steam 会话，请稍后重试下载。"
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "正在验证 Steam 会话，请稍后重试下载。"
            ])
        }

        guard hasSavedCredentials else {
            presentSteamLoginGuidance(context: "下载")
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "下载需要登录 Steam。请使用工具栏的「登录 Steam」。"
            ])
        }

        if !(await validateSavedAuthenticationSessionIfNeeded()) {
            requiresLogin = false
            isAnonymousBrowsing = false
            presentSteamLoginGuidance(context: "会话已过期")
            throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "当前 Steam 登录态需要重新验证。请使用工具栏的「登录 Steam」。"
            ])
        }
    }

    /// SK4.1：把执行器结果写回 JobStore。job 已被先行终结（如登出 cancelAll
    /// 或重复结果）时 reducer 拒绝、此处 no-op。没有这一步 job 会永远停在
    /// running：去重（canRequestDownload）与忙碌判定被污染，重启后还会回退
    /// queued 复活成重复任务。
    func finishDownloadJob(id: String, event: SteamDownloadJobEvent) {
        guard let job = downloadJobStore.activeJob(forWorkshopItemId: id) else { return }
        downloadJobStore.apply(event, toID: job.id)
    }

    func cancelActiveDownload() {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(showFeedback: true)
        }
    }

    func cancelDownload(itemID: String) {
        Task { @MainActor [weak self] in
            self?.cancelDownloadImmediately(itemID: itemID, showFeedback: true)
        }
    }

    func performWorkshopDownload(_ request: SteamWorkshopPendingDownloadRequest) async throws {
        let id = request.id
        let pageTitle = request.pageTitle
        let title = pageTitle ?? "Workshop #\(id)"
        statusMessage = "正在通过内置 SteamCMD 下载 \(title)"
        appendSteamAuthDebugLog("DOWNLOAD BEGIN: id=\(id), title=\(title)")

        try prepareCleanWorkshopStaging()

        let username = steamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try await runValidatedWorkshopDownload(
            id: id,
            title: title,
            username: username,
            pageTitle: pageTitle,
            item: request.item
        )

        let hasSuccessfulOutput = output.localizedCaseInsensitiveContains("Success. Downloaded item")
        let hasStagedContent = stagedDownloadDirectoryContainsContent(id: id)
        let hasBenignBootstrapOutput = outputIndicatesBenignSteamBootstrap(output)

        guard hasSuccessfulOutput || hasStagedContent else {
            if outputIndicatesAuthenticationFailure(output) {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效。请使用工具栏的「登录 Steam」重新登录后再试。"
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效。请使用工具栏的「登录 Steam」。"
                ])
            }
            if outputIndicatesAccessRestriction(output) {
                throw NSError(domain: "SteamWorkshop", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "当前项目可能是私有内容、权限不足，或资源暂不可用，SteamCMD 未能完成下载。"
                ])
            }
            if hasBenignBootstrapOutput {
                appendSteamAuthDebugLog("DOWNLOAD OUTPUT IGNORED: benign Steam bootstrap noise observed for id=\(id).")
            }
            throw NSError(domain: "SteamWorkshop", code: 2, userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 未返回成功下载结果。" : output
            ])
        }

        if !hasSuccessfulOutput, hasStagedContent {
            appendSteamAuthDebugLog("DOWNLOAD FALLBACK SUCCESS: staged content detected for id=\(id) despite missing success marker.")
        }

        try await syncDownloadedItemToLibrary(request)
        appendSteamAuthDebugLog("DOWNLOAD SYNC OK: copied staged content into library for id=\(id)")
        // SK4.1：旧执行器成功即内联入库——staged 是本卡的成功终态。
        finishDownloadJob(id: id, event: .staged)
        cleanupStagedDownload(id: id)

        finishActiveDownloadState()
        statusMessage = "已完成 Workshop #\(id) 下载"
        reloadInstalledItems()
        appendSteamAuthDebugLog("DOWNLOAD COMPLETE: id=\(id)")
        processNextQueuedDownloadIfPossible()
    }

    func runValidatedWorkshopDownload(
        id: String,
        title: String,
        username: String,
        pageTitle: String?,
        item: SteamWorkshopBrowserItem?
    ) async throws -> String {
        do {
            return try await runDownloadProcess(
                id: id,
                title: title,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", username,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        } catch {
            let processOutput = error.localizedDescription
            guard outputIndicatesAuthenticationFailure(processOutput) || outputRequestsPassword(processOutput.localizedLowercase) else {
                throw error
            }

            authSessionState = .expired
            lastSuccessfulSessionValidationAt = nil
            let sessionRecovered = await validateSavedAuthenticationSessionIfNeeded(force: true)
            guard sessionRecovered else {
                expireAuthenticationAndPromptRelogin(
                    reason: "Steam 下载认证已失效。请使用工具栏的「登录 Steam」重新登录后再试。"
                )
                throw NSError(domain: "SteamWorkshop", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "当前 Steam 登录态已失效。请使用工具栏的「登录 Steam」。"
                ])
            }

            return try await runDownloadProcess(
                id: id,
                title: title,
                arguments: [
                    "+force_install_dir", runtimeInstallRootURL.path,
                    "+login", username,
                    "+workshop_download_item", Constants.workshopAppID, id, "validate",
                    "+quit"
                ]
            )
        }
    }

    func runDownloadProcess(id: String, title: String, arguments: [String]) async throws -> String {
        let steamRootURL = try resolvedSteamRuntimeExecutionRootURL()
        appendSteamAuthDebugLog("DOWNLOAD PROCESS: root=\(steamRootURL.path)")
        appendSteamAuthDebugLog("DOWNLOAD PROCESS: arguments=./steamcmd.sh \(arguments.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = steamRootURL
        process.arguments = ["./steamcmd.sh"] + arguments
        process.environment = steamProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        activeDownloadWasCancelled = false
        let captureState = SteamWorkshopDownloadCaptureState()

        return try await withCheckedThrowingContinuation { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                captureState.append(chunk)
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD STDOUT: \(self?.sanitizeSteamOutput(chunk) ?? "")")
                }
            }

            process.terminationHandler = { [weak self] process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let trailingOutput = String(data: data, encoding: .utf8) ?? ""
                if !trailingOutput.isEmpty {
                    captureState.append(trailingOutput)
                }
                let output = captureState.snapshot()
                Task { @MainActor [weak self] in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    self?.activeDownloadProcess = nil
                    let completedSuccessfully =
                        output.localizedCaseInsensitiveContains("Success. Downloaded item")
                        || self?.stagedDownloadDirectoryContainsContent(id: id) == true
                    if completedSuccessfully {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: success, status=\(process.terminationStatus), aggregatedOutput=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(returning: output)
                    } else if self?.activeDownloadWasCancelled == true {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: cancelled by user, status=\(process.terminationStatus)")
                        continuation.resume(throwing: SteamWorkshopDownloadControlError.cancelled)
                    } else if process.terminationStatus == 0 {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: success, status=0, aggregatedOutput=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(returning: output)
                    } else {
                        self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS TERMINATED: nonzero status=\(process.terminationStatus), output=\(self?.sanitizeSteamOutput(output) ?? "")")
                        continuation.resume(throwing: NSError(domain: "SteamWorkshop", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: output.isEmpty ? "SteamCMD 执行失败，退出码 \(process.terminationStatus)。" : output
                        ]))
                    }
                }
            }

            do {
                try process.run()
                Task { @MainActor [weak self] in
                    self?.appendSteamAuthDebugLog("DOWNLOAD PROCESS STARTED: pid=\(process.processIdentifier)")
                    self?.startActiveDownloadState(
                        id: id,
                        title: title,
                        process: process
                    )
                }
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                appendSteamAuthDebugLog("DOWNLOAD PROCESS START FAILED: \(sanitizeSteamOutput(error.localizedDescription))")
                continuation.resume(throwing: error)
            }
        }
    }

    func startActiveDownloadState(id: String, title: String, process: Process) {
        activeDownloadItemID = id
        activeDownloadProcess = process
        upsertTransientRecord(id: id, title: title, status: .downloading, sizeText: downloadStatusSizeText(for: id))
    }

    func finishActiveDownloadState() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadProcess = nil
        activeDownloadItemID = nil
        activeDownloadWasCancelled = false
    }

    func cancelDownloadImmediately(itemID: String? = nil, showFeedback: Bool) {
        if let itemID, itemID != activeDownloadItemID {
            // SK4.1：队列真值在 JobStore——取消排队任务并清投影。
            if let job = downloadJobStore.activeJob(forWorkshopItemId: itemID) {
                downloadJobStore.cancel(id: job.id)
                removeTransientRecord(id: itemID)
                if showFeedback {
                    statusMessage = "已将 \(itemID) 移出下载队列。"
                }
                return
            }
            return
        }

        guard activeDownloadProcess != nil || activeDownloadItemID != nil || activeDownloadTask != nil else { return }
        activeDownloadWasCancelled = true
        activeDownloadTask?.cancel()
        activeDownloadProcess?.terminate()
        if showFeedback {
            statusMessage = "正在取消当前下载…"
        }
    }

    func prepareCleanWorkshopStaging() throws {
        let workshopRootURL = runtimeInstallRootURL
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("workshop", isDirectory: true)
        let appID = Constants.workshopAppID
        let cleanupTargets = [
            workshopRootURL.appendingPathComponent("appworkshop_\(appID).acf", isDirectory: false),
            workshopRootURL
                .appendingPathComponent("content", isDirectory: true)
                .appendingPathComponent(appID, isDirectory: true),
            workshopRootURL
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent(appID, isDirectory: true),
            workshopRootURL
                .appendingPathComponent("temp", isDirectory: true)
                .appendingPathComponent(appID, isDirectory: true)
        ]

        for targetURL in cleanupTargets where FileManager.default.fileExists(atPath: targetURL.path) {
            appendSteamAuthDebugLog("DOWNLOAD PREPARE: removing stale Steam staging state \(targetURL.path)")
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.createDirectory(
            at: stagingWorkshopContentRootURL,
            withIntermediateDirectories: true
        )
    }

    func cleanupStagedDownload(id: String) {
        let cleanupTargets = [
            stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true),
            runtimeInstallRootURL
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("workshop", isDirectory: true)
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true),
            runtimeInstallRootURL
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("workshop", isDirectory: true)
                .appendingPathComponent("temp", isDirectory: true)
                .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
        ]

        for targetURL in cleanupTargets where FileManager.default.fileExists(atPath: targetURL.path) {
            appendSteamAuthDebugLog("DOWNLOAD CLEANUP: removing staged directory \(targetURL.path)")
            try? FileManager.default.removeItem(at: targetURL)
        }
    }

    func expectedDownloadBytes(for id: String) -> Int64? {
        if let item = browserItems.first(where: { $0.id == id }) {
            return Self.parseByteCount(from: item.fileSizeText)
        }
        if selectedBrowserItem?.id == id {
            return Self.parseByteCount(from: selectedBrowserItem?.fileSizeText)
        }
        return nil
    }

    /// SK2.2/SK4.1：会话过期只做过期标注与就地提示；不自动弹登录、不保留
    /// 待续接任务（用户登录后重新确认下载）。
    func expireAuthenticationAndPromptRelogin(reason: String) {
        cancelActiveLoginSession()
        defaults.removeObject(forKey: Constants.defaultsLastAuthenticatedAt)
        steamGuardCode = ""
        requiresLogin = false
        isAnonymousBrowsing = false
        authPhase = .credentials
        authSessionState = .expired
        lastSuccessfulSessionValidationAt = nil
        authError = nil
        authStatusMessage = reason
    }

    private func enqueueDownloadRequest(id: String, pageTitle: String?, item: SteamWorkshopBrowserItem?) {
        let title = pageTitle ?? "Workshop #\(id)"
        // SK4.1：入队真值在 JobStore——同项去重，重复点击/跨来源点击只一个任务。
        let (_, isNew) = downloadJobStore.enqueue(
            workshopItemId: id,
            title: title,
            accountSteamId: steamAuth.steamId ?? "anonymous"
        )
        // 执行载荷不入任务文件：会话内内存映射，出队时取回。
        if let item {
            steamJobItemPayloads[id] = item
        }
        guard isNew else {
            statusMessage = "\(title) 已在下载队列中。"
            return
        }
        upsertTransientRecord(
            id: id,
            title: title,
            status: .queued,
            sizeText: downloadStatusSizeText(for: id)
        )
        statusMessage = "已将 \(title) 加入下载队列。"
    }

    private func processNextQueuedDownloadIfPossible() {
        guard activeDownloadItemID == nil,
              activeDownloadTask == nil,
              !isLoginSheetPresented,
              authPhase != .awaitingGuardCode,
              !isAuthenticating else { return }

        // SK4.1：出队即 started（attempt 递增）；按当前账号隔离。匿名会话
        // 只出队匿名任务（与 enqueue 的 "anonymous" 标记一致），不接管其它
        // 账号的恢复任务（§5.6 账号切换不自动恢复）。
        guard let next = downloadJobStore.popNextQueued(
            forAccount: steamAuth.steamId ?? "anonymous"
        ) else { return }
        startDownloadRequest(SteamWorkshopPendingDownloadRequest(
            id: next.workshopItemId,
            pageTitle: next.title,
            item: steamJobItemPayloads[next.workshopItemId]
        ))
    }

    private func isQueuedDownloadRequest(id: String) -> Bool {
        downloadJobStore.isQueuedOrRunning(workshopItemId: id)
    }

    private func downloadStatusSizeText(for id: String) -> String {
        if let existing = latestDownloadRecord(for: id)?.sizeText, !existing.isEmpty {
            return existing
        }
        if let browserSize = browserItemForDownload(id: id)?.fileSizeText, !browserSize.isEmpty {
            return browserSize
        }
        return "未知大小"
    }

    func removeTransientRecord(id: String) {
        downloads.removeAll { record in
            record.id == id && record.status != .ready
        }
    }
}
