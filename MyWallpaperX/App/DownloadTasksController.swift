import AppKit
import Combine

/// One App-lifetime consumer of terminal receipts and one read projection for
/// the native panel. All execution, progress and publication stay in sources.
@MainActor final class DownloadTasksController {
    private let steam: SteamWorkshopService
    private let pixabay: PixabayService
    private let images: OnlineImageLibrary
    private let history: DownloadHistoryStore?
    private var historyError: String?
    private var subscriptions = Set<AnyCancellable>()
    private let changed = PassthroughSubject<Void, Never>()
    private let localThumbnails = SILThumbnailProvider()

    var changes: AnyPublisher<Void, Never> { changed.eraseToAnyPublisher() }
    var unfinishedCount: Int {
        steam.downloadJobStore.jobs.lazy.filter { !$0.isTerminal }.count + pixabay.activeDownloadCount + images.activeDownloadCount
    }

    init(steam: SteamWorkshopService, pixabay: PixabayService, images: OnlineImageLibrary,
         historyURL: URL? = nil) {
        self.steam = steam; self.pixabay = pixabay; self.images = images
        do { history = try DownloadHistoryStore(persistenceURL: historyURL) }
        catch { history = nil; historyError = "下载历史无法读取：" + error.localizedDescription }
        Publishers.Merge(pixabay.downloadTerminals, images.downloadTerminals).sink { [weak self] receipt in
            guard let self, let history else { return }
            do { try history.record(receipt); historyError = nil }
            catch { historyError = "下载已结算，但历史无法保存：" + error.localizedDescription; changed.send() }
        }.store(in: &subscriptions)
        let publishers: [AnyPublisher<Void, Never>] = [
            steam.$downloads.map { _ in () }.eraseToAnyPublisher(),
            steam.downloadJobStore.$jobs.map { _ in () }.eraseToAnyPublisher(),
            steam.downloadJobStore.$history.map { _ in () }.eraseToAnyPublisher(),
            steam.steamAuth.$phase.map { _ in () }.eraseToAnyPublisher(),
            steam.steamAuth.$steamId.map { _ in () }.eraseToAnyPublisher(),
            pixabay.downloadTasksDidChange.eraseToAnyPublisher(),
            pixabay.$downloadedContent.map { _ in () }.eraseToAnyPublisher(),
            images.downloadTasksDidChange.eraseToAnyPublisher(),
            images.$snapshot.map { _ in () }.eraseToAnyPublisher(),
            images.$wallhavenCredentialRevision.map { _ in () }.eraseToAnyPublisher(),
            images.$pixivSession.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers).receive(on: RunLoop.main).sink { [weak self] in
            self?.sourceChanged()
        }.store(in: &subscriptions)
        sourceChanged()
    }

    func makePopoverController() -> DownloadTasksPopoverController {
        DownloadTasksPopoverController(snapshot: { [weak self] in self?.snapshot() ?? .init() }, changes: changes,
            bindings: .init(perform: { [weak self] row, action in self?.perform(row, action: action) },
                loadThumbnail: { [weak self] row, receive in self?.loadThumbnail(row, receive: receive) },
                observeProgress: { [weak self] row, receive in self?.observeProgress(row, receive: receive) }),
            retryAllFailed: { [weak self] rows in
                guard let self else { return }
                for row in rows { perform(row, action: .retry) }
            }, clearHistory: { [weak self] in self?.clearHistory() })
    }

    private func sourceChanged() {
        if let history, pixabay.downloadedContent.status.hasSuccessfulScan, images.snapshot.status.hasSuccessfulScan {
            do {
                try history.importExistingSuccesses {
                    pixabay.downloadedContent.entries.map { entry in
                        .init(id: .init(reference: .init(provider: .pixabay, sourceID: String(entry.id)), attemptID: "existing-local"),
                            title: entry.displayTitle, outcome: .existingLocal, recordedAt: entry.creationDate)
                    } + images.snapshot.records.map { record in
                        .init(id: .init(reference: record.id.reference, attemptID: "existing-local"), title: record.title,
                              outcome: .existingLocal, recordedAt: record.firstDownloadedAt)
                    }
                }
            } catch { historyError = "旧下载历史无法保存：" + error.localizedDescription }
        }
        changed.send()
    }

    private func snapshot() -> DownloadTaskSnapshot {
        let jobs = SteamWorkshopDownloadTaskProjection.currentJobs(from: steam.downloadJobStore.jobs)
        let pixabayTasks = pixabay.downloadActivities, imageTasks = images.downloadActivities
        let steamRecords = Dictionary(steam.downloads.map { (WallpaperReference(provider: .steamWorkshop, sourceID: $0.id), $0) },
            uniquingKeysWith: { first, _ in first })
        let pixabayRecords = Dictionary(pixabay.downloadedContent.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let imageRecords = Dictionary(images.snapshot.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = jobs.map { job -> DownloadTaskRow in
            let reference = WallpaperReference(provider: .steamWorkshop, sourceID: job.workshopItemId)
            let phase = steamPhase(job)
            var actions: Set<DownloadTaskAction> = []
            if job.accountSteamId == steam.steamAuth.steamId {
                if SteamWorkshopDownloadTaskProjection.isCancellable(job) { actions.insert(.cancel) }
                if phase == .paused { actions.insert(.resume) }
                else if job.state == .running { actions.insert(.pause) }
                else if job.state == .queued { actions.insert(.promote) }
            }
            let url = steamPreviewURL(id: job.workshopItemId, publishedPreviewURL: steamRecords[reference]?.previewURL)
            let progressKey = SteamWorkshopDownloadTaskProjection.jobKey(for: job)
            return .init(id: .init(reference: reference,
                attemptID: progressKey ?? "\(job.id)-0"), title: job.title, phase: phase,
                recordedAt: job.createdAt, progress: progressKey.flatMap { steamProgress(id: job.workshopItemId, attempt: $0) },
                thumbnailKey: url.map { $0.absoluteString + ":\(steam.previewReloadToken)" }, actions: actions)
        }
        current += pixabayTasks.map { task in
            .init(id: .init(reference: .init(provider: .pixabay, sourceID: String(task.itemID)), attemptID: task.attemptID.uuidString),
                title: task.title, phase: task.phase, recordedAt: task.createdAt,
                progress: .init(phase: task.phase, fraction: pixabay.downloadProgressByID[task.itemID]),
                thumbnailKey: task.previewURL?.absoluteString, actions: [.cancel])
        }
        current += imageTasks.map { task in
            .init(id: .init(reference: task.assetID.reference, attemptID: task.attemptID.uuidString), title: task.title,
                phase: task.phase, recordedAt: task.createdAt,
                progress: .init(phase: task.phase, fraction: images.progress[task.assetID]),
                thumbnailKey: task.previewURL.map { $0.absoluteString + images.requestScope(task.assetID.source) }, actions: [.cancel])
        }
        let activeReferences = Set(current.map { $0.id.reference })
        var terminal = SteamWorkshopDownloadHistoryProjection.summaries(from: steam.downloadJobStore.history).map { summary -> DownloadTaskRow in
            let reference = WallpaperReference(provider: .steamWorkshop, sourceID: summary.workshopItemID)
            let phase: DownloadTaskPhase = summary.latestOutcome == .completed ? .completed
                : summary.latestOutcome == .failed ? .failed : .cancelled
            var actions: Set<DownloadTaskAction> = [.removeHistory]
            if summary.accountSteamID == steam.steamAuth.steamId, !activeReferences.contains(reference) {
                if phase == .failed || phase == .cancelled || steamRecords[reference]?.status != .ready { actions.insert(.retry) }
            }
            if steamRecords[reference]?.status == .ready { actions.insert(.revealFile) }
            return .init(id: .init(reference: reference,
                attemptID: "\(summary.jobID)-\(summary.latestAttempt)"), title: summary.title, phase: phase,
                statusText: summary.attempts.first?.failureMessage, recordedAt: summary.latestTerminalAt,
                thumbnailKey: steamPreviewURL(id: summary.workshopItemID, publishedPreviewURL: steamRecords[reference]?.previewURL)
                    .map { $0.absoluteString + ":\(steam.previewReloadToken)" }, actions: actions)
        }
        terminal += (history?.entries ?? []).map { receipt in
            let reference = receipt.id.reference
            let localKey: String?
            let available: Bool
            if reference.provider == .pixabay, let id = Int(reference.sourceID), let record = pixabayRecords[id] {
                available = record.isAvailable; localKey = record.thumbnailSourceKey ?? record.localURL.absoluteString
            } else if let id = OnlineImageAssetID(reference: reference), let record = imageRecords[id] {
                available = !images.snapshot.unavailable.contains(id); localKey = record.revision.uuidString
            } else { available = false; localKey = nil }
            var actions: Set<DownloadTaskAction> = [.removeHistory]
            if available { actions.insert(.revealFile) }
            else if !activeReferences.contains(reference) { actions.insert(.retry) }
            return .init(id: receipt.id, title: receipt.title, phase: receipt.outcome.phase,
                statusText: receipt.outcome == .existingLocal ? "本地已有" : receipt.failureMessage,
                recordedAt: receipt.recordedAt, thumbnailKey: available ? localKey : nil, actions: actions)
        }
        var value = DownloadTaskProjection.snapshot(current: current, history: terminal)
        value.notice = historyError
        return value
    }

    private func perform(_ row: DownloadTaskRow, action: DownloadTaskAction) {
        let reference = row.id.reference
        if reference.provider == .steamWorkshop {
            let job = steam.downloadJobStore.jobs.first { "\($0.id)-\($0.attempt)" == row.id.attemptID }
            let terminal = steam.downloadJobStore.history.first { $0.id == row.id.attemptID }
            if action == .removeHistory, let terminal {
                if let job, job.state == .failed, job.accountSteamId == steam.steamAuth.steamId,
                   !steam.discardFailedDownload(jobID: job.id) { return }
                steam.downloadJobStore.removeHistory(forJobID: terminal.jobID, accountSteamId: terminal.accountSteamId)
            } else if action == .revealFile {
                if let record = steam.downloadRecord(for: reference.sourceID) { steam.revealItem(record) }
            } else {
                guard let account = job?.accountSteamId ?? terminal?.accountSteamId,
                      account == steam.steamAuth.steamId else { return }
                switch action {
                case .retry: steam.downloadWorkshopItem(id: reference.sourceID, pageTitle: row.title)
                case .cancel: if let job, SteamWorkshopDownloadTaskProjection.isCancellable(job) { steam.cancelDownloadImmediately(itemID: reference.sourceID, showFeedback: false) }
                case .pause: if job != nil { steam.pauseDownload(itemID: reference.sourceID) }
                case .resume: if job != nil { steam.resumeDownload(itemID: reference.sourceID) }
                case .promote: if job != nil { steam.promoteQueuedDownload(itemID: reference.sourceID) }
                default: break
                }
            }
        } else if action == .removeHistory {
            do { try history?.remove(row.id); if history != nil { historyError = nil } }
            catch { historyError = "下载历史无法清除：" + error.localizedDescription }
        } else if reference.provider == .pixabay, let id = Int(reference.sourceID) {
            switch action {
            case .retry: pixabay.retryDownload(id: id)
            case .cancel: if let attempt = UUID(uuidString: row.id.attemptID) { pixabay.cancelDownload(id: id, attemptID: attempt) }
            case .revealFile:
                if let record = pixabay.downloadedContent.entries.first(where: { $0.id == id && $0.isAvailable }) {
                    FinderRevealCoordinator.shared.reveal([record.localURL])
                }
            default: break
            }
        } else if let id = OnlineImageAssetID(reference: reference) {
            switch action {
            case .retry: images.retryDownload(reference, title: row.title)
            case .cancel: if let attempt = UUID(uuidString: row.id.attemptID) { images.cancel(id, attemptID: attempt) }
            case .revealFile:
                if let record = images.record(for: reference), !images.snapshot.unavailable.contains(id), let url = images.localURL(for: record) {
                    FinderRevealCoordinator.shared.reveal([url])
                }
            default: break
            }
        }
        changed.send()
    }

    private func clearHistory() {
        do { try history?.clear(); if history != nil { historyError = nil } }
        catch { historyError = "下载历史无法清除：" + error.localizedDescription }
        steam.downloadJobStore.clearHistory()
        changed.send()
    }

    private func steamPhase(_ job: SteamDownloadJob) -> DownloadTaskPhase {
        switch job.state {
        case .queued: return steam.isDownloadPaused(itemID: job.workshopItemId) ? .paused : .queued
        case .running: return .preparing
        case .staged, .committing: return .saving
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    private func steamProgress(id: String, attempt: String) -> DownloadTaskProgress? {
        guard let snapshot = steam.downloadProgressStore.snapshot(for: id), snapshot.jobKey == attempt else { return nil }
        let phase: DownloadTaskPhase
        switch snapshot.phase {
        case .connecting, .preparing: phase = .preparing
        case .transferring: phase = .transferring
        case .validating, .saving: phase = .saving
        case .waiting: phase = .queued
        case .failed: phase = .failed
        }
        return .init(phase: phase, statusText: snapshot.statusText(compact: true), fraction: snapshot.fraction,
                     verifiedBytes: snapshot.verifiedBytes, totalBytes: snapshot.totalBytes, sequence: snapshot.sequence)
    }

    private func observeProgress(_ row: DownloadTaskRow, receive: @escaping (DownloadTaskProgress) -> Void) -> (() -> Void)? {
        let reference = row.id.reference
        if reference.provider == .steamWorkshop {
            let store = steam.downloadProgressStore
            let id = store.addObserver(for: reference.sourceID, owner: self) { [weak self] _ in
                if let progress = self?.steamProgress(id: reference.sourceID, attempt: row.id.attemptID) { receive(progress) }
            }
            return { store.removeObserver(id) }
        }
        let subscription: AnyCancellable
        if reference.provider == .pixabay, let id = Int(reference.sourceID) {
            subscription = pixabay.$downloadProgressByID.compactMap { $0[id] }.removeDuplicates().sink { [weak pixabay] fraction in
                guard let activity = pixabay?.downloadActivity(for: id), activity.attemptID.uuidString == row.id.attemptID else { return }
                receive(.init(phase: activity.phase, fraction: fraction))
            }
        } else if let id = OnlineImageAssetID(reference: reference) {
            subscription = images.$progress.compactMap { $0[id] }.removeDuplicates().sink { [weak images] fraction in
                guard let activity = images?.downloadActivity(for: id), activity.attemptID.uuidString == row.id.attemptID else { return }
                receive(.init(phase: activity.phase, fraction: fraction))
            }
        } else { return nil }
        return { subscription.cancel() }
    }

    private func steamPreviewURL(id: String, publishedPreviewURL: URL?) -> URL? {
        publishedPreviewURL ?? steam.browserItemForDownload(id: id)?.previewImageURL
    }

    private func loadThumbnail(_ row: DownloadTaskRow, receive: @escaping (NSImage?) -> Void) -> (() -> Void)? {
        let reference = row.id.reference
        if reference.provider == .steamWorkshop,
           let url = steamPreviewURL(id: reference.sourceID, publishedPreviewURL: steam.latestDownloadRecord(for: reference.sourceID)?.previewURL) {
            let cancellation = SteamWorkshopPreviewLoadCancellation()
            steamWorkshopLoadPreviewImage(from: url, cancellation: cancellation, completion: receive)
            return { cancellation.cancel() }
        }
        if reference.provider == .pixabay, let id = Int(reference.sourceID) {
            if let entry = pixabay.downloadedContent.entries.first(where: { $0.id == id && $0.isAvailable }) {
                let cancellation = ThumbnailCacheRequestCancellation()
                PixabayDownloadedThumbnailStore.loadThumbnail(entry, priority: .visible, cancellation: cancellation) { _, image in receive(image) }
                return { cancellation.cancel() }
            }
            if let url = pixabay.downloadActivity(for: id)?.previewURL { return loadRemoteThumbnail(.init(url: url), receive: receive) }
        } else if let id = OnlineImageAssetID(reference: reference) {
            if let record = images.record(for: reference), !images.snapshot.unavailable.contains(id), let url = images.localURL(for: record) {
                let cancellation = ThumbnailCacheRequestCancellation()
                localThumbnails.load(path: url.path, cancellation: cancellation) { result in
                    if case .image(let image) = result { receive(image) } else { receive(nil) }
                }
                return { cancellation.cancel() }
            }
            if let url = images.downloadActivity(for: id)?.previewURL {
                return loadRemoteThumbnail(images.thumbnailRequest(url: url, source: id.source), receive: receive)
            }
        }
        return nil
    }

    private func loadRemoteThumbnail(_ request: OnlineImageThumbnailRequest, receive: @escaping (NSImage?) -> Void) -> (() -> Void)? {
        let cache = OnlineImageThumbnailCache.shared
        if let ready = cache.readyImage(for: request, maxPixelSize: 128) { receive(ready); return nil }
        let task = Task {
            let image = await cache.image(for: request, maxPixelSize: 128, priority: .visible)
            if !Task.isCancelled { receive(image) }
        }
        return { task.cancel() }
    }
}
