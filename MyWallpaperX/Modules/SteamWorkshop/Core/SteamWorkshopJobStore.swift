//
//  SteamWorkshopJobStore.swift
//  MyWallpaperX
//

import Combine
import Foundation

// 下载任务单一权威：job/attempt/queue ordinal/state/receipt/提交阶段。
//
// 合同：
// - 同一 workshopItem 至多一个非终态任务（去重）；同任务重试递增 attempt。
// - 状态迁移只经 reducer（纯函数），非法迁移被拒绝而非静默改写。
// - 持久化：版本化 JSON、原子替换（.atomic）、不含任何凭据；损坏文件改名
//   保留后以空状态继续；保存失败对外可见（不伪报已保存）。
// - 账号隔离：任务携带 accountSteamId；出队/取消可按账号过滤，其它账号的
//   任务不接管。
// - 执行器在 Service；库内现有元数据指针是 ready 的唯一提交依据。

enum SteamDownloadJobState: String, Codable, Equatable {
    case queued
    case running
    case staged
    case failed
    case cancelled

    case committing
    case completed

    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

struct SteamDownloadJob: Codable, Identifiable, Equatable {
    let id: String
    let workshopItemId: String
    let title: String
    var state: SteamDownloadJobState
    var attempt: Int
    var queueOrdinal: Int
    let accountSteamId: String
    var stagingPath: String?
    var stagingManifestId: String? = nil
    var stagingLeaseIdentity: SteamWorkshopStagingLeaseIdentity? = nil
    var receipt: SteamWorkshopStagedReceipt? = nil
    var preparedCommit: SteamWorkshopLibraryCommit? = nil
    var failureMessage: String?
    let createdAt: Date
    var updatedAt: Date

    var isActive: Bool { !isTerminal }
    var isTerminal: Bool { state.isTerminal }
}

enum SteamDownloadHistoryOutcome: String, Codable, Equatable {
    case completed
    case failed
    case cancelled
}

/// A durable, terminal attempt owned by JobStore. `recordID` is only a reference
/// to the download library; history never decides whether an item is still ready.
struct SteamDownloadHistoryEntry: Codable, Identifiable, Equatable {
    let jobID: String
    let workshopItemId: String
    let title: String
    let accountSteamId: String
    let attempt: Int
    let outcome: SteamDownloadHistoryOutcome
    let failureMessage: String?
    let recordID: String?
    let terminalAt: Date

    var id: String { "\(jobID)-\(attempt)" }
}

enum SteamDownloadJobEvent: Equatable {
    case retryQueued(ordinal: Int)
    case resourcesReleased
    case started
    case resumed
    case stagingAllocated(
        path: String,
        manifestId: String,
        leaseIdentity: SteamWorkshopStagingLeaseIdentity
    )
    case recoveryInvalidated
    case staged(SteamWorkshopStagedReceipt)
    case committing(SteamWorkshopLibraryCommit)
    case completed
    case failed(String)
    case cancelled
}

/// 状态 reducer：非法迁移返回 nil。
enum SteamDownloadJobReducer {
    static func apply(
        _ event: SteamDownloadJobEvent,
        to job: SteamDownloadJob,
        now: Date
    ) -> SteamDownloadJob? {
        var next = job
        next.updatedAt = now
        switch event {
        case .retryQueued(let ordinal):
            guard job.state == .failed else { return nil }
            next.state = .queued
            next.queueOrdinal = ordinal
            next.failureMessage = nil
        case .resourcesReleased:
            guard job.state == .completed || job.state == .cancelled else { return nil }
            next.stagingPath = nil
            next.stagingManifestId = nil
            next.stagingLeaseIdentity = nil
            next.receipt = nil
            next.preparedCommit = nil
        case .started:
            guard job.state == .queued || job.state == .failed else { return nil }
            next.state = .running
            next.attempt = job.attempt + 1
            next.failureMessage = nil
            next.receipt = nil
            next.preparedCommit = nil
            // A queued retry may retain a complete descriptor-bound recovery
            // identity. A direct retry of an identityless failed job must start
            // a fresh helper lease instead of re-adopting its old lexical path.
            if job.state == .failed && job.stagingLeaseIdentity == nil {
                next.stagingPath = nil
                next.stagingManifestId = nil
            }
        case .resumed:
            guard job.state == .failed, let path = job.stagingPath, path.hasPrefix("/"),
                  let manifestId = job.stagingManifestId,
                  SteamWorkshopLibraryTransaction.validID(manifestId),
                  job.stagingLeaseIdentity != nil else { return nil }
            next.state = .running
            next.attempt = job.attempt + 1
            next.failureMessage = nil
            next.receipt = nil
            next.preparedCommit = nil
        case .stagingAllocated(let path, let manifestId, let leaseIdentity):
            guard job.state == .running, path.hasPrefix("/"), !path.utf8.contains(0),
                  SteamWorkshopLibraryTransaction.validID(manifestId),
                  (job.stagingPath == nil || job.stagingPath == path),
                  (job.stagingManifestId == nil || job.stagingManifestId == manifestId),
                  (job.stagingLeaseIdentity == nil || job.stagingLeaseIdentity == leaseIdentity)
            else { return nil }
            next.stagingPath = path
            next.stagingManifestId = manifestId
            next.stagingLeaseIdentity = leaseIdentity
        case .recoveryInvalidated:
            guard job.state == .running else { return nil }
            next.stagingPath = nil
            next.stagingManifestId = nil
            next.stagingLeaseIdentity = nil
        case .staged(let receipt):
            guard job.state == .running, receipt.jobId == "\(job.id)-\(job.attempt)",
                  receipt.workshopId == job.workshopItemId, receipt.accountSteamId == job.accountSteamId,
                  job.stagingManifestId == nil || job.stagingManifestId == receipt.manifestId,
                  let stagedIdentity = job.stagingLeaseIdentity,
                  stagedIdentity == receipt.stagingLeaseIdentity else { return nil }
            next.state = .staged
            next.receipt = receipt
            next.stagingPath = receipt.stagingURL.path
            next.stagingManifestId = receipt.manifestId
            next.stagingLeaseIdentity = receipt.stagingLeaseIdentity
        case .committing(let commit):
            guard job.state == .staged, commit.jobId == job.receipt?.jobId,
                  commit.attempt == job.attempt, commit.workshopId == job.workshopItemId,
                  commit.manifestId == job.receipt?.manifestId, commit.contentDigest == job.receipt?.contentDigest else { return nil }
            next.state = .committing
            next.preparedCommit = commit
        case .completed:
            guard job.state == .committing, job.preparedCommit != nil else { return nil }
            next.state = .completed
        case .failed(let message):
            guard !job.isTerminal else { return nil }
            next.state = .failed
            next.failureMessage = message
        case .cancelled:
            guard !job.isTerminal || job.state == .failed else { return nil }
            next.state = .cancelled
        }
        return next
    }
}

@MainActor
final class SteamDownloadJobStore: ObservableObject {
    struct PersistedState: Codable {
        var version: Int
        var jobs: [SteamDownloadJob]
        var history: [SteamDownloadHistoryEntry]

        private enum CodingKeys: String, CodingKey {
            case version
            case jobs
            case history
        }

        init(version: Int, jobs: [SteamDownloadJob], history: [SteamDownloadHistoryEntry] = []) {
            self.version = version
            self.jobs = jobs
            self.history = history
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            jobs = try container.decode([SteamDownloadJob].self, forKey: .jobs)
            history = try container.decodeIfPresent(
                [SteamDownloadHistoryEntry].self,
                forKey: .history
            ) ?? []
        }
    }

    static let persistenceVersion = 4
    static let historyLimit = 100
    static let historyRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    @Published private(set) var jobs: [SteamDownloadJob] = []
    @Published private(set) var history: [SteamDownloadHistoryEntry] = []
    /// 最近一次持久化是否成功；失败时 UI 可提示（不伪报已保存）。
    private(set) var lastSaveSucceeded = true

    private var ordinal = 0
    private let persistenceURL: URL
    /// Rollback boundary: the current owner never writes or quarantines an
    /// earlier schema filename. It may import the newest readable snapshot once
    /// when the v4 sidecar is absent, leaving older apps byte-for-byte sources.
    private let legacyImportURLs: [URL]
    private let now: () -> Date

    init(
        persistenceURL: URL? = nil,
        legacyImportURL: URL? = nil,
        olderLegacyImportURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        if let persistenceURL {
            self.persistenceURL = persistenceURL
            self.legacyImportURLs = [legacyImportURL, olderLegacyImportURL].compactMap { $0 }
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("MyWallpaperX/SteamJobs", isDirectory: true)
            self.persistenceURL = base.appendingPathComponent("jobs-v4.json")
            self.legacyImportURLs = [
                base.appendingPathComponent("jobs-v3.json"),
                base.appendingPathComponent("jobs.json"),
            ]
        }
        // 注入路径与默认路径统一确保父目录存在，否则原子写入会静默失败。
        try? FileManager.default.createDirectory(
            at: self.persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: self.persistenceURL.path) {
            loadPersistedJobs(from: self.persistenceURL, quarantineOnFailure: true)
        } else {
            for legacyImportURL in legacyImportURLs {
                guard FileManager.default.fileExists(atPath: legacyImportURL.path) else { continue }
                if loadPersistedJobs(from: legacyImportURL, quarantineOnFailure: false) {
                    // Import is copy-on-read. Persist only to the v4 sidecar and
                    // leave the old snapshot intact for whole-version rollback.
                    save(jobs, history: history)
                }
                // The newest existing predecessor is authoritative even when
                // corrupt. Falling through could replay stale intent from an
                // older filename that its owner had already superseded.
                break
            }
        }
    }

    static func defaultPersistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MyWallpaperX/SteamJobs", isDirectory: true)
        return base.appendingPathComponent("jobs-v4.json")
    }

    // MARK: - 查询

    func job(id: String) -> SteamDownloadJob? {
        jobs.first { $0.id == id }
    }

    func activeJob(forWorkshopItemId workshopItemId: String) -> SteamDownloadJob? {
        jobs.first { $0.workshopItemId == workshopItemId && $0.isActive }
    }

    func failedJob(forWorkshopItemId workshopItemId: String, accountSteamId: String) -> SteamDownloadJob? {
        jobs
            .filter {
                $0.workshopItemId == workshopItemId && $0.state == .failed
                    && $0.accountSteamId == accountSteamId
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func isQueuedOrRunning(workshopItemId: String) -> Bool {
        jobs.contains {
            $0.workshopItemId == workshopItemId && $0.isActive
        }
    }

    var activeJobs: [SteamDownloadJob] {
        jobs.filter(\.isActive)
    }

    var queuedCount: Int {
        jobs.filter { $0.state == .queued }.count
    }

    func history(forAccount accountSteamId: String?) -> [SteamDownloadHistoryEntry] {
        guard let accountSteamId, !accountSteamId.isEmpty else { return [] }
        return history.filter { $0.accountSteamId == accountSteamId }
    }

    // MARK: - 命令

    /// 入队（去重）：已有同 item 非终态任务则原样返回 (existing, false)。
    @discardableResult
    func enqueue(
        workshopItemId: String,
        title: String,
        accountSteamId: String,
        stagingPath: String? = nil
    ) -> (job: SteamDownloadJob, isNew: Bool) {
        if let existing = activeJob(forWorkshopItemId: workshopItemId) {
            return (existing, false)
        }
        ordinal += 1
        if let failed = failedJob(forWorkshopItemId: workshopItemId, accountSteamId: accountSteamId) {
            let queued = apply(.retryQueued(ordinal: ordinal), toID: failed.id)
            return (queued ?? failed, queued != nil)
        }
        let stamp = now()
        let job = SteamDownloadJob(
            id: UUID().uuidString,
            workshopItemId: workshopItemId,
            title: title,
            state: .queued,
            attempt: 0,
            queueOrdinal: ordinal,
            accountSteamId: accountSteamId,
            stagingPath: stagingPath,
            stagingManifestId: nil,
            failureMessage: nil,
            createdAt: stamp,
            updatedAt: stamp
        )
        let candidate = jobs + [job]
        save(candidate)
        guard lastSaveSucceeded else { return (job, false) }
        jobs = candidate
        history = normalizedHistory(history, now: stamp)
        return (job, true)
    }

    /// 出队：当前账号的最早入队 queued 任务（账号隔离）。
    func popNextQueued(forAccount accountSteamId: String?) -> SteamDownloadJob? {
        let candidate = jobs
            .filter { $0.state == .queued }
            .filter { accountSteamId == nil || $0.accountSteamId == accountSteamId }
            .min { $0.queueOrdinal < $1.queueOrdinal }
        guard let candidate else { return nil }
        return apply(.started, toID: candidate.id)
    }

    /// 事件应用：reducer 拒绝的迁移返回 nil；成功则替换并持久化。
    @discardableResult
    func apply(_ event: SteamDownloadJobEvent, toID jobID: String) -> SteamDownloadJob? {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              let next = SteamDownloadJobReducer.apply(event, to: jobs[index], now: now()) else {
            return nil
        }
        var candidate = jobs
        candidate[index] = next
        let candidateHistory = next.isTerminal && next.state != jobs[index].state
            ? upsertingHistoryEntry(for: next, into: history)
            : history
        save(candidate, history: candidateHistory)
        guard lastSaveSucceeded else { return nil }
        jobs = candidate
        history = normalizedHistory(candidateHistory, now: next.updatedAt)
        return next
    }

    @discardableResult
    func cancel(id: String) -> SteamDownloadJob? {
        apply(.cancelled, toID: id)
    }

    /// 取消全部非终态任务（登出/换号）；返回被取消的 workshopItemId 列表
    /// （供调用方清理对应 UI 投影）。
    @discardableResult
    func cancelAll(forAccount accountSteamId: String? = nil) -> [String] {
        let stamp = now()
        var cancelledIDs: [String] = []
        var cancelledJobs: [SteamDownloadJob] = []
        let candidate = jobs.map { job in
            guard job.isActive, accountSteamId == nil || job.accountSteamId == accountSteamId,
                  let next = SteamDownloadJobReducer.apply(.cancelled, to: job, now: stamp) else { return job }
            cancelledIDs.append(job.workshopItemId)
            cancelledJobs.append(next)
            return next
        }
        guard !cancelledIDs.isEmpty else { return [] }
        let candidateHistory = cancelledJobs.reduce(history) { partial, job in
            upsertingHistoryEntry(for: job, into: partial)
        }
        save(candidate, history: candidateHistory)
        guard lastSaveSucceeded else { return [] }
        jobs = candidate
        history = normalizedHistory(candidateHistory, now: stamp)
        return cancelledIDs
    }

    /// Removes only terminal history records. Jobs, queue intent and the download
    /// library remain untouched.
    @discardableResult
    func clearHistory(forAccount accountSteamId: String? = nil) -> Int {
        let candidate: [SteamDownloadHistoryEntry]
        if let accountSteamId {
            candidate = history.filter { $0.accountSteamId != accountSteamId }
        } else {
            candidate = []
        }
        let removedCount = history.count - candidate.count
        guard removedCount > 0 else { return 0 }
        save(jobs, history: candidate)
        guard lastSaveSucceeded else { return 0 }
        history = candidate
        return removedCount
    }

    /// Removes every terminal attempt of one job for the account (panel-side
    /// clearing only; the download library is untouched).
    @discardableResult
    func removeHistory(forJobID jobID: String, accountSteamId: String?) -> Int {
        guard let accountSteamId, !accountSteamId.isEmpty else { return 0 }
        let candidate = history.filter {
            $0.accountSteamId != accountSteamId || $0.jobID != jobID
        }
        let removedCount = history.count - candidate.count
        guard removedCount > 0 else { return 0 }
        save(jobs, history: candidate)
        guard lastSaveSucceeded else { return 0 }
        history = candidate
        return removedCount
    }

    /// Refresh the time-based retention boundary on a user-visible history read,
    /// without a timer or a second in-memory history owner.
    @discardableResult
    func pruneExpiredHistory() -> Int {
        let candidate = normalizedHistory(history, now: now())
        let removedCount = history.count - candidate.count
        guard removedCount > 0 else { return 0 }
        save(jobs, history: candidate)
        guard lastSaveSucceeded else { return 0 }
        history = candidate
        return removedCount
    }

    /// Caller supplies only available, published metadata pointers. Unpublished directories cannot settle a job.
    func reconcileInterruptedCommits(published: [String: SteamWorkshopLibraryCommit]) {
        for job in activeJobs where job.state == .staged || job.state == .committing {
            if job.state == .committing, let commit = published[job.workshopItemId],
               commit == job.preparedCommit, !commit.removed {
                _ = apply(.completed, toID: job.id)
            } else {
                _ = apply(.failed("上次入库未提交，旧版本保持不变；请重新发起下载。"), toID: job.id)
            }
        }
    }

    // MARK: - 持久化（版本化 + 原子替换 + 无凭据）

    private func save(
        _ candidate: [SteamDownloadJob],
        history candidateHistory: [SteamDownloadHistoryEntry]? = nil
    ) {
        // Failed jobs are durable user-visible intent. They are retried only by an
        // explicit user action and retain their staging identity for bounded cleanup.
        let persisted = candidate.filter { $0.isActive || $0.state == .failed || $0.stagingPath != nil || $0.preparedCommit != nil }
        let retainedHistory = normalizedHistory(candidateHistory ?? history, now: now())
        let state = PersistedState(
            version: Self.persistenceVersion,
            jobs: persisted,
            history: retainedHistory
        )
        guard let data = try? JSONEncoder().encode(state) else {
            lastSaveSucceeded = false
            return
        }
        do {
            try data.write(to: persistenceURL, options: .atomic)
            lastSaveSucceeded = true
        } catch {
            lastSaveSucceeded = false
        }
    }

    @discardableResult
    private func loadPersistedJobs(from sourceURL: URL, quarantineOnFailure: Bool) -> Bool {
        guard let data = try? Data(contentsOf: sourceURL) else {
            if quarantineOnFailure { quarantineCorruptedFile(at: sourceURL) }
            return false
        }
        guard let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              (1...Self.persistenceVersion).contains(state.version) else {
            if quarantineOnFailure { quarantineCorruptedFile(at: sourceURL) }
            return false
        }
        jobs = state.jobs
        let stamp = now()
        var restoredHistory = normalizedHistory(state.history, now: stamp)
        var recoveredFailureIDs: Set<String> = []
        ordinal = jobs.map(\.queueOrdinal).max() ?? 0
        // A partial is resumable only when path, manifest and descriptor identity
        // were durably captured as one unit. Older schemas had no identity; keep
        // their logical intent but never re-adopt the lexical staging name.
        for index in jobs.indices {
            let hasRecoveryField = jobs[index].stagingPath != nil
                || jobs[index].stagingManifestId != nil
                || jobs[index].stagingLeaseIdentity != nil
            let hasCompleteRecovery = jobs[index].stagingPath != nil
                && jobs[index].stagingManifestId != nil
                && jobs[index].stagingLeaseIdentity != nil
            if hasRecoveryField && !hasCompleteRecovery {
                jobs[index].stagingPath = nil
                jobs[index].stagingManifestId = nil
                jobs[index].stagingLeaseIdentity = nil
            }
        }
        for index in jobs.indices where jobs[index].state == .running {
            if jobs[index].stagingPath != nil && jobs[index].stagingManifestId != nil
                && jobs[index].stagingLeaseIdentity != nil {
                jobs[index].state = .failed
                jobs[index].failureMessage = "上次下载被中断；请重试以校验并恢复已完成的数据块。"
                jobs[index].updatedAt = stamp
                recoveredFailureIDs.insert(jobs[index].id)
            } else {
                jobs[index].state = .queued
                jobs[index].stagingPath = nil
                jobs[index].stagingManifestId = nil
                jobs[index].stagingLeaseIdentity = nil
            }
        }
        // v1/v2 had no history field. Preserve their retryable failures as one
        // terminal attempt, and make crash recovery idempotent by the same key.
        for job in jobs where job.state == .failed
            && (state.version < Self.persistenceVersion || recoveredFailureIDs.contains(job.id)) {
            restoredHistory = upsertingHistoryEntry(for: job, into: restoredHistory)
        }
        history = normalizedHistory(restoredHistory, now: stamp)

        if state.version != Self.persistenceVersion || history != state.history || jobs != state.jobs {
            save(jobs, history: history)
        } else {
            lastSaveSucceeded = true
        }
        return true
    }

    private func upsertingHistoryEntry(
        for job: SteamDownloadJob,
        into candidate: [SteamDownloadHistoryEntry]
    ) -> [SteamDownloadHistoryEntry] {
        guard let entry = historyEntry(for: job) else { return candidate }
        return candidate.filter { $0.id != entry.id } + [entry]
    }

    private func historyEntry(for job: SteamDownloadJob) -> SteamDownloadHistoryEntry? {
        let outcome: SteamDownloadHistoryOutcome
        switch job.state {
        case .completed:
            outcome = .completed
        case .failed:
            outcome = .failed
        case .cancelled:
            outcome = .cancelled
        case .queued, .running, .staged, .committing:
            return nil
        }
        return SteamDownloadHistoryEntry(
            jobID: job.id,
            workshopItemId: job.workshopItemId,
            title: job.title,
            accountSteamId: job.accountSteamId,
            attempt: job.attempt,
            outcome: outcome,
            failureMessage: job.failureMessage,
            recordID: outcome == .completed ? job.workshopItemId : nil,
            terminalAt: job.updatedAt
        )
    }

    private func normalizedHistory(
        _ candidate: [SteamDownloadHistoryEntry],
        now: Date
    ) -> [SteamDownloadHistoryEntry] {
        let cutoff = now.addingTimeInterval(-Self.historyRetentionInterval)
        var entryByID: [String: SteamDownloadHistoryEntry] = [:]
        for entry in candidate where entry.terminalAt >= cutoff {
            if let existing = entryByID[entry.id], existing.terminalAt >= entry.terminalAt {
                continue
            }
            entryByID[entry.id] = entry
        }
        return Array(entryByID.values
            .sorted { lhs, rhs in
                if lhs.terminalAt != rhs.terminalAt { return lhs.terminalAt > rhs.terminalAt }
                return lhs.id < rhs.id
            }
            .prefix(Self.historyLimit))
    }

    private func quarantineCorruptedFile(at sourceURL: URL) {
        let backup = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("jobs.corrupted-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: sourceURL, to: backup)
        jobs = []
        history = []
        lastSaveSucceeded = true
    }
}
