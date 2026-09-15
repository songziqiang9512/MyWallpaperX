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
        prioritizeUserRequestedDetail()
        let resolvedItem = browserItems.first(where: { $0.id == item.id }) ?? item
        selectedBrowserItem = resolvedItem
        selectedBrowserItemError = nil
        currentWorkshopItemID = resolvedItem.id
        currentPageTitle = resolvedItem.title
        statusMessage = "已加载 \(resolvedItem.title)"
        let needsDependencyRefresh = SteamWorkshopDetailRefreshSupport.needsDependencyRefresh(resolvedItem)
        refreshSelectedBrowserItemDetailIfNeeded(
            forceRefresh: needsDependencyRefresh || SteamWorkshopDetailRefreshSupport.needsRefresh(resolvedItem)
        )
    }

    func dismissItemDetail() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
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

    func retrySelectedBrowserItemDetailRefresh() {
        guard let selectedBrowserItem else { return }
        retryInspectorDetailRefresh(for: selectedBrowserItem.id)
    }

    func refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedDownloadInspectorItem else { return }
        if selectedDownloadRecord?.contentType == .scene {
            selectedItemDetailTask?.cancel()
            selectedItemDetailTask = nil
            isRefreshingSelectedDownloadDetailItem = false
            selectedDownloadDetailError = nil
            selectedDownloadDetailItem = selectedDownloadInspectorItem
            return
        }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsDownloadedMetadataRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedDownloadDetailItem = true
        selectedDownloadDetailError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)
        let browserContentMode: SteamWorkshopBrowserContentMode =
            selectedDownloadRecord?.contentType == .web ? .web : .video

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.selectedDownloadDetailItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.persistRefreshedDownloadInspectorMetadata(refreshed)
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = error.localizedDescription
                }
            }
        }
    }

    private func persistRefreshedDownloadInspectorMetadata(_ item: SteamWorkshopBrowserItem) {
        guard let record = latestDownloadRecord(for: item.id),
              record.status == .ready else { return }
        persistDownloadMetadata(item: item, id: item.id, targetURL: record.folderURL)
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
           Self.resolvedAuthorWorkshopURL(for: cachedItem) != nil {
            openAuthorWorksPage(for: cachedItem)
            return
        }

        if Self.resolvedAuthorWorkshopURL(for: item) != nil {
            persistRefreshedDownloadInspectorMetadata(item)
            openAuthorWorksPage(for: item)
            return
        }

        selectedItemDetailTask?.cancel()
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
                guard let self,
                      self.selectedDownloadInspectorItem?.id == item.id,
                      let resolved else { return }
                self.selectedDownloadDetailItem = resolved
                self.mergeBrowserItem(resolved)
                self.persistRefreshedDownloadInspectorMetadata(resolved)
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
           Self.resolvedAuthorWorkshopURL(for: fallback) != nil {
            return fallback
        }

        do {
            guard let detail = try await Self.fetchPublishedFileDetails(
                ids: [itemID],
                requestPriority: .userInitiated
            )[itemID] else {
                appendSteamAuthDebugLog("DOWNLOAD METADATA: official detail missing for id=\(itemID)")
                return fallback
            }

            let authorProfileURL = detail.creator.flatMap { URL(string: "https://steamcommunity.com/profiles/\($0)/") }
            let authorWorkshopURL = detail.creator.flatMap {
                URL(string: "https://steamcommunity.com/profiles/\($0)/myworkshopfiles/?appid=\(Constants.workshopAppID)")
            }
            let stub = fallback.map(SteamWorkshopDetailRefreshSupport.makeStub) ?? SteamWorkshopBrowseStub(
                id: itemID,
                title: title,
                author: nil,
                authorProfileURL: authorProfileURL,
                authorWorkshopURL: authorWorkshopURL,
                hasAdultContent: false,
                summary: nil,
                previewImageURL: nil
            )
            let author = await Self.resolvedAuthorName(
                creatorID: detail.creator,
                stub: stub,
                authorProfileURL: authorProfileURL,
                authorWorkshopURL: authorWorkshopURL
            )
            let resolved = Self.itemByMergingAuthorMetadata(
                into: fallback,
                id: itemID,
                title: title,
                author: author,
                authorProfileURL: authorProfileURL,
                authorWorkshopURL: authorWorkshopURL
            )
            appendSteamAuthDebugLog("DOWNLOAD METADATA: resolved author URL for id=\(itemID)")
            return resolved
        } catch {
            appendSteamAuthDebugLog("DOWNLOAD METADATA: failed to resolve author URL for id=\(itemID), error=\(sanitizeSteamOutput(error.localizedDescription))")
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
            let cacheKey = steamWorkshopPreviewCacheKey(for: previewURL)
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
        }
        previewReloadToken += 1
    }

    private func refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedBrowserItem else { return }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedBrowserItem = true
        selectedBrowserItemError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)
        let browserContentMode = self.browserContentMode

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.selectedBrowserItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = error.localizedDescription
                }
            }
        }
    }
}
