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
        filteredAndSortedMergedDownloads(from: downloadsWithFailedIntents(from: records))
    }

    /// refreshDisplayedDownloads 已提交合成记录，不在筛选阶段重复扫描任务意图。
    func filteredAndSortedMergedDownloads(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        let modeFiltered = records.filter { record in
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
        var failedHistoryItemIDs: Set<String>?
        let visible = modeFiltered.filter { record in
            if !downloadsShowsAdultContent, let item = record.browserItem,
               item.hasAdultContent || SteamWorkshopContentRatingSupport.hasAdultContent(tags: item.tags) {
                return false
            }
            switch record.status {
            case .ready, .failed:
                return true
            case .queued, .downloading:
                // 进行中意图 = 失败后的重试（同卡续显进度）；从未失败的新任务
                // 属弹窗队列，不进下载页。
                return hasFailedDownloadHistory(itemID: record.id, failedItemIDs: &failedHistoryItemIDs)
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
        guard synthesized.isEmpty == false else { return records }
        return (records + synthesized).sorted { $0.updatedAt > $1.updatedAt }
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
        // Filesystem statistics are prepared by the background library scan.
        // Never sort by rounded display strings or mutable modification dates.
        let locale = Locale(identifier: "en_US_POSIX")
        var foldedTitles: [String: String] = [:]
        return searched.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch downloadsSortMode {
            case .createdAt:
                switch (lhs.createdAt, rhs.createdAt) {
                case let (a?, b?) where a != b: comparison = a < b ? .orderedAscending : .orderedDescending
                case (.some, nil): return true
                case (nil, .some): return false
                default: comparison = downloadRecordStableComparison(lhs, rhs, foldedTitles: &foldedTitles, locale: locale)
                }
            case .title:
                comparison = downloadRecordStableComparison(lhs, rhs, foldedTitles: &foldedTitles, locale: locale)
            case .size:
                switch (lhs.sizeBytes, rhs.sizeBytes) {
                case let (a?, b?) where a != b: comparison = a < b ? .orderedAscending : .orderedDescending
                case (.some, nil): return true
                case (nil, .some): return false
                default: comparison = downloadRecordStableComparison(lhs, rhs, foldedTitles: &foldedTitles, locale: locale)
                }
            }
            return comparison == (downloadsSortAscending ? .orderedAscending : .orderedDescending)
        }
    }

    /// Fixed alphabetic collation and a stable identity make direction changes
    /// exact inverses for known values, including equal titles/sizes/dates.
    private func downloadRecordStableComparison(
        _ lhs: SteamWorkshopDownloadRecord,
        _ rhs: SteamWorkshopDownloadRecord,
        foldedTitles: inout [String: String],
        locale: Locale
    ) -> ComparisonResult {
        // Per-sort, demand-driven keys: unique date/size comparisons need no folding.
        func folded(_ title: String) -> String {
            if let cached = foldedTitles[title] { return cached }
            let value = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            foldedTitles[title] = value
            return value
        }
        let lhsTitle = folded(lhs.title)
        let rhsTitle = folded(rhs.title)
        let comparison = lhsTitle.compare(rhsTitle, options: [.numeric], locale: locale)
        if comparison != .orderedSame { return comparison }
        return lhs.id.compare(rhs.id, options: [.literal])
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
