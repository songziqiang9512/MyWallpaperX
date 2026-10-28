//
//  SteamWorkshopService+DownloadFiltering.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    /// Source facts for the unified downloads page; other pages keep the full
    /// catalog. A brand-new task stays in the queue popover, while a retry with
    /// failure history for the supplied account keeps its original card.
    /// Published account inputs are explicit so willSet cannot consult the
    /// previous account. Missing/empty identity never borrows the live getter.
    func excludedDownloadReferences(
        in records: [SteamWorkshopDownloadRecord],
        accountSteamID: String?
    ) -> Set<WallpaperReference> {
        var excluded: Set<WallpaperReference> = []
        var failedHistoryItemIDs: Set<String>?
        for record in records {
            let reference = WallpaperReference(provider: .steamWorkshop, sourceID: record.id)
            if let intentAccount = record.intentAccountSteamID,
               accountSteamID != intentAccount || accountSteamID?.isEmpty != false {
                excluded.insert(reference)
                continue
            }
            switch record.status {
            case .ready, .failed:
                break
            case .queued, .downloading:
                guard let accountSteamID, !accountSteamID.isEmpty,
                      hasFailedDownloadHistory(itemID: record.id, accountSteamId: accountSteamID,
                                               failedItemIDs: &failedHistoryItemIDs) else {
                    excluded.insert(reference)
                    continue
                }
            }
        }
        return excluded
    }

    /// 把现役账号的持久失败意图与失败后的重试任务合并进记录列表。
    /// - 失败事实的持久 owner 是 JobStore（jobs/history 落盘）：`downloads` 里的
    ///   瞬态失败记录会被下一次库扫描整表替换，重启后的可见性由 JobStore 决定，
    ///   不由任何临时 UI 状态决定。
    /// - 只为 `downloads` 中不存在的 item 合成记录：ready 卡不被失败覆盖，
    ///   也不产生同 item 两张卡；进行中的瞬态卡（含进度）原样保留。
    /// - 合成结果写回 `downloads`（由 refreshDownloadIntentProjection 值相等守卫执行），
    ///   删除/详情因此走同一条 record 路径（含既有的 discardFailedDownload
    ///   「仅移除意图、不删文件」语义）。
    func downloadsWithFailedIntents(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        // Published/legacy source rows have no provenance tag and are account
        // independent. Keep current admitted transient snapshots (metadata and
        // progress included); only their original JobStore can revoke them.
        let account = currentSteamDownloadAccount
        let admittedItemIDs = Set(downloadJobStore.jobs.lazy.filter {
            $0.accountSteamId == account && $0.state != .cancelled && $0.state != .completed
        }.map(\.workshopItemId))
        let sourceRecords = records.filter {
            guard let intentAccount = $0.intentAccountSteamID else { return true }
            return intentAccount == account && admittedItemIDs.contains($0.id)
        }
        guard let account else { return sourceRecords }
        // 同 item 只合成一张卡：knownIDs 之外的每个 workshop intent 只取第一条
        // 命中意图。存量形态里同账号同 item 可能有多条 failed job（旧版本落盘
        // 的重复 failed intents，见 discardFailedDownload 的去重注释）；多余的
        // 意图仍由既有 discardFailedDownload / terminal cleanup 路径清理，投影
        // 不删 job，只保证不产生同 item 两张卡。
        var synthesizedItemIDs = Set(sourceRecords.map(\.id))
        var synthesized: [SteamWorkshopDownloadRecord] = []
        var failedHistoryItemIDs: Set<String>?
        for job in downloadJobStore.jobs {
            guard job.accountSteamId == account,
                  synthesizedItemIDs.contains(job.workshopItemId) == false else { continue }
            let record: SteamWorkshopDownloadRecord?
            switch job.state {
            case .failed:
                record = synthesizedFailedIntentRecord(from: job)
            case .queued, .running, .staged, .committing:
                // 失败后的重试：同 workshop intent 的卡续显；从未失败的任务不合成。
                record = hasFailedDownloadHistory(
                    itemID: job.workshopItemId, accountSteamId: account, failedItemIDs: &failedHistoryItemIDs
                )
                    ? synthesizedActiveRetryRecord(from: job)
                    : nil
            case .cancelled, .completed:
                record = nil
            }
            guard let record else { continue }
            synthesized.append(record)
            synthesizedItemIDs.insert(job.workshopItemId)
        }
        guard synthesized.isEmpty == false else { return sourceRecords }
        return (sourceRecords + synthesized).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 现役下载账号（合成与历史判定的账号隔离边界：跨账号不接管旧失败意图）。
    var currentSteamDownloadAccount: String? {
        guard let account = steamAuth.steamId, account.isEmpty == false else { return nil }
        return account
    }

    /// 调用方在一次同步投影内复用当前账号的失败集合；首次遇到重试才读取历史。
    func hasFailedDownloadHistory(
        itemID: String, accountSteamId account: String? = nil, failedItemIDs: inout Set<String>?
    ) -> Bool {
        guard let account = account ?? currentSteamDownloadAccount else { return false }
        if let failedItemIDs { return failedItemIDs.contains(itemID) }
        let itemIDs = Set(downloadJobStore.history.lazy.filter {
            $0.accountSteamId == account && $0.outcome == .failed
        }.map(\.workshopItemId))
        failedItemIDs = itemIDs
        return itemIDs.contains(itemID)
    }

    /// 现役账号下该 item 是否存在持久失败意图（ready 卡「更新失败」附加状态的判定）。
    func hasFailedDownloadIntent(for itemID: String) -> Bool {
        guard let account = currentSteamDownloadAccount else { return false }
        return downloadJobStore.failedJob(forWorkshopItemId: itemID, accountSteamId: account) != nil
    }

    /// 现役账号下该 item 失败意图的失败摘要（无失败意图或无摘要返回 nil）。
    func failedDownloadIntentMessage(for itemID: String) -> String? {
        guard let account = currentSteamDownloadAccount else { return nil }
        return downloadJobStore.failedJob(forWorkshopItemId: itemID, accountSteamId: account)?.failureMessage
    }

    private func synthesizedFailedIntentRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(
            id: job.workshopItemId,
            title: job.title,
            description: "",
            tags: [],
            folderURL: libraryRootURL,
            projectFileURL: nil,
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: nil,
            sourceVideoURL: nil,
            exportedVideoURL: nil,
            updatedAt: job.updatedAt,
            sizeText: "",
            status: .failed(job.failureMessage ?? "下载失败"),
            browserItem: nil,
            contentType: .unknown,
            dependencyItemID: nil,
            dependencyStatus: .none,
            intentAccountSteamID: job.accountSteamId
        )
    }

    private func synthesizedActiveRetryRecord(from job: SteamDownloadJob) -> SteamWorkshopDownloadRecord {
        SteamWorkshopDownloadRecord(
            id: job.workshopItemId,
            title: job.title,
            description: "",
            tags: [],
            folderURL: libraryRootURL,
            projectFileURL: nil,
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: nil,
            sourceVideoURL: nil,
            exportedVideoURL: nil,
            updatedAt: job.updatedAt,
            sizeText: job.state == .queued ? "等待下载" : "",
            status: job.state == .queued ? .queued : .downloading,
            browserItem: nil,
            contentType: .unknown,
            dependencyItemID: nil,
            dependencyStatus: .none,
            intentAccountSteamID: job.accountSteamId
        )
    }

    func clearFilters() {
        guard !facetFilters.isEmpty || !browserContentMode.isAll else { return }
        let wasSuppressed = suppressAutomaticBrowseNavigation
        suppressAutomaticBrowseNavigation = true
        browserContentMode = .all
        facetFilters = .none
        suppressAutomaticBrowseNavigation = wasSuppressed
        if !wasSuppressed { navigateToBrowse() }
    }
}
