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
