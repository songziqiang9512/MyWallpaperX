import Foundation

extension SteamWorkshopService {
    /// A user action can precede the asynchronous catalog projection by one
    /// turn. Resolve that exact published record through its existing launch
    /// validator; ordinary queries and cells never use this action-time path.
    func libraryContentItemForExplicitPlayback(id: String) -> WallpaperContentItem? {
        guard let record = latestDownloadRecord(for: id) ?? installedRecordForLaunchReplay(itemID: id), record.id.utf8.elementsEqual(id.utf8),
              record.status == .ready, canLaunchDownloadRecord(record) else { return nil }
        let url = record.contentType == .video ? record.videoURL : record.folderURL
        return SteamWorkshopLibraryContentProjection.project(record: record,
            facts: Self.libraryContentFacts(record: record, available: true, localURL: url))
    }

    /// Low-frequency local publication projection. Transfer counters remain in
    /// the existing per-visible-card progress observer and never drive this scan.
    func libraryContentItems(from records: [SteamWorkshopDownloadRecord],
                             jobs: [SteamDownloadJob], account: String?,
                             reusing previous: [WallpaperContentItem],
                             previousRecords: [SteamWorkshopDownloadRecord],
                             refreshAvailabilityFor references: Set<WallpaperReference> = [],
                             refreshAll: Bool = false) async -> [WallpaperContentItem] {
        // Account publishers deliver their new value before the service's
        // deferred intent refresh. Foreign task snapshots cannot become mixed
        // page facts during that interval; untagged local records stay shared.
        let records = records.filter { record in
            guard let owner = record.intentAccountSteamID else { return true }
            guard let account, !account.isEmpty else { return false }
            return owner.utf8.elementsEqual(account.utf8)
        }
        let oldItems = Dictionary(previous.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        let oldRecords = Dictionary(previousRecords.map { (Self.libraryContentReference($0.id), $0) },
                                    uniquingKeysWith: { first, _ in first })
        let transfers = libraryContentTransfers(from: jobs, account: account)
        let inputs = records.map { record in
            let reference = Self.libraryContentReference(record.id)
            let reused = oldItems[reference].flatMap { item -> WallpaperContentLocalFacts? in
                guard !refreshAll, !references.contains(reference), let old = oldRecords[reference],
                      Self.sameLibraryContentResource(old, record) else { return nil }
                return Self.libraryContentFacts(record: record, available: item.publishedAvailability.isAvailable,
                                                localURL: item.locator.path.map { URL(fileURLWithPath: $0) })
            }
            // Scene's existing loader is actor-isolated. Keep that admission
            // owner intact and call it only for changed/explicitly refreshed
            // Scene publications, never for metadata or progress ticks.
            let sceneAvailable = reused == nil && record.contentType == .scene && record.status == .ready
                ? canLaunchDownloadRecord(record) : false
            return (record, reused, sceneAvailable)
        }
        let worker = Task.detached(priority: .utility) { [self] in
            var facts: [WallpaperReference: WallpaperContentLocalFacts] = [:]
            for (record, reuse, sceneAvailable) in inputs {
                guard !Task.isCancelled else { return facts }
                let reference = Self.libraryContentReference(record.id)
                if let reuse { facts[reference] = reuse; continue }
                var launchable = false
                var localURL = record.folderURL
                if record.status == .ready {
                    switch record.contentType {
                    case .video:
                        let video = record.videoURL
                        launchable = video != nil
                        localURL = video ?? record.exportedVideoURL ?? record.sourceVideoURL ?? record.folderURL
                    case .web:
                        launchable = record.isWebPlayableOrLaunchable && webLaunchEntryIsValid(for: record)
                    case .scene:
                        launchable = sceneAvailable
                    case .unknown: break
                    }
                }
                facts[reference] = Self.libraryContentFacts(record: record, available: launchable, localURL: localURL)
            }
            return facts
        }
        let facts = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return [] }
        return records.compactMap { record in
            let reference = Self.libraryContentReference(record.id)
            guard let local = facts[reference] else { return nil }
            let transfer = transfers[reference]
            return SteamWorkshopLibraryContentProjection.project(record: record, facts: local,
                acquisition: local.isPublishedLocally ? nil : transfer,
                update: local.isPublishedLocally ? transfer : nil)
        }
    }

    private func libraryContentTransfers(from jobs: [SteamDownloadJob], account: String?)
        -> [WallpaperReference: WallpaperContentTransferState] {
        guard let account, !account.isEmpty else { return [:] }
        let owned = jobs.filter { $0.accountSteamId.utf8.elementsEqual(account.utf8) }
        var grouped: [WallpaperReference: [SteamDownloadJob]] = [:]
        for job in owned { grouped[Self.libraryContentReference(job.workshopItemId), default: []].append(job) }
        return grouped.compactMapValues { values in
            let job = values.first(where: { $0.isActive })
                ?? values.filter { $0.state == .failed }.max { $0.updatedAt < $1.updatedAt }
            guard let job else { return nil }
            if job.state == .running,
               let progress = downloadProgressStore.snapshot(for: job.workshopItemId),
               progress.jobKey.utf8.elementsEqual(job.id.utf8), progress.attempt == job.attempt {
                return SteamWorkshopLibraryContentProjection.transfer(nil, progress: progress)
            }
            let phase: WallpaperContentTransferState.Phase
            switch job.state {
            case .queued: phase = .queued
            case .running: phase = .transferring
            case .staged, .committing: phase = .publishing
            case .failed: phase = .failed
            case .cancelled, .completed: return nil
            }
            return WallpaperContentTransferState(phase: phase, failureMessage: job.failureMessage,
                jobKey: job.id, attempt: job.attempt)
        }
    }

    nonisolated private static func libraryContentReference(_ id: String) -> WallpaperReference {
        WallpaperReference(provider: .steamWorkshop, sourceID: id)
    }

    nonisolated private static func libraryContentFacts(record: SteamWorkshopDownloadRecord,
                                                       available: Bool, localURL: URL?) -> WallpaperContentLocalFacts {
        let published = record.status == .ready
        let canDelete: Bool
        switch record.status {
        case .ready, .failed: canDelete = true
        case .queued, .downloading: canDelete = false
        }
        return WallpaperContentLocalFacts(isPublishedLocally: published, isAvailable: available,
            canPlay: available, canDelete: canDelete, localURL: localURL)
    }

    nonisolated private static func sameLibraryContentResource(_ lhs: SteamWorkshopDownloadRecord,
                                                              _ rhs: SteamWorkshopDownloadRecord) -> Bool {
        (lhs.status == .ready) == (rhs.status == .ready) && lhs.contentType == rhs.contentType
            && lhs.folderURL == rhs.folderURL && lhs.projectFileURL == rhs.projectFileURL
            && lhs.sourceVideoURL == rhs.sourceVideoURL && lhs.exportedVideoURL == rhs.exportedVideoURL
            && lhs.entryHTMLURL == rhs.entryHTMLURL && lhs.resolvedWebRootURL == rhs.resolvedWebRootURL
            && lhs.dependencyItemID == rhs.dependencyItemID && lhs.dependencyStatus == rhs.dependencyStatus
            && lhs.updatedAt == rhs.updatedAt
    }
}
