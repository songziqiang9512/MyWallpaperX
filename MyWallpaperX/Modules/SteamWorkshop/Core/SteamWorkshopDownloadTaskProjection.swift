import Foundation

/// SK5.2 current-task projection. JobStore remains the only queue/state owner;
/// this type only orders local task facts. Reading them never requires login.
enum SteamWorkshopDownloadTaskProjection {
    static func currentJobs(
        from jobs: [SteamDownloadJob]
    ) -> [SteamDownloadJob] {
        return jobs
            .filter { !$0.isTerminal }
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.state)
                let rhsPriority = priority(for: rhs.state)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhs.queueOrdinal != rhs.queueOrdinal { return lhs.queueOrdinal < rhs.queueOrdinal }
                return lhs.id < rhs.id
            }
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

/// Selects one display row per job; all durable attempts remain in JobStore.
enum SteamWorkshopDownloadHistoryProjection {
    static func latestEntries(
        from history: [SteamDownloadHistoryEntry]
    ) -> [SteamDownloadHistoryEntry] {
        var latestByJobID: [String: SteamDownloadHistoryEntry] = [:]
        for entry in history {
            if let latest = latestByJobID[entry.jobID] {
                guard entry.terminalAt > latest.terminalAt
                    || (entry.terminalAt == latest.terminalAt && entry.attempt > latest.attempt) else { continue }
            }
            latestByJobID[entry.jobID] = entry
        }
        return latestByJobID.values.sorted { lhs, rhs in
            if lhs.terminalAt != rhs.terminalAt { return lhs.terminalAt > rhs.terminalAt }
            return lhs.jobID < rhs.jobID
        }
    }
}
