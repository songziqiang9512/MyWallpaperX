import Foundation

/// SK5.2 current-task projection. JobStore remains the only queue/state owner;
/// this type only filters and orders a stable UI snapshot for the signed-in account.
enum SteamWorkshopDownloadTaskProjection {
    static func currentJobs(
        from jobs: [SteamDownloadJob],
        accountSteamID: String?
    ) -> [SteamDownloadJob] {
        guard let accountSteamID, !accountSteamID.isEmpty else { return [] }
        return jobs
            .filter {
                $0.accountSteamId == accountSteamID
                    && $0.state != .completed
                    && $0.state != .cancelled
            }
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.state)
                let rhsPriority = priority(for: rhs.state)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhs.queueOrdinal != rhs.queueOrdinal { return lhs.queueOrdinal < rhs.queueOrdinal }
                return lhs.id < rhs.id
            }
    }

    static func unfinishedCount(
        in jobs: [SteamDownloadJob],
        accountSteamID: String?
    ) -> Int {
        currentJobs(from: jobs, accountSteamID: accountSteamID).count
    }

    static func jobKey(for job: SteamDownloadJob) -> String? {
        guard job.attempt > 0 else { return nil }
        return "\(job.id)-\(job.attempt)"
    }

    static func isCancellable(_ job: SteamDownloadJob) -> Bool {
        job.state == .queued || job.state == .running
    }

    private static func priority(for state: SteamDownloadJobState) -> Int {
        switch state {
        case .running, .staged, .committing:
            return 0
        case .failed:
            return 1
        case .queued:
            return 2
        case .completed, .cancelled:
            return 3
        }
    }
}

struct SteamWorkshopDownloadHistorySummary: Identifiable, Equatable {
    let jobID: String
    let workshopItemID: String
    let title: String
    let latestOutcome: SteamDownloadHistoryOutcome
    let latestTerminalAt: Date
    let recordID: String?
    let attempts: [SteamDownloadHistoryEntry]

    var id: String { jobID }
}

/// SK5.3 read projection. Attempts remain durable JobStore records; grouping is
/// recomputed from the bounded history snapshot and never becomes a second owner.
enum SteamWorkshopDownloadHistoryProjection {
    static func summaries(
        from history: [SteamDownloadHistoryEntry],
        accountSteamID: String?
    ) -> [SteamWorkshopDownloadHistorySummary] {
        guard let accountSteamID, !accountSteamID.isEmpty else { return [] }
        return Dictionary(grouping: history.filter { $0.accountSteamId == accountSteamID }, by: \.jobID)
            .compactMap { jobID, attempts -> SteamWorkshopDownloadHistorySummary? in
                let orderedAttempts = attempts.sorted { lhs, rhs in
                    if lhs.terminalAt != rhs.terminalAt { return lhs.terminalAt > rhs.terminalAt }
                    return lhs.attempt > rhs.attempt
                }
                guard let latest = orderedAttempts.first else { return nil }
                return SteamWorkshopDownloadHistorySummary(
                    jobID: jobID,
                    workshopItemID: latest.workshopItemId,
                    title: latest.title,
                    latestOutcome: latest.outcome,
                    latestTerminalAt: latest.terminalAt,
                    recordID: latest.recordID,
                    attempts: orderedAttempts
                )
            }
            .sorted { lhs, rhs in
                if lhs.latestTerminalAt != rhs.latestTerminalAt {
                    return lhs.latestTerminalAt > rhs.latestTerminalAt
                }
                return lhs.jobID < rhs.jobID
            }
    }
}
