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
            if !activeDownloadItemIDs.contains(id) {
                statusMessage = "\(title) 已在下载任务中。"
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
        if activeDownloadTasks.count >= maximumConcurrentDownloads {
            enqueueDownloadRequest(id: id, pageTitle: pageTitle, item: requestItem)
            return
        }
        startDownloadRequest(SteamWorkshopPendingDownloadRequest(id: id, pageTitle: pageTitle, item: requestItem))
    }

    /// 同步准入必须发生在 JobStore、瞬态卡片及执行器副作用之前。
    /// 只读新账号 owner，不读旧密码/网页登录，也不触发恢复或登录 UI。
    private func downloadAdmissionAccount() -> String? {
        guard steamAuth.isOnline, let account = steamAuth.steamId, !account.isEmpty else {
            presentSteamLoginForUserAction(context: "下载")
            return nil
        }
        return account
    }

    func canRequestDownload(id: String) -> Bool {
        !isQueuedDownloadRequest(id: id)
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
        activeDownloadTasks.count >= maximumConcurrentDownloads
            || !reservedLibraryCopyBytesByJobKey.isEmpty
    }

    func startDownloadRequest(_ request: SteamWorkshopPendingDownloadRequest) {
        guard let account = downloadAdmissionAccount() else { return }
        let job: SteamDownloadJob
        if let active = downloadJobStore.activeJob(forWorkshopItemId: request.id) {
            guard active.accountSteamId == account else { return }
            if active.state == .queued {
                guard let started = downloadJobStore.apply(.started, toID: active.id) else { return }
                job = started
            } else {
                guard active.state == .running else { return }
                job = active
            }
        } else if let failed = downloadJobStore.failedJob(
            forWorkshopItemId: request.id,
            accountSteamId: account
        ) {
            // Explicit retry keeps one logical job and advances its attempt. A
            // different account can never adopt the failed intent.
            let event: SteamDownloadJobEvent = failed.stagingPath != nil
                && failed.stagingManifestId != nil
                && failed.stagingLeaseIdentity?.isComplete == true
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
        guard activeDownloadTasks.count < maximumConcurrentDownloads,
              let job = downloadJobStore.activeJob(forWorkshopItemId: request.id), job.state == .running,
              downloadJobStore.lastSaveSucceeded else { return }
        let epoch = steamServiceClient.accountEpoch
        let key = "\(job.id)-\(job.attempt)"
        downloadProgressStore.begin(itemID: request.id, jobKey: key, attempt: job.attempt)
        activeDownloadItemIDs.insert(request.id)
        activeDownloadJobKeysByItemID[request.id] = key
        statusMessage = "正在通过 Steam 下载 \(job.title)…"
        upsertTransientRecord(id: request.id, title: job.title, status: .downloading,
                              sizeText: downloadStatusSizeText(for: request.id))
        let observer = steamServiceClient.addEventObserver { [weak self] frame in
            guard let self, self.activeDownloadJobKeysByItemID[request.id] == key,
                  self.steamServiceClient.accountEpoch == epoch,
                  frame.event == "downloadProgress", frame.jobId == key else { return }
            guard frame.accountEpoch == epoch else {
                self.activeDownloadTasks[key]?.cancel()
                return
            }
            let stage = frame.root["stage"]?.stringValue ?? ""
            if let path = frame.root["stagingPath"]?.stringValue,
               let manifestId = frame.root["manifestId"]?.stringValue {
                guard let deviceText = frame.root["stagingDevice"]?.stringValue,
                      let device = UInt64(deviceText),
                      let inodeText = frame.root["stagingInode"]?.stringValue,
                      let inode = UInt64(inodeText), inode > 0,
                      let birthSecondsText = frame.root["stagingBirthSeconds"]?.stringValue,
                      let birthSeconds = Int64(birthSecondsText), birthSeconds > 0,
                      let birthNanosecondsText = frame.root["stagingBirthNanoseconds"]?.stringValue,
                      let birthNanoseconds = Int64(birthNanosecondsText),
                      (0..<1_000_000_000).contains(birthNanoseconds),
                      let stagingURL = SteamWorkshopStagedReceipt.validatedStagingURL(
                    path: path,
                    stagingRoot: self.steamDownloadStagingRootURL.path
                      ), let current = self.downloadJobStore.job(id: job.id) else {
                    self.activeDownloadTasks[key]?.cancel()
                    return
                }
                let helperIdentity = SteamWorkshopStagingLeaseIdentity(
                    device: device,
                    inode: inode,
                    birthSeconds: birthSeconds,
                    birthNanoseconds: birthNanoseconds
                )
                guard let localIdentity = try? SteamWorkshopLibraryTransaction.stagingLeaseIdentity(
                    stagingURL: stagingURL,
                    stagingRoot: self.steamDownloadStagingRootURL
                ), localIdentity == helperIdentity else {
                    self.activeDownloadTasks[key]?.cancel()
                    return
                }
                if current.stagingPath != stagingURL.path
                    || current.stagingManifestId != manifestId
                    || current.stagingLeaseIdentity != helperIdentity {
                    guard self.downloadJobStore.apply(
                        .stagingAllocated(
                            path: stagingURL.path,
                            manifestId: manifestId,
                            leaseIdentity: helperIdentity
                        ),
                        toID: job.id
                    ) != nil else {
                        self.activeDownloadTasks[key]?.cancel()
                        return
                    }
                }
                if stage == "allocated" {
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.activeDownloadJobKeysByItemID[request.id] == key,
                              self.steamServiceClient.accountEpoch == epoch,
                              self.cancellationFeedbackByDownloadJobKey[key] == nil,
                              let current = self.downloadJobStore.job(id: job.id),
                              current.isActive, current.attempt == job.attempt else { return }
                        do {
                            try await self.steamWorkshopQueryClient.acknowledgeStagedDownload(
                                jobId: key,
                                stagingPath: stagingURL.path,
                                manifestId: manifestId,
                                stagingLeaseIdentity: helperIdentity
                            )
                        } catch {
                            self.activeDownloadTasks[key]?.cancel()
                        }
                    }
                }
            }
            // Progress remains item scoped and never enters the service-wide
            // ObservableObject stream. A helper event never establishes success.
            if let sequence = frame.sequence {
                _ = self.downloadProgressStore.receiveHelperEvent(
                    itemID: request.id,
                    jobKey: key,
                    attempt: job.attempt,
                    sequence: sequence,
                    stage: stage,
                    totalBytes: frame.root["totalBytes"]?.intValue.map(Int64.init),
                    verifiedBytes: frame.root["verifiedBytes"]?.intValue.map(Int64.init)
                )
            }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.steamServiceClient.removeEventObserver(observer)
                self.activeDownloadTasks[key] = nil
                self.cancellationFeedbackByDownloadJobKey.removeValue(forKey: key)
                self.reservedLibraryCopyBytesByJobKey[key] = nil
                if self.activeDownloadJobKeysByItemID[request.id] == key {
                    self.activeDownloadJobKeysByItemID[request.id] = nil
                    self.activeDownloadItemIDs.remove(request.id)
                    self.steamJobItemPayloads.removeValue(forKey: request.id)
                }
                self.scheduleTerminalDownloadCleanup()
                self.processNextQueuedDownloadIfPossible()
            }
            @MainActor func checkCurrent() throws {
                try Task.checkCancellation()
                guard self.activeDownloadJobKeysByItemID[request.id] == key,
                      self.steamServiceClient.accountEpoch == epoch,
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
                var resumePath = job.stagingPath
                var resumeManifestId = job.stagingManifestId
                var resumeIdentity = job.stagingLeaseIdentity
                if resumePath != nil || resumeManifestId != nil || resumeIdentity != nil {
                    let persistedIdentityIsCurrent: Bool
                    if let path = resumePath,
                       resumeManifestId != nil,
                       let expectedIdentity = resumeIdentity, expectedIdentity.isComplete,
                       let stagingURL = SteamWorkshopStagedReceipt.validatedStagingURL(
                        path: path,
                        stagingRoot: staging.path
                       ) {
                        persistedIdentityIsCurrent = (try? SteamWorkshopLibraryTransaction.stagingLeaseIdentity(
                            stagingURL: stagingURL,
                            stagingRoot: staging
                        )) == expectedIdentity
                    } else {
                        persistedIdentityIsCurrent = false
                    }
                    if !persistedIdentityIsCurrent {
                        guard self.downloadJobStore.apply(.recoveryInvalidated, toID: job.id) != nil else {
                            throw SteamWorkshopLibraryTransaction.Failure(
                                message: "无法保存失效的下载暂存身份，未开始下载。"
                            )
                        }
                        resumePath = nil
                        resumeManifestId = nil
                        resumeIdentity = nil
                    }
                }
                let receipt = try await self.steamWorkshopQueryClient.startStagedDownload(
                    jobId: key,
                    workshopId: request.id,
                    accountSteamId: job.accountSteamId,
                    stagingRoot: staging.path,
                    resumeStagingPath: resumePath,
                    resumeManifestId: resumeManifestId,
                    resumeStagingLeaseIdentity: resumeIdentity
                )
                try checkCurrent()
                guard let helperIdentity = receipt.stagingLeaseIdentity,
                      let allocatedIdentity = self.downloadJobStore.job(id: job.id)?.stagingLeaseIdentity,
                      helperIdentity == allocatedIdentity else {
                    throw SteamWorkshopLibraryTransaction.Failure(
                        message: "下载暂存身份未在内容写入前持久化，拒绝收养终态路径。"
                    )
                }
                let localIdentity = try SteamWorkshopLibraryTransaction.stagingLeaseIdentity(
                    stagingURL: receipt.stagingURL,
                    stagingRoot: staging
                )
                guard localIdentity == helperIdentity else {
                    throw SteamWorkshopLibraryTransaction.Failure(
                        message: "下载暂存目录在 helper 完成后发生替换。"
                    )
                }
                guard self.downloadJobStore.apply(.staged(receipt), toID: job.id) != nil else {
                    throw SteamWorkshopLibraryTransaction.Failure(message: "无法保存下载凭证，尚未入库。")
                }
                self.downloadProgressStore.markSaving(itemID: request.id, jobKey: key)
                try await self.claimLibraryCopyCapacity(jobKey: key)
                try checkCurrent()
                let library = self.steamDownloadLibraryRootURL
                let capacity = Task.detached(priority: .utility) {
                    (
                        available: try SteamWorkshopLibraryTransaction.availableDiskBytes(at: library),
                        sharesStagingVolume: try SteamWorkshopLibraryTransaction.areOnSameFileSystem(library, staging)
                    )
                }
                let capacitySnapshot = try await capacity.value
                try checkCurrent()
                try self.reserveLibraryCopyCapacity(
                    required: Int64(receipt.verifiedBytes),
                    available: capacitySnapshot.available,
                    sharesStagingVolume: capacitySnapshot.sharesStagingVolume,
                    jobKey: key
                )
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
                // No suspension between the final identity check and the metadata rename.
                try checkCurrent()
                try self.publishDownloadedVersion(request, commit: commit, libraryRoot: library)
                // The metadata rename is authoritative even if writing the job completion fails.
                let recorded = self.downloadJobStore.apply(.completed, toID: job.id) != nil
                self.removeTransientRecord(id: request.id)
                self.reloadInstalledItems()
                self.downloadProgressStore.clear(itemID: request.id, jobKey: key)
                self.statusMessage = recorded ? "已完成 \(job.title) 下载"
                    : "内容已入库；任务记录保存失败，下次启动将对账。"
                // Publish UI while the account/attempt check is still current.
                // Cleanup can suspend; it must not project an old account afterwards.
                if recorded { await self.cleanupTerminalDownload(job.id) }
            } catch {
                guard self.activeDownloadJobKeysByItemID[request.id] == key else { return }
                var terminalError: Error = error
                let cancellationShowsFeedback = self.cancellationFeedbackByDownloadJobKey[key] ?? true
                let wasDurablyCancelled = self.downloadJobStore.job(id: job.id)?.state == .cancelled
                var cancellationCleanupFailed = false
                var cancelled = error is CancellationError
                    || self.cancellationFeedbackByDownloadJobKey[key] != nil
                    || (error as? SteamServiceClient.RequestError) == .cancelled
                let invalidRecovery: Bool = {
                    guard case let .helperError(code, _) = error as? SteamServiceClient.RequestError else {
                        return false
                    }
                    return code == "integrity" || code == "unsupportedContent" || code == "protocolMismatch"
                }()
                if cancelled || invalidRecovery,
                   let cleanupJob = self.downloadJobStore.job(id: job.id),
                   cleanupJob.stagingPath != nil {
                    do {
                        try await self.removeOwnedDownloadStaging(cleanupJob)
                        if invalidRecovery {
                            _ = self.downloadJobStore.apply(.recoveryInvalidated, toID: job.id)
                        }
                    } catch {
                        terminalError = SteamWorkshopLibraryTransaction.Failure(
                            message: "下载已停止，但暂存目录无法安全清理：\(error.localizedDescription)"
                        )
                        if wasDurablyCancelled {
                            cancellationCleanupFailed = true
                        } else {
                            cancelled = false
                        }
                    }
                }
                let failureMessage = self.downloadFailureMessage(terminalError)
                _ = self.downloadJobStore.apply(
                    cancelled ? .cancelled : .failed(failureMessage),
                    toID: job.id
                )
                if cancelled {
                    self.removeTransientRecord(id: request.id)
                    self.downloadProgressStore.clear(itemID: request.id, jobKey: key)
                    if cancellationCleanupFailed {
                        self.downloadError = failureMessage
                    }
                } else {
                    self.upsertTransientRecord(
                        id: request.id,
                        title: job.title,
                        status: .failed(failureMessage),
                        sizeText: self.downloadStatusSizeText(for: request.id)
                    )
                    self.downloadError = failureMessage
                    self.downloadProgressStore.fail(itemID: request.id, jobKey: key, message: failureMessage)
                }
                self.reloadInstalledItems()
                if cancelled {
                    if cancellationShowsFeedback { self.statusMessage = "已取消下载。" }
                } else {
                    self.statusMessage = failureMessage
                }
            }
        }
        activeDownloadTasks[key] = task
    }

    private func removeOwnedDownloadStaging(_ job: SteamDownloadJob) async throws {
        let stagingRoot = steamDownloadStagingRootURL
        guard let path = job.stagingPath,
              let leaseIdentity = job.stagingLeaseIdentity,
              leaseIdentity.isComplete else {
            throw SteamWorkshopLibraryTransaction.Failure(
                message: "下载暂存缺少稳定身份，拒绝按路径清理。"
            )
        }
        guard let stagingURL = SteamWorkshopStagedReceipt.validatedStagingURL(
            path: path,
            stagingRoot: stagingRoot.path
        ) else {
            throw SteamWorkshopLibraryTransaction.Failure(message: "下载暂存身份无效。")
        }
        try await Task.detached(priority: .utility) {
            try SteamWorkshopLibraryTransaction.removeStagingLease(
                stagingURL: stagingURL,
                stagingRoot: stagingRoot,
                expectedIdentity: leaseIdentity
            )
        }.value
    }

    /// Terminal cleanup is durable and independent of login. A published ready
    /// pointer is never rolled back because deleting its staging lease failed.
    @discardableResult
    private func cleanupTerminalDownload(_ jobID: String) async -> Bool {
        guard let job = downloadJobStore.job(id: jobID),
              job.state == .completed || job.state == .cancelled else { return false }
        do {
            if job.stagingPath != nil { try await removeOwnedDownloadStaging(job) }
            return downloadJobStore.apply(.resourcesReleased, toID: jobID) != nil
        } catch {
            downloadError = "内容状态已保存，但下载暂存清理失败，稍后将重试：\(error.localizedDescription)"
            return false
        }
    }

    func scheduleTerminalDownloadCleanup() {
        guard terminalDownloadCleanupTask == nil else { return }
        terminalDownloadCleanupTask = Task { [weak self] in
            guard let self else { return }
            // Drain terminals arriving while filesystem work suspends this actor.
            // A failed deletion is attempted only once per drain, avoiding a spin.
            var attempted: Set<String> = []
            while let job = self.downloadJobStore.jobs.first(where: {
                ($0.state == .completed || $0.state == .cancelled)
                    && ($0.stagingPath != nil || $0.preparedCommit != nil)
                    && !attempted.contains($0.id)
                    && self.activeDownloadJobKeysByItemID[$0.workshopItemId] != "\($0.id)-\($0.attempt)"
            }) {
                attempted.insert(job.id)
                await self.cleanupTerminalDownload(job.id)
            }
            self.terminalDownloadCleanupTask = nil
        }
    }

    func discardFailedDownload(jobID: String) {
        guard let job = downloadJobStore.job(id: jobID), job.state == .failed,
              job.accountSteamId == steamAuth.steamId else { return }
        // Old releases could persist duplicate failed intents for the same item.
        // Abandon all matching failures so an older record cannot reappear.
        let failures = downloadJobStore.jobs.filter {
            $0.state == .failed && $0.workshopItemId == job.workshopItemId
                && $0.accountSteamId == job.accountSteamId
        }
        for failure in failures {
            guard downloadJobStore.cancel(id: failure.id) != nil else {
                downloadError = "放弃下载任务无法保存，请重试。"
                scheduleTerminalDownloadCleanup()
                return
            }
            downloadProgressStore.clear(itemID: failure.workshopItemId, jobKey: "\(failure.id)-\(failure.attempt)")
        }
        removeTransientRecord(id: job.workshopItemId)
        scheduleTerminalDownloadCleanup()
    }

    func reserveLibraryCopyCapacity(
        required: Int64,
        available: Int64,
        sharesStagingVolume: Bool,
        jobKey: String
    ) throws {
        var reserved = reservedLibraryCopyBytesByJobKey
            .filter { $0.key != jobKey }
            .values.reduce(Int64(0), +)
        if sharesStagingVolume {
            let helperJobs = activeDownloadTasks.keys.filter {
                $0 != jobKey && reservedLibraryCopyBytesByJobKey[$0] == nil
            }.count
            reserved += Int64(helperJobs) * Int64(SteamWorkshopLibraryTransaction.maxBytes)
        }
        guard SteamWorkshopLibraryTransaction.canReserveDiskBytes(
            required: required,
            available: available,
            alreadyReserved: reserved
        ) else {
            throw SteamWorkshopLibraryTransaction.Failure(
                message: "磁盘空间不足，下载暂存已保留；释放空间后可重试。"
            )
        }
        reservedLibraryCopyBytesByJobKey[jobKey] = required
    }

    func claimLibraryCopyCapacity(jobKey: String) async throws {
        // Copying a version changes the observed free-space value. Serialize
        // copies so an earlier reservation is never subtracted a second time
        // after its bytes have already reached disk.
        while reservedLibraryCopyBytesByJobKey.keys.contains(where: { $0 != jobKey }) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        reservedLibraryCopyBytesByJobKey[jobKey] = 0
    }

    private func downloadFailureMessage(_ error: Error) -> String {
        if case let .helperError(code, _) = error as? SteamServiceClient.RequestError,
           code == "diskFull" {
            return "磁盘空间不足，下载暂存已保留；释放空间后可重试。"
        }
        return error.localizedDescription
    }

    func cancelActiveDownload() { cancelDownloadImmediately(showFeedback: true) }
    func cancelDownload(itemID: String) { cancelDownloadImmediately(itemID: itemID, showFeedback: true) }

    func cancelDownloadImmediately(itemID: String? = nil, showFeedback: Bool) {
        let keys: [String]
        if let itemID {
            if let key = activeDownloadJobKeysByItemID[itemID] {
                keys = [key]
            } else {
                if let job = downloadJobStore.activeJob(forWorkshopItemId: itemID),
                   downloadJobStore.cancel(id: job.id) != nil {
                    steamJobItemPayloads.removeValue(forKey: itemID)
                    removeTransientRecord(id: itemID)
                    scheduleTerminalDownloadCleanup()
                    if showFeedback { statusMessage = "已移出下载队列。" }
                }
                return
            }
        } else {
            keys = Array(activeDownloadTasks.keys)
        }
        guard !keys.isEmpty else { return }
        for key in keys {
            cancellationFeedbackByDownloadJobKey[key] = showFeedback
            activeDownloadTasks[key]?.cancel()
        }
        if showFeedback {
            statusMessage = keys.count == 1 ? "正在取消当前下载…" : "正在取消 \(keys.count) 个下载…"
        }
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
        guard reservedLibraryCopyBytesByJobKey.isEmpty else { return }

        // 恢复任务只按当前在线账号出队。无账号时保持队列原样，不制造匿名任务。
        guard steamAuth.isOnline, let account = steamAuth.steamId else { return }
        while activeDownloadTasks.count < maximumConcurrentDownloads,
              let next = downloadJobStore.popNextQueued(forAccount: account) {
            let before = activeDownloadTasks.count
            startDownloadRequest(SteamWorkshopPendingDownloadRequest(
                id: next.workshopItemId,
                pageTitle: next.title,
                item: steamJobItemPayloads[next.workshopItemId]
            ))
            if activeDownloadTasks.count == before { break }
        }
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
