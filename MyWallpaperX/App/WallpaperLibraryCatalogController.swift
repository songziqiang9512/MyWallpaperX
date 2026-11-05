import Combine
import Foundation

/// One App-owned live value projection. Original providers retain files,
/// availability checks, commands and transfer observers. Queries read `catalog`.
/// Trusted download ↔ Video UUID receipts await the import publisher and are
/// never guessed from a path or title.
@MainActor final class WallpaperLibraryCatalogController: ObservableObject {
    @Published private(set) var catalog = WallpaperLibraryCatalog()
    let visibleLocalFactsRefreshed = PassthroughSubject<Void, Never>()
    private let manager: WallpaperManager
    private let images: SILService
    private let steam: SteamWorkshopService
    private let pixabay: PixabayService
    private let onlineImages = OnlineImageLibrary.shared
    private var subscriptions = Set<AnyCancellable>()
    private var videoTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var steamTask: Task<Void, Never>?
    private var revisions: [WallpaperProvider: UInt64] = [:]
    private var publishedRevisions: [WallpaperProvider: UInt64] = [:]
    private var refreshVideos = false
    private var refreshImages = false
    private var refreshSteam = false
    private var steamRefreshReferences = Set<WallpaperReference>()
    private var projectedSteamRecords: [SteamWorkshopDownloadRecord] = []
    private var latestSteamJobs: [SteamDownloadJob] = []
    private var visibleReferences: [UUID: Set<WallpaperReference>] = [:]
    private var visibleAvailabilityTask: Task<Void, Never>?
    private var visibleAvailabilityGeneration = UUID()
    private var downloadHides: [WallpaperReference: Int64] = [:]
    private var downloadHideRevision: Int64 = 0

    init(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService) {
        self.manager = manager
        self.images = images
        self.steam = steam
        self.pixabay = pixabay
        manager.$wallpapers.combineLatest(manager.$didFinishInitialIndexLoad).removeDuplicates { lhs, rhs in
            lhs.1 == rhs.1 && lhs.0 == rhs.0 && zip(lhs.0, rhs.0).allSatisfy { $0.id.utf8.elementsEqual($1.id.utf8) }
        }.sink { [weak self] values, loaded in
            self?.replaceVideos(values, loaded: loaded)
        }.store(in: &subscriptions)
        images.$wallpapers.removeDuplicates { lhs, rhs in
            lhs == rhs && zip(lhs, rhs).allSatisfy { $0.id.utf8.elementsEqual($1.id.utf8) }
        }.sink { [weak self] values in
            self?.replaceImages(values)
        }.store(in: &subscriptions)
        steam.$downloads.combineLatest(steam.steamAuth.$steamId)
            .sink { [weak self] records, account in
                self?.updateDownloadsExclusions(records, account: account)
            }.store(in: &subscriptions)
        // Job history also changes independently of jobs (clear/prune/remove).
        // Defer willSet delivery before the original fact owner reads history.
        steam.downloadJobStore.$history.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.updateDownloadsExclusions(self.steam.downloads, account: self.steam.steamAuth.steamId)
        }.store(in: &subscriptions)
        pixabay.$downloadedContent.removeDuplicates {
            $0.entries == $1.entries && ($0.revision == 0) == ($1.revision == 0) && $0.status == $1.status
        }.sink { [weak self] snapshot in
            self?.replaceOnline(snapshot)
        }.store(in: &subscriptions)
        onlineImages.$snapshot.removeDuplicates().sink { [weak self] snapshot in
            self?.replaceOnlineImages(snapshot)
        }.store(in: &subscriptions)
        Publishers.CombineLatest4(steam.$downloads, steam.downloadJobStore.$jobs, steam.steamAuth.$steamId, steam.$hasCompletedInstalledLibraryLoad)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
                    && zip(lhs.0, rhs.0).allSatisfy { $0.id.utf8.elementsEqual($1.id.utf8) }
                    && zip(lhs.1, rhs.1).allSatisfy { $0.workshopItemId.utf8.elementsEqual($1.workshopItemId.utf8) }
            }
            .sink { [weak self] records, jobs, account, loaded in
                self?.replaceSteam(records, jobs: jobs, account: account, loaded: loaded)
            }.store(in: &subscriptions)
    }

    deinit { videoTask?.cancel(); imageTask?.cancel(); steamTask?.cancel(); visibleAvailabilityTask?.cancel() }

    func hideDownloads(_ references: Set<WallpaperReference>) {
        guard !references.isEmpty else { return }
        downloadHideRevision += 1
        for reference in references { downloadHides[reference] = downloadHideRevision }
        publishDownloadHides()
    }

    func downloadHideRevisions(for references: Set<WallpaperReference>, canonical: [WallpaperReference: WallpaperReference]) -> [WallpaperReference: Int64] {
        var revisions: [WallpaperReference: Int64] = [:]
        for (reference, revision) in downloadHides {
            let key = canonical[reference]!
            revisions[key] = max(revisions[key] ?? revision, revision)
        }
        var result: [WallpaperReference: Int64] = [:]
        for reference in references { result[reference] = revisions[canonical[reference]!] }
        return result
    }

    func restoreDownload(_ reference: WallpaperReference, expectedRevision: Int64?, canonical: [WallpaperReference: WallpaperReference]) {
        let current = downloadHideRevisions(for: [reference], canonical: canonical)[reference]
        guard let current, current == expectedRevision else { return }
        downloadHides = downloadHides.filter { canonical[$0.key] != canonical[reference] }
        publishDownloadHides()
    }

    private func publishDownloadHides() {
        var next = catalog
        next.sessionHiddenDownloadReferences = Set(downloadHides.keys)
        next.revision &+= 1
        catalog = next
    }

    /// Visibility is a consumer lease, not another source index. One cadence
    /// replaces the retired Video/SIL grids' visible-file probes. Hidden pages
    /// and closed pickers release their leases; ordinary queries never stat files.
    func setVisibleReferences(_ references: Set<WallpaperReference>, sourceToken: UUID) {
        let local = references.filter { $0.provider == .videoLibrary || $0.provider == .staticImageLibrary }
        guard (visibleReferences[sourceToken] ?? []) != local else { return }
        let previous = Set(visibleReferences.values.flatMap { $0 })
        if local.isEmpty { visibleReferences.removeValue(forKey: sourceToken) }
        else { visibleReferences[sourceToken] = local }
        guard previous != Set(visibleReferences.values.flatMap({ $0 })) else { return }
        visibleAvailabilityGeneration = UUID()
        if visibleReferences.isEmpty { visibleAvailabilityTask?.cancel() }
        else { startVisibleAvailabilityIfNeeded() }
    }

    private func startVisibleAvailabilityIfNeeded() {
        // A cancelled stat on a slow/removable volume may still be blocked.
        // Keep that task tracked until it actually exits; viewport changes must
        // never fan out more workers behind a cancelled parent.
        guard visibleAvailabilityTask == nil, !visibleReferences.isEmpty else { return }
        visibleAvailabilityTask = Task { [weak self] in
            defer { self?.finishVisibleAvailabilityLoop() }
            while !Task.isCancelled, self?.visibleReferences.isEmpty == false {
                let generation = self?.visibleAvailabilityGeneration
                await self?.refreshVisibleAvailability()
                guard !Task.isCancelled else { return }
                if generation == self?.visibleAvailabilityGeneration {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
                // A changed viewport gets exactly one fresh pass after the
                // prior worker returns, without waiting for the next cadence.
            }
        }
    }

    private func finishVisibleAvailabilityLoop() {
        visibleAvailabilityTask = nil
        startVisibleAvailabilityIfNeeded()
    }

    private func refreshVisibleAvailability() async {
        let generation = visibleAvailabilityGeneration
        let references = Set(visibleReferences.values.flatMap { $0 })
        let videoRevision = revisions[.videoLibrary]
        let videoValues: [VideoWallpaper]
        if references.contains(where: { $0.provider == .videoLibrary }) {
            let values = manager.wallpapers
            let indices = await Self.visibleSourceIndices(values.map(\.id), references: references, provider: .videoLibrary)
            guard !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
            videoValues = indices.map { values[$0] }
        } else { videoValues = [] }
        if !videoValues.isEmpty {
            let updates = await manager.libraryContentItems(from: videoValues, reusing: [], refreshAvailability: true)
            guard !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
            await mergeVisibleAvailability(updates, provider: .videoLibrary, revision: videoRevision, generation: generation)
            guard !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
            if revisions[.videoLibrary] == videoRevision { visibleLocalFactsRefreshed.send() }
        }
        let imageRevision = revisions[.staticImageLibrary]
        let imageValues: [SILWallpaper]
        if references.contains(where: { $0.provider == .staticImageLibrary }) {
            let values = images.wallpapers
            let indices = await Self.visibleSourceIndices(values.map(\.id), references: references, provider: .staticImageLibrary)
            guard !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
            imageValues = indices.map { values[$0] }
        } else { imageValues = [] }
        if !imageValues.isEmpty {
            let updates = await images.libraryContentItems(from: imageValues, reusing: [], refreshAvailability: true)
            guard !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
            await mergeVisibleAvailability(updates, provider: .staticImageLibrary, revision: imageRevision, generation: generation)
        }
    }

    private func mergeVisibleAvailability(_ updates: [WallpaperContentItem], provider: WallpaperProvider,
                                          revision: UInt64?, generation: UUID) async {
        // A rename/removal/reimport can publish while its old path is checked.
        // Only the unchanged source generation may accept the worker receipt.
        guard let revision, revisions[provider] == revision, publishedRevisions[provider] == revision else { return }
        let previous = provider == .videoLibrary ? catalog.videos : catalog.images
        guard let next = await Self.mergedVisibleAvailability(updates, into: previous),
              !Task.isCancelled, generation == visibleAvailabilityGeneration else { return }
        publish(next, provider: provider, revision: revision, loaded: catalog.loadedProviders.contains(provider))
    }

    @concurrent nonisolated private static func visibleSourceIndices(_ ids: [String], references: Set<WallpaperReference>,
                                                                    provider: WallpaperProvider) async -> [Int] {
        ids.indices.filter { references.contains(.init(provider: provider, sourceID: ids[$0])) }
    }

    @concurrent nonisolated private static func mergedVisibleAvailability(_ updates: [WallpaperContentItem],
                                                                         into previous: [WallpaperContentItem]) async -> [WallpaperContentItem]? {
        let byReference = Dictionary(updates.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        var next = previous
        var changed = false
        for index in previous.indices {
            guard let update = byReference[previous[index].providerReference],
                  update != previous[index] else { continue }
            next[index] = update
            changed = true
        }
        return changed ? next : nil
    }

    /// Explicit refresh intent, separate from querying, searching or scrolling.
    /// The original source workers resolve current availability once per batch.
    func refreshAvailability() {
        refreshVideos = true
        refreshImages = true
        refreshSteam = true
        pixabay.refreshDownloadedContent()
        onlineImages.refreshLocal(Set(OnlineImageSource.allCases.filter { catalog.sourceScanStatuses[$0.provider] != nil }))
        replaceVideos(manager.wallpapers, loaded: manager.didFinishInitialIndexLoad)
        replaceImages(images.wallpapers)
        replaceSteam(steam.downloads, jobs: steam.downloadJobStore.jobs, account: steam.steamAuth.steamId,
                     loaded: steam.hasCompletedInstalledLibraryLoad)
    }

    private func updateDownloadsExclusions(_ records: [SteamWorkshopDownloadRecord], account: String?) {
        let excluded = steam.excludedDownloadReferences(in: records, accountSteamID: account)
        // Revoke foreign task-only facts synchronously with account willSet.
        // Published local rows remain shared even if an old task has the same ID.
        let published = Set(records.filter { $0.intentAccountSteamID == nil }.map {
            WallpaperReference(provider: .steamWorkshop, sourceID: $0.id)
        })
        let foreign = Set(records.filter { record in
            guard let owner = record.intentAccountSteamID else { return false }
            guard let account, !account.isEmpty else { return true }
            return !owner.utf8.elementsEqual(account.utf8)
        }.map { WallpaperReference(provider: .steamWorkshop, sourceID: $0.id) }).subtracting(published)
        let downloads = catalog.downloads.filter { !foreign.contains($0.providerReference) }
        guard catalog.excludedDownloadReferences != excluded || downloads != catalog.downloads else { return }
        var next = catalog
        next.downloads = downloads
        next.excludedDownloadReferences = excluded
        next.revision &+= 1
        catalog = next
    }

    private func nextRevision(_ provider: WallpaperProvider) -> UInt64 {
        let revision = (revisions[provider] ?? 0) &+ 1
        revisions[provider] = revision
        return revision
    }

    private func replaceVideos(_ values: [VideoWallpaper], loaded: Bool) {
        videoTask?.cancel()
        let previous = catalog.videos
        let checkedPrevious = publishedRevisions[.videoLibrary] == revisions[.videoLibrary] ? previous : []
        let revision = nextRevision(.videoLibrary)
        let refresh = refreshVideos
        let old = Dictionary(previous.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        let initial = values.map { value in
            let reference = WallpaperReference(provider: .videoLibrary, sourceID: value.id)
            let available = old[reference].flatMap { item in
                item.locator.path?.utf8.elementsEqual(value.path.utf8) == true ? item.publishedAvailability.isAvailable : nil
            } ?? true
            return VideoLibraryContentProjection.project(value, facts: .init(isPublishedLocally: true,
                isAvailable: available, canPlay: available, canDelete: true, canQuickLook: true,
                localURL: URL(fileURLWithPath: value.path)))
        }
        publish(initial, provider: .videoLibrary, revision: revision, loaded: catalog.loadedProviders.contains(.videoLibrary), availabilityChecked: false)
        videoTask = Task { [weak self, manager] in
            let items = await manager.libraryContentItems(from: values, reusing: checkedPrevious, refreshAvailability: refresh)
            guard !Task.isCancelled, let self, self.publish(items, provider: .videoLibrary, revision: revision, loaded: loaded) else { return }
            self.refreshVideos = false
        }
    }

    private func replaceImages(_ values: [SILWallpaper]) {
        imageTask?.cancel()
        let previous = catalog.images
        let checkedPrevious = publishedRevisions[.staticImageLibrary] == revisions[.staticImageLibrary] ? previous : []
        let revision = nextRevision(.staticImageLibrary)
        let refresh = refreshImages
        let old = Dictionary(previous.map { ($0.providerReference, $0) }, uniquingKeysWith: { first, _ in first })
        let initial = values.map { value in
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: value.id)
            let available = old[reference].flatMap { item in
                item.locator.path?.utf8.elementsEqual(value.path.utf8) == true ? item.publishedAvailability.isAvailable : nil
            } ?? true
            return StaticImageLibraryContentProjection.project(value, facts: .init(isPublishedLocally: true,
                isAvailable: available, canPlay: available, canDelete: true, canQuickLook: true,
                localURL: URL(fileURLWithPath: value.path)))
        }
        publish(initial, provider: .staticImageLibrary, revision: revision, loaded: catalog.loadedProviders.contains(.staticImageLibrary), availabilityChecked: false)
        imageTask = Task { [weak self, images] in
            let items = await images.libraryContentItems(from: values, reusing: checkedPrevious, refreshAvailability: refresh)
            guard !Task.isCancelled, let self, self.publish(items, provider: .staticImageLibrary, revision: revision) else { return }
            self.refreshImages = false
        }
    }

    private func replaceSteam(_ records: [SteamWorkshopDownloadRecord], jobs: [SteamDownloadJob], account: String?, loaded: Bool) {
        let oldTerminal = Dictionary(latestSteamJobs.filter { $0.isTerminal }.map { (Data($0.id.utf8), $0) },
                                     uniquingKeysWith: { first, _ in first })
        let newTerminal = Dictionary(jobs.filter { $0.isTerminal }.map { (Data($0.id.utf8), $0) },
                                     uniquingKeysWith: { first, _ in first })
        for id in Set(oldTerminal.keys).union(newTerminal.keys) where oldTerminal[id] != newTerminal[id] {
            if let job = newTerminal[id] ?? oldTerminal[id] {
                steamRefreshReferences.insert(WallpaperReference(provider: .steamWorkshop, sourceID: job.workshopItemId))
            }
        }
        latestSteamJobs = jobs
        steamTask?.cancel()
        let previous = catalog.downloads
        let checkedPrevious = publishedRevisions[.steamWorkshop] == revisions[.steamWorkshop] ? previous : []
        let revision = nextRevision(.steamWorkshop)
        if !loaded {
            let initial = steam.initialLibraryContentItems(from: records, jobs: jobs, account: account)
            publish(initial, provider: .steamWorkshop, revision: revision, loaded: false, availabilityChecked: false)
            return
        }
        let previousRecords = projectedSteamRecords
        let references = steamRefreshReferences
        let refreshAll = refreshSteam
        steamTask = Task { [weak self, steam] in
            let items = await steam.libraryContentItems(from: records, jobs: jobs, account: account,
                reusing: checkedPrevious, previousRecords: previousRecords,
                refreshAvailabilityFor: references, refreshAll: refreshAll)
            guard !Task.isCancelled, let self, self.publish(items, provider: .steamWorkshop, revision: revision, loaded: loaded) else { return }
            self.projectedSteamRecords = records
            self.steamRefreshReferences.subtract(references)
            self.refreshSteam = false
        }
    }

    private func replaceOnline(_ snapshot: PixabayDownloadedContentSnapshot) {
        let revision = nextRevision(.pixabay)
        let items = snapshot.entries.compactMap { entry in
            PixabayLibraryContentProjection.project(download: entry,
                facts: WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: entry.isAvailable,
                    canPlay: entry.isAvailable, canDelete: true, canQuickLook: true,
                    localURL: entry.localURL, resourceRevision: entry.thumbnailSourceKey))
        }
        publish(items, provider: .pixabay, revision: revision, loaded: snapshot.status.hasSuccessfulScan, scanStatus: snapshot.status)
    }

    private func replaceOnlineImages(_ snapshot: OnlineImageLocalSnapshot) {
        let records = Dictionary(grouping: snapshot.records, by: { $0.assetID.source })
        var sources = Dictionary(grouping: catalog.downloads, by: { $0.providerReference.provider })
        var next = catalog
        for source in OnlineImageSource.allCases {
            guard let status = snapshot.sourceStatuses[source] else { continue }
            sources[source.provider] = (records[source] ?? []).compactMap { record -> WallpaperContentItem? in
                guard let url = onlineImages.localURL(for: record) else { return nil }
                return OnlineImageContentProjection.local(record, url: url, available: !snapshot.unavailable.contains(record.id))
            }
            publishedRevisions[source.provider] = nextRevision(source.provider)
            if status.hasSuccessfulScan { next.loadedProviders.insert(source.provider) }
            next.sourceScanStatuses[source.provider] = status
        }
        next.downloads = [.steamWorkshop, .pixabay, .wallhaven, .pixiv].flatMap { sources[$0] ?? [] }
        install(next)
    }

    @discardableResult private func publish(_ items: [WallpaperContentItem], provider: WallpaperProvider, revision: UInt64,
                                          loaded: Bool = true, scanStatus: WallpaperSourceScanStatus? = nil, availabilityChecked: Bool = true) -> Bool {
        guard revisions[provider] == revision else { return false }
        if availabilityChecked { publishedRevisions[provider] = revision }
        var next = catalog
        switch provider {
        case .videoLibrary: next.videos = items
        case .staticImageLibrary: next.images = items
        case .steamWorkshop, .pixabay, .wallhaven, .pixiv:
            var sources = Dictionary(grouping: catalog.downloads, by: { $0.providerReference.provider })
            sources[provider] = items
            next.downloads = [.steamWorkshop, .pixabay, .wallhaven, .pixiv].flatMap { sources[$0] ?? [] }
        }
        if loaded { next.loadedProviders.insert(provider) }
        if let scanStatus { next.sourceScanStatuses[provider] = scanStatus }
        install(next)
        return true
    }

    private func install(_ value: WallpaperLibraryCatalog) {
        var next = value
        if next.videos != catalog.videos || next.images != catalog.images || next.downloads != catalog.downloads
            || next.loadedProviders != catalog.loadedProviders || next.sourceScanStatuses != catalog.sourceScanStatuses {
            next.revision &+= 1
            catalog = next
        }
    }
}
