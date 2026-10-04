//
//  SteamWorkshopService+DownloadFiltering.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    /// D7 单一投影：记录 ⊕ 现役账号失败意图 → 模式过滤 → 搜索 → 排序。
    /// 失败项与失败后的重试任务保留在下载页；从未失败的新 queued/downloading
    /// 只在下载弹窗展示，不进本列表。
    func filteredAndSortedDownloads(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        let modeFiltered = downloadsWithFailedIntents(from: records).filter { record in
            switch downloadsDisplayMode {
            case .all:
                // all 含未知类型的失败意图。
                return true
            case .video:
                return record.contentType == .video
            case .web:
                return record.contentType == .web
            case .scene:
                return record.contentType == .scene
            }
        }
        let visible = modeFiltered.filter { record in
            switch record.status {
            case .ready, .failed:
                return true
            case .queued, .downloading:
                // 进行中意图 = 失败后的重试（同卡续显进度）；从未失败的新任务
                // 属弹窗队列，不进下载页。
                return hasFailedDownloadHistory(itemID: record.id)
            }
        }
        return sortedDownloadRecords(visible)
    }

    /// 把现役账号的持久失败意图与失败后的重试任务合并进记录列表。
    /// - 失败事实的持久 owner 是 JobStore（jobs/history 落盘）：`downloads` 里的
    ///   瞬态失败记录会被下一次库扫描整表替换，重启后的可见性由 JobStore 决定，
    ///   不由任何临时 UI 状态决定。
    /// - 只为 `downloads` 中不存在的 item 合成记录：ready 卡不被失败覆盖，
    ///   也不产生同 item 两张卡；进行中的瞬态卡（含进度）原样保留。
    /// - 合成结果写回 `downloads`（由 refreshDisplayedDownloads 值相等守卫执行），
    ///   选中/删除/详情因此走同一条 record 路径（含既有的 discardFailedDownload
    ///   「仅移除意图、不删文件」语义）。
    func downloadsWithFailedIntents(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        guard let account = currentSteamDownloadAccount else { return records }
        // 同 item 只合成一张卡：knownIDs 之外的每个 workshop intent 只取第一条
        // 命中意图。存量形态里同账号同 item 可能有多条 failed job（旧版本落盘
        // 的重复 failed intents，见 discardFailedDownload 的去重注释）；多余的
        // 意图仍由既有 discardFailedDownload / terminal cleanup 路径清理，投影
        // 不删 job，只保证不产生同 item 两张卡。
        var synthesizedItemIDs = Set(records.map(\.id))
        var synthesized: [SteamWorkshopDownloadRecord] = []
        for job in downloadJobStore.jobs {
            guard job.accountSteamId == account,
                  synthesizedItemIDs.contains(job.workshopItemId) == false else { continue }
            let record: SteamWorkshopDownloadRecord?
            switch job.state {
            case .failed:
                record = synthesizedFailedIntentRecord(from: job)
            case .queued, .running, .staged, .committing:
                // 失败后的重试：同 workshop intent 的卡续显；从未失败的任务不合成。
                record = hasFailedDownloadHistory(itemID: job.workshopItemId, accountSteamId: account)
                    ? synthesizedActiveRetryRecord(from: job)
                    : nil
            case .cancelled, .completed:
                record = nil
            }
            guard let record else { continue }
            synthesized.append(record)
            synthesizedItemIDs.insert(job.workshopItemId)
        }
        guard synthesized.isEmpty == false else { return records }
        return (records + synthesized).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 现役下载账号（合成与历史判定的账号隔离边界：跨账号不接管旧失败意图）。
    var currentSteamDownloadAccount: String? {
        guard let account = steamAuth.steamId, account.isEmpty == false else { return nil }
        return account
    }

    /// 该 item 在现役账号下是否存在失败历史（重试中/未完成的判定事实）。
    func hasFailedDownloadHistory(itemID: String, accountSteamId account: String? = nil) -> Bool {
        guard let account = account ?? currentSteamDownloadAccount else { return false }
        return downloadJobStore.history.contains { entry in
            entry.workshopItemId == itemID
                && entry.accountSteamId == account
                && entry.outcome == .failed
        }
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
            dependencyStatus: .none
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
            dependencyStatus: .none
        )
    }

    private func sortedDownloadRecords(_ filtered: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        let query = downloadsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [SteamWorkshopDownloadRecord]
        if query.isEmpty {
            searched = filtered
        } else {
            let normalized = query.localizedLowercase
            let idQuery = Self.workshopItemIDSearchID(from: query)?.localizedLowercase ?? normalized
            searched = filtered.filter {
                $0.title.localizedLowercase.contains(normalized)
                || $0.description.localizedLowercase.contains(normalized)
                || $0.tags.contains(where: { $0.localizedLowercase.contains(normalized) })
                || $0.id.localizedLowercase.contains(idQuery)
                || $0.browserItem?.author.localizedLowercase.contains(normalized) == true
            }
        }
        // Size ordering parses each record's size text exactly once instead of
        // twice per comparison inside the sort closure (O(N log N) parses for
        // an O(N log N) sort).
        let sorted: [SteamWorkshopDownloadRecord]
        if downloadsSortMode == .size {
            let sized = searched.map { record -> (record: SteamWorkshopDownloadRecord, bytes: Int64?) in
                (record, Self.parseByteCount(from: record.sizeText))
            }
            sorted = sized.sorted { lhs, rhs in
                switch (lhs.bytes, rhs.bytes) {
                case let (lhsBytes?, rhsBytes?):
                    if lhsBytes != rhsBytes {
                        return downloadsSortAscending ? (lhsBytes < rhsBytes) : (lhsBytes > rhsBytes)
                    }
                case (.some, nil):
                    // 已知大小恒在未知大小之前（与排序方向无关）：失败意图的未知
                    // 大小不当作零大小完成包。
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return downloadRecordStableTieBreak(lhs.record, rhs.record)
            }.map(\.record)
        } else {
            sorted = searched.sorted { lhs, rhs in
                switch downloadsSortMode {
                case .updatedAt:
                    if lhs.updatedAt != rhs.updatedAt {
                        return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
                    }
                case .title:
                    let comparison = lhs.title.localizedStandardCompare(rhs.title)
                    if comparison != .orderedSame {
                        return downloadsSortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
                    }
                    if lhs.updatedAt != rhs.updatedAt {
                        return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
                    }
                case .size:
                    // Handled by the decorate-sort path above.
                    break
                }
                return downloadRecordStableTieBreak(lhs, rhs)
            }
        }
        return sorted
    }

    /// 用户选项并列时的最终稳定 tie-break：workshop item ID。
    private func downloadRecordStableTieBreak(
        _ lhs: SteamWorkshopDownloadRecord,
        _ rhs: SteamWorkshopDownloadRecord
    ) -> Bool {
        let comparison = lhs.title.localizedStandardCompare(rhs.title)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    func sanitizeDownloadSelectionAgainstDisplayedDownloads() {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let visibleSelection = selectedDownloadIDs.intersection(visibleIDs)
        let normalizedPrimaryID: String? = {
            if let selectedDownloadID, visibleIDs.contains(selectedDownloadID) {
                return selectedDownloadID
            }
            if isDownloadsMultiSelectMode {
                return firstDisplayedDownloadID(in: visibleSelection)
            }
            return nil
        }()
        let normalizedSelectedIDs = isDownloadsMultiSelectMode
            ? visibleSelection
            : (normalizedPrimaryID.map { [$0] } ?? [])
        guard normalizedPrimaryID != selectedDownloadID || normalizedSelectedIDs != selectedDownloadIDs else {
            return
        }
        publishDownloadSelectionState(
            primaryID: normalizedPrimaryID,
            selectedIDs: normalizedSelectedIDs,
            deferPublishing: true
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
