import Foundation
import AppKit

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
        guard downloadAdmissionAccount() != nil else { return }
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

    /// 同步准入必须发生在 JobStore、瞬态卡片及执行器副作用之前。
    /// 只读新账号 owner，不读旧密码/网页登录，也不触发恢复或登录 UI。
    private func downloadAdmissionAccount() -> String? {
        guard steamAuth.isOnline, let account = steamAuth.steamId, !account.isEmpty else {
            presentSteamLoginGuidance(context: "下载")
            return nil
        }
        return account
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
            || isAuthenticating
            || isLoginSheetPresented
            || authPhase == .awaitingGuardCode
    }

    func startDownloadRequest(_ request: SteamWorkshopPendingDownloadRequest) {
        guard let account = downloadAdmissionAccount() else { return }
        let job: SteamDownloadJob
        if let failed = downloadJobStore.failedJob(
            forWorkshopItemId: request.id,
            accountSteamId: account
        ) {
            // Explicit retry keeps one logical job and advances its attempt. A
            // different account can never adopt the failed intent.
            let event: SteamDownloadJobEvent = failed.stagingPath != nil && failed.stagingManifestId != nil
                ? .resumed : .started
            guard let retried = downloadJobStore.apply(event, toID: failed.id) else {
                statusMessage = "下载重试任务无法保存，未开始下载。"
                return
            }
            job = retried
        } else {
            // SK4.1：直接点击与出队续跑共用同一入队/启动语义——
            // 已在队列/执行中的任务不会被重复入队或二次 started。
            let (enqueued, _) = downloadJobStore.enqueue(
                workshopItemId: request.id,
                title: request.pageTitle ?? "Workshop #\(request.id)",
                accountSteamId: account
            )
            guard downloadJobStore.lastSaveSucceeded else {
                statusMessage = "下载任务无法保存，未开始下载。"
                return
            }
            guard enqueued.accountSteamId == account else { return }
            if enqueued.state == .queued {
                guard let started = downloadJobStore.apply(.started, toID: enqueued.id) else { return }
                job = started
            } else {
                job = enqueued
            }
        }
        guard job.accountSteamId == account else { return }
        guard downloadJobStore.lastSaveSucceeded else {
            statusMessage = "下载任务无法保存，未开始下载。"
            return
        }
        beginDownloadWorkflow(request)
    }

    private func beginDownloadWorkflow(_ request: SteamWorkshopPendingDownloadRequest) {
        guard activeDownloadTask == nil,
              let job = downloadJobStore.activeJob(forWorkshopItemId: request.id), job.state == .running,
              downloadJobStore.lastSaveSucceeded else { return }
        let epoch = steamServiceClient.accountEpoch
        let key = "\(job.id)-\(job.attempt)"
        activeDownloadItemID = request.id
        activeDownloadJobKey = key
        activeDownloadWasCancelled = false
        statusMessage = "正在通过 Steam 下载 \(job.title)…"
        upsertTransientRecord(id: request.id, title: job.title, status: .downloading,
                              sizeText: downloadStatusSizeText(for: request.id))
        let observer = steamServiceClient.addEventObserver { [weak self] frame in
            guard let self, self.activeDownloadJobKey == key, self.steamServiceClient.accountEpoch == epoch,
                  frame.event == "downloadProgress", frame.jobId == key else { return }
            if let path = frame.root["stagingPath"]?.stringValue,
               let manifestId = frame.root["manifestId"]?.stringValue,
               let stagingURL = SteamWorkshopStagedReceipt.validatedStagingURL(
                    path: path,
                    stagingRoot: self.steamDownloadStagingRootURL.path
               ), let current = self.downloadJobStore.job(id: job.id),
               current.stagingPath != stagingURL.path || current.stagingManifestId != manifestId {
                _ = self.downloadJobStore.apply(
                    .stagingAllocated(path: stagingURL.path, manifestId: manifestId),
                    toID: job.id
                )
            }
            // Card progress projection is the next UI slice; never derive success from an event.
            let stage = frame.root["stage"]?.stringValue ?? ""
            self.statusMessage = stage == "validating" ? "正在校验 \(job.title)…" : "正在下载 \(job.title)…"
        }
        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.steamServiceClient.removeEventObserver(observer)
                if self.activeDownloadJobKey == key {
                    self.activeDownloadTask = nil
                    self.activeDownloadItemID = nil
                    self.activeDownloadJobKey = nil
                    self.activeDownloadWasCancelled = false
                    self.steamJobItemPayloads.removeValue(forKey: request.id)
                    self.processNextQueuedDownloadIfPossible()
                }
            }
            @MainActor func checkCurrent() throws {
                try Task.checkCancellation()
                guard self.activeDownloadJobKey == key, self.steamServiceClient.accountEpoch == epoch,
                      self.steamAuth.steamId == job.accountSteamId,
                      let current = self.downloadJobStore.job(id: job.id), current.isActive,
                      current.attempt == job.attempt else { throw CancellationError() }
            }
            do {
                try checkCurrent()
                let staging = self.steamDownloadStagingRootURL
                let allocation = Task.detached(priority: .utility) {
                    try SteamWorkshopLibraryTransaction.stagingBase(at: staging)
                }
                _ = try await withTaskCancellationHandler { try await allocation.value } onCancel: { allocation.cancel() }
                try checkCurrent()
                let receipt = try await self.steamWorkshopQueryClient.startStagedDownload(
                    jobId: key,
                    workshopId: request.id,
                    accountSteamId: job.accountSteamId,
                    stagingRoot: staging.path,
                    resumeStagingPath: job.stagingPath,
                    resumeManifestId: job.stagingManifestId
                )
                try checkCurrent()
                guard self.downloadJobStore.apply(.staged(receipt), toID: job.id) != nil else {
                    throw SteamWorkshopLibraryTransaction.Failure(message: "无法保存下载凭证，尚未入库。")
                }
                let library = self.steamDownloadLibraryRootURL
                let preparation = Task.detached(priority: .utility) {
                    try SteamWorkshopLibraryTransaction.prepare(receipt: receipt, attempt: job.attempt, libraryRoot: library)
                }
                let commit = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                try checkCurrent()
                guard self.downloadJobStore.apply(.committing(commit), toID: job.id) != nil else {
                    throw SteamWorkshopLibraryTransaction.Failure(message: "无法保存入库事务，旧版本保持不变。")
                }
                // The copied version is complete; retire the exact helper lease
                // before publishing ready. A cleanup failure keeps the old ready
                // pointer and the recoverable job identity instead of leaking it.
                try await self.removeOwnedDownloadStaging(receipt.stagingURL.path)
                // No suspension between the final identity check and the metadata rename.
                try checkCurrent()
                try self.publishDownloadedVersion(request, commit: commit, libraryRoot: library)
                // The metadata rename is authoritative even if writing the job completion fails.
                let recorded = self.downloadJobStore.apply(.completed, toID: job.id) != nil
                self.removeTransientRecord(id: request.id)
                self.reloadInstalledItems()
                self.statusMessage = recorded ? "已完成 \(job.title) 下载"
                    : "内容已入库；任务记录保存失败，下次启动将对账。"
            } catch {
                guard self.activeDownloadJobKey == key else { return }
                var terminalError: Error = error
                var cancelled = error is CancellationError || self.activeDownloadWasCancelled
                    || (error as? SteamServiceClient.RequestError) == .cancelled
                let invalidRecovery: Bool = {
                    guard case let .helperError(code, _) = error as? SteamServiceClient.RequestError else {
                        return false
                    }
                    return code == "integrity" || code == "unsupportedContent" || code == "protocolMismatch"
                }()
                if (cancelled || invalidRecovery),
                   let stagingPath = self.downloadJobStore.job(id: job.id)?.stagingPath {
                    do {
                        try await self.removeOwnedDownloadStaging(stagingPath)
                        if invalidRecovery {
                            _ = self.downloadJobStore.apply(.recoveryInvalidated, toID: job.id)
                        }
                    } catch {
                        cancelled = false
                        terminalError = SteamWorkshopLibraryTransaction.Failure(
                            message: "下载已停止，但暂存目录无法安全清理：\(error.localizedDescription)"
                        )
                    }
                }
                _ = self.downloadJobStore.apply(
                    cancelled ? .cancelled : .failed(terminalError.localizedDescription),
                    toID: job.id
                )
                if cancelled {
                    self.removeTransientRecord(id: request.id)
                } else {
                    self.upsertTransientRecord(
                        id: request.id,
                        title: job.title,
                        status: .failed(terminalError.localizedDescription),
                        sizeText: self.downloadStatusSizeText(for: request.id)
                    )
                }
                self.reloadInstalledItems()
                self.statusMessage = cancelled ? "已取消下载。" : terminalError.localizedDescription
                if !cancelled { self.downloadError = terminalError.localizedDescription }
            }
        }
    }

    private func removeOwnedDownloadStaging(_ path: String) async throws {
        let stagingRoot = steamDownloadStagingRootURL
        guard let stagingURL = SteamWorkshopStagedReceipt.validatedStagingURL(
            path: path,
            stagingRoot: stagingRoot.path
        ) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "下载暂存身份无效。")
        }
        try await Task.detached(priority: .utility) {
            try SteamWorkshopLibraryTransaction.removeStagingLease(
                stagingURL: stagingURL,
                stagingRoot: stagingRoot
            )
        }.value
    }

    func cancelActiveDownload() { cancelDownloadImmediately(showFeedback: true) }
    func cancelDownload(itemID: String) { cancelDownloadImmediately(itemID: itemID, showFeedback: true) }

    func cancelDownloadImmediately(itemID: String? = nil, showFeedback: Bool) {
        if let itemID, itemID != activeDownloadItemID {
            if let job = downloadJobStore.activeJob(forWorkshopItemId: itemID),
               downloadJobStore.cancel(id: job.id) != nil {
                steamJobItemPayloads.removeValue(forKey: itemID)
                removeTransientRecord(id: itemID)
                if showFeedback { statusMessage = "已移出下载队列。" }
            }
            return
        }
        guard activeDownloadTask != nil else { return }
        activeDownloadWasCancelled = true
        activeDownloadTask?.cancel()
        if showFeedback { statusMessage = "正在取消当前下载…" }
    }

    private func enqueueDownloadRequest(id: String, pageTitle: String?, item: SteamWorkshopBrowserItem?) {
        guard let account = downloadAdmissionAccount() else { return }
        let title = pageTitle ?? "Workshop #\(id)"
        // SK4.1：入队真值在 JobStore——同项去重，重复点击/跨来源点击只一个任务。
        let (_, isNew) = downloadJobStore.enqueue(
            workshopItemId: id,
            title: title,
            accountSteamId: account
        )
        guard downloadJobStore.lastSaveSucceeded else {
            statusMessage = "下载任务无法保存，未加入队列。"
            return
        }
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

        // 恢复任务只按当前在线账号出队。无账号时保持队列原样，不制造匿名任务。
        guard steamAuth.isOnline, let account = steamAuth.steamId else { return }
        guard let next = downloadJobStore.popNextQueued(
            forAccount: account
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
