import Foundation

extension SteamWorkshopAgeRatingFilter {
    func allows(tags: [String]) -> Bool {
        guard self != .all else { return true }
        guard !isEmpty else { return false }
        guard let rating = Self.selectableRatings.first(where: { candidate in
            tags.contains { $0.caseInsensitiveCompare(candidate.tagValue) == .orderedSame }
        }) else {
            return false
        }
        return contains(rating)
    }

    var activeDisplayName: String? {
        guard self != .all else { return nil }
        guard !isEmpty else { return "不显示任何年龄分级" }
        return Self.selectableRatings
            .filter(contains)
            .map(\.displayName)
            .joined(separator: "、")
    }
}

extension SteamWorkshopService {
    func fetchAgeFilteredBrowserItemsIfNeeded(
        stubs: [SteamWorkshopBrowseStub],
        browserContentMode: SteamWorkshopBrowserContentMode
    ) async throws -> [SteamWorkshopBrowserItem]? {
        guard ageRatingFilter != .all else { return nil }
        let items = try await Self.fetchWorkshopItems(
            stubs: stubs,
            browserContentMode: browserContentMode,
            requestPriority: .userInitiated
        )
        return visibleItemsAfterApplyingAgeRating(items)
    }

    func visibleItemsAfterApplyingAgeRating(_ items: [SteamWorkshopBrowserItem]) -> [SteamWorkshopBrowserItem] {
        items.filter { ageRatingFilter.allows(tags: $0.tags) }
    }

    func continueAgeFilteredPaginationIfNeeded(loadedVisibleItemCount: Int) {
        guard ageRatingFilter != .all,
              !ageRatingFilter.isEmpty,
              loadedVisibleItemCount == 0,
              hasMoreBrowserItems,
              !isLoadingMoreBrowserItems else {
            return
        }
        Task { @MainActor [weak self] in
            self?.loadMoreBrowserItemsIfNeeded()
        }
    }

    func removeAgeFilteredStubs(_ stubs: [SteamWorkshopBrowseStub], keeping items: [SteamWorkshopBrowserItem]) {
        let visibleIDs = Set(items.map(\.id))
        let hiddenIDs = Set(stubs.map(\.id)).subtracting(visibleIDs)
        guard !hiddenIDs.isEmpty else { return }
        browserItems.removeAll { hiddenIDs.contains($0.id) }
        if !ageRatingFilter.isEmpty,
           browserItems.isEmpty,
           hasMoreBrowserItems,
           !isLoadingMoreBrowserItems {
            Task { @MainActor [weak self] in
                self?.loadMoreBrowserItemsIfNeeded()
            }
        }
    }
}
