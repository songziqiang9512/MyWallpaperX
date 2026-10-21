import Foundation

extension SteamWorkshopService {
    func presentDownloadTaskDetail(itemID: String, title: String) {
        if let item = browserItemForDownload(id: itemID) {
            presentItemDetail(item)
            return
        }
        guard let detailURL = URL(
            string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(itemID)"
        ) else { return }
        presentItemDetail(SteamWorkshopBrowserItem(
            id: itemID,
            title: title,
            author: "未知作者",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: "",
            descriptionText: "",
            tags: [],
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: "Wallpaper",
            dependencyIDs: [],
            previewImageURL: nil,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: nil,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: detailURL
        ))
    }

    func presentItemDetail(_ item: SteamWorkshopBrowserItem) {
        if selectedBrowserItem?.id != item.id || selectedDownloadInspectorItem != nil {
            cancelSelectedItemDetailRefresh()
            selectedDownloadInspectorItem = nil
            selectedDownloadDetailItem = nil
        }
        let listedItem = browserItems.first(where: { $0.id == item.id }) ?? item
        let cachedItem = SteamWorkshopDetailRefreshSupport.needsRefresh(listedItem)
            ? Self.loadDetailCache(id: item.id) : nil
        let resolvedItem = cachedItem.flatMap { SteamWorkshopDetailRefreshSupport.needsRefresh($0) ? nil : $0 } ?? listedItem
        if resolvedItem != listedItem { mergeBrowserItem(resolvedItem) }
        selectedBrowserItem = resolvedItem
        selectedBrowserItemError = nil
        currentWorkshopItemID = resolvedItem.id
        currentPageTitle = resolvedItem.title
        statusMessage = "已加载 \(resolvedItem.title)"
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: false)
    }

    func dismissItemDetail() {
        if selectedBrowserItem != nil { cancelSelectedItemDetailRefresh() }
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
    }

    /// One request serves one visible inspector consumer. End its entire
    /// transient state before changing consumer, item or browse context.
    func cancelSelectedItemDetailRefresh() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        inFlightDetailItemID = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        isRefreshingSelectedDownloadDetailItem = false
        selectedDownloadDetailError = nil
    }

    func retryInspectorDetailRefresh(for itemID: String) {
        if let selectedDownloadInspectorItem,
           selectedDownloadInspectorItem.id == itemID {
            retryInspectorPreviewLoad(for: selectedDownloadDetailItem ?? selectedDownloadInspectorItem)
            refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: true)
            return
        }

        guard let selectedBrowserItem, selectedBrowserItem.id == itemID else { return }
        retryInspectorPreviewLoad(for: selectedBrowserItem)
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
    }

    func refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: Bool, metadataIsStale: Bool = false) {
        guard let item = selectedDownloadInspectorItem else { return }
        let needsDetails = SteamWorkshopDetailRefreshSupport.needsRefresh(item)
        guard forceRefresh || needsDetails || metadataIsStale else { return }
        let showsProgress = forceRefresh || needsDetails
        if let selectedItemDetailTask, !selectedItemDetailTask.isCancelled,
           inFlightDetailItemID == item.id, !forceRefresh {
            return
        }

        selectedItemDetailTask?.cancel()
        inFlightDetailItemID = item.id
        isRefreshingSelectedDownloadDetailItem = showsProgress
        selectedDownloadDetailError = nil

        selectedItemDetailTask = Task(priority: showsProgress ? .userInitiated : .utility) { [weak self] in
            do {
                guard let self else { return }
                let refreshed = try await self.fetchWorkshopItemViaSteamKit(
                    fallback: item
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.selectedItemDetailTask = nil
                    if self.inFlightDetailItemID == item.id { self.inFlightDetailItemID = nil }
                    guard self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.selectedDownloadDetailItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.persistRefreshedDownloadMetadata(refreshed)
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    self.selectedItemDetailTask = nil
                    if self.inFlightDetailItemID == item.id { self.inFlightDetailItemID = nil }
                    guard self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = showsProgress ? error.localizedDescription : nil
                }
            }
        }
    }

    func persistRefreshedDownloadMetadata(_ item: SteamWorkshopBrowserItem, fetchedAt: Date = Date()) {
        guard let record = latestDownloadRecord(for: item.id),
              record.status == .ready else { return }
        persistDownloadMetadata(item: item, id: item.id, targetURL: record.folderURL, fetchedAt: fetchedAt)
        // Reopening before the asynchronous library scan finishes must already
        // see the accepted detail result. Keep all local storage fields intact.
        if let index = downloads.firstIndex(where: { $0.id == item.id }) {
            downloads[index].browserItem = item
        }
        reloadInstalledItems()
        if selectedDownloadInspectorItem?.id == item.id {
            selectedDownloadInspectorItem = item
            selectedDownloadDetailItem = item
        }
    }

    func openAuthorWorkshopFromLocalDownloadMetadata(for item: SteamWorkshopBrowserItem) {
        guard selectedDownloadInspectorItem?.id == item.id,
              let record = latestDownloadRecord(for: item.id) else {
            openAuthorWorksPage(for: item)
            return
        }

        if let cachedItem = record.displayItem,
           Self.creatorID(from: cachedItem.authorProfileURL) != nil
            || Self.creatorID(from: cachedItem.authorWorkshopURL) != nil {
            openAuthorWorksPage(for: cachedItem)
            return
        }

        if Self.creatorID(from: item.authorProfileURL) != nil
            || Self.creatorID(from: item.authorWorkshopURL) != nil {
            persistRefreshedDownloadMetadata(item)
            openAuthorWorksPage(for: item)
            return
        }

        cancelSelectedItemDetailRefresh()
        inFlightDetailItemID = item.id
        isRefreshingSelectedDownloadDetailItem = true
        selectedDownloadDetailError = nil
        statusMessage = "本地缺少作者工坊链接，正在按作品 ID 查询作者信息…"

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            let resolved = await self?.resolveCachedDownloadAuthorMetadata(
                itemID: item.id,
                fallback: record.displayItem ?? item,
                title: item.title
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else { return }
                self.selectedItemDetailTask = nil
                if self.inFlightDetailItemID == item.id { self.inFlightDetailItemID = nil }
                self.isRefreshingSelectedDownloadDetailItem = false
                guard self.selectedDownloadInspectorItem?.id == item.id,
                      let resolved else { return }
                self.selectedDownloadDetailItem = resolved
                self.mergeBrowserItem(resolved)
                self.persistRefreshedDownloadMetadata(resolved)
                self.isRefreshingSelectedDownloadDetailItem = false
                self.selectedDownloadDetailError = nil
                guard Self.resolvedAuthorWorkshopURL(for: resolved) != nil else {
                    self.statusMessage = "没有获取到作者工坊链接。"
                    return
                }
                self.openAuthorWorksPage(for: resolved)
            }
        }
    }

    func resolveCachedDownloadAuthorMetadata(
        itemID: String,
        fallback: SteamWorkshopBrowserItem?,
        title: String?
    ) async -> SteamWorkshopBrowserItem? {
        if let fallback,
           Self.creatorID(from: fallback.authorProfileURL) != nil
            || Self.creatorID(from: fallback.authorWorkshopURL) != nil {
            return fallback
        }

        do {
            let base = fallback ?? Self.itemByMergingAuthorMetadata(
                into: fallback,
                id: itemID,
                title: title,
                author: "未知作者",
                authorProfileURL: nil,
                authorWorkshopURL: nil
            )
            return try await fetchWorkshopItemViaSteamKit(
                fallback: base
            )
        } catch {
            return fallback
        }
    }

    nonisolated static func itemByMergingAuthorMetadata(
        into fallback: SteamWorkshopBrowserItem?,
        id: String,
        title: String?,
        author: String,
        authorProfileURL: URL?,
        authorWorkshopURL: URL?
    ) -> SteamWorkshopBrowserItem {
        let base = fallback ?? SteamWorkshopBrowserItem(
            id: id,
            title: title ?? "Workshop #\(id)",
            author: "未知作者",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: "",
            descriptionText: "",
            tags: [],
            workshopTypeText: nil,
            ageRatingText: nil,
            genreText: nil,
            categoryText: nil,
            dependencyIDs: [],
            previewImageURL: nil,
            previewVideoURL: nil,
            previewAssetKind: .unknown,
            fileSizeText: nil,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: makeDetailURL(id: id)
        )

        return SteamWorkshopBrowserItem(
            id: base.id,
            title: base.title,
            author: author == "未知作者" ? base.author : author,
            authorProfileURL: authorProfileURL ?? base.authorProfileURL,
            authorWorkshopURL: authorWorkshopURL ?? base.authorWorkshopURL,
            hasAdultContent: base.hasAdultContent,
            summary: base.summary,
            descriptionText: base.descriptionText,
            tags: base.tags,
            workshopTypeText: base.workshopTypeText,
            ageRatingText: base.ageRatingText,
            genreText: base.genreText,
            categoryText: base.categoryText,
            dependencyIDs: base.dependencyIDs,
            previewImageURL: base.previewImageURL,
            previewVideoURL: base.previewVideoURL,
            previewAssetKind: base.previewAssetKind,
            fileSizeText: base.fileSizeText,
            resolutionText: base.resolutionText,
            postedText: base.postedText,
            updatedText: base.updatedText,
            favoritesText: base.favoritesText,
            subscriptionsText: base.subscriptionsText,
            scoreText: base.scoreText,
            lifetimeFavoritesText: base.lifetimeFavoritesText,
            lifetimeSubscriptionsText: base.lifetimeSubscriptionsText,
            visibilityText: base.visibilityText,
            moderationText: base.moderationText,
            detailFields: base.detailFields,
            detailURL: base.detailURL
        )
    }

    private func retryInspectorPreviewLoad(for item: SteamWorkshopBrowserItem) {
        if let previewURL = item.previewImageURL {
            SteamWorkshopPreviewRequestCoordinator.shared.resetFailureState(for: previewURL)
            steamWorkshopInvalidatePreview(previewURL)
        }
        previewReloadToken += 1
    }

    private func refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedBrowserItem else { return }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }
        if let selectedItemDetailTask, !selectedItemDetailTask.isCancelled,
           inFlightDetailItemID == item.id, !forceRefresh {
            return
        }

        selectedItemDetailTask?.cancel()
        inFlightDetailItemID = item.id
        isRefreshingSelectedBrowserItem = true
        selectedBrowserItemError = nil

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                guard let self else { return }
                let refreshed = try await self.fetchWorkshopItemViaSteamKit(
                    fallback: item
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.selectedItemDetailTask = nil
                    if self.inFlightDetailItemID == item.id { self.inFlightDetailItemID = nil }
                    guard self.selectedBrowserItem?.id == item.id else { return }
                    self.selectedBrowserItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.persistRefreshedDownloadMetadata(refreshed)
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    self.selectedItemDetailTask = nil
                    if self.inFlightDetailItemID == item.id { self.inFlightDetailItemID = nil }
                    guard self.selectedBrowserItem?.id == item.id else { return }
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = error.localizedDescription
                }
            }
        }
    }
}
