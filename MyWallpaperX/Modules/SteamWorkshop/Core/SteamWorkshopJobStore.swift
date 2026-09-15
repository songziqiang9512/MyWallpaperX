//
//  SteamWorkshopJobStore.swift
//  MyWallpaperX
//

import Combine
import Foundation

// SK4.1：下载任务单一权威（job/attempt/queue ordinal/state/receipt 扩展位）。
//
// 合同：
// - 同一 workshopItem 至多一个非终态任务（去重）；同任务重试递增 attempt。
// - 状态迁移只经 reducer（纯函数），非法迁移被拒绝而非静默改写。
// - 持久化：版本化 JSON、原子替换（.atomic）、不含任何凭据；损坏文件改名
//   保留后以空状态继续；保存失败对外可见（不伪报已保存）。
// - 账号隔离：任务携带 accountSteamId；出队/取消可按账号过滤，其它账号的
//   任务不接管。
// - 执行器不在本类（SK4.2 接 helper downloader；SK4.1 仅 fake 验证）。

enum SteamDownloadJobState: String, Codable, Equatable {
    case queued
    case running
    case staged
    case failed
    case cancelled

    var isTerminal: Bool { self == .failed || self == .cancelled }
}

struct SteamDownloadJob: Codable, Identifiable, Equatable {
    let id: String
    let workshopItemId: String
    let title: String
    var state: SteamDownloadJobState
    var attempt: Int
    let queueOrdinal: Int
    let accountSteamId: String
    var stagingPath: String?
    var failureMessage: String?
    let createdAt: Date
    var updatedAt: Date

    var isActive: Bool { !isTerminal }
    var isTerminal: Bool { state.isTerminal }
}

enum SteamDownloadJobEvent: Equatable {
    case started
    case staged
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
        case .started:
            guard job.state == .queued || job.state == .failed else { return nil }
            next.state = .running
            next.attempt = job.attempt + 1
            next.failureMessage = nil
        case .staged:
            guard job.state == .running else { return nil }
            next.state = .staged
        case .failed(let message):
            guard job.state == .queued || job.state == .running else { return nil }
            next.state = .failed
            next.failureMessage = message
        case .cancelled:
            guard job.state == .queued || job.state == .running else { return nil }
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
    }

    static let persistenceVersion = 1

    @Published private(set) var jobs: [SteamDownloadJob] = []
    /// 最近一次持久化是否成功；失败时 UI 可提示（不伪报已保存）。
    private(set) var lastSaveSucceeded = true

    private var ordinal = 0
    private let persistenceURL: URL
    private let now: () -> Date

    init(persistenceURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        if let persistenceURL {
            self.persistenceURL = persistenceURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("MyWallpaperX/SteamJobs", isDirectory: true)
            self.persistenceURL = base.appendingPathComponent("jobs.json")
        }
        // 注入路径与默认路径统一确保父目录存在，否则原子写入会静默失败。
        try? FileManager.default.createDirectory(
            at: self.persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        loadPersistedJobs()
    }

    static func defaultPersistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MyWallpaperX/SteamJobs", isDirectory: true)
        return base.appendingPathComponent("jobs.json")
    }

    // MARK: - 查询

    func job(id: String) -> SteamDownloadJob? {
        jobs.first { $0.id == id }
    }

    func activeJob(forWorkshopItemId workshopItemId: String) -> SteamDownloadJob? {
        jobs.first { $0.workshopItemId == workshopItemId && $0.isActive }
    }

    func isQueuedOrRunning(workshopItemId: String) -> Bool {
        jobs.contains {
            $0.workshopItemId == workshopItemId && ($0.state == .queued || $0.state == .running)
        }
    }

    var activeJobs: [SteamDownloadJob] {
        jobs.filter(\.isActive)
    }

    var queuedCount: Int {
        jobs.filter { $0.state == .queued }.count
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
            failureMessage: nil,
            createdAt: stamp,
            updatedAt: stamp
        )
        jobs.append(job)
        save()
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
        jobs[index] = next
        save()
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
        let targets = jobs.filter { job in
            job.isActive && (accountSteamId == nil || job.accountSteamId == accountSteamId)
        }
        for job in targets {
            _ = apply(.cancelled, toID: job.id)
        }
        return targets.map(\.workshopItemId)
    }

    // MARK: - 持久化（版本化 + 原子替换 + 无凭据）

    private func save() {
        // 终态任务不持久化（历史/记录由下载库与 SK5.3 任务历史承担）。
        let persisted = jobs.filter(\.isActive)
        let state = PersistedState(version: Self.persistenceVersion, jobs: persisted)
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

    private func loadPersistedJobs() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        guard let data = try? Data(contentsOf: persistenceURL) else {
            quarantineCorruptedFile()
            return
        }
        guard let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              state.version == Self.persistenceVersion else {
            quarantineCorruptedFile()
            return
        }
        jobs = state.jobs
        ordinal = jobs.map(\.queueOrdinal).max() ?? 0
        // 重启后 running 意图不再可信：回退为 queued 等待重新调度（意图保留）。
        for index in jobs.indices where jobs[index].state == .running {
            jobs[index].state = .queued
        }
        lastSaveSucceeded = true
    }

    private func quarantineCorruptedFile() {
        let backup = persistenceURL.deletingLastPathComponent()
            .appendingPathComponent("jobs.corrupted-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: persistenceURL, to: backup)
        jobs = []
        lastSaveSucceeded = true
    }
}
