//
//  SteamWorkshopService+DownloadFiltering.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    func filteredAndSortedDownloads(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {
        let modeFiltered = records.filter { record in
            switch downloadsDisplayMode {
            case .all:
                return true
            case .video:
                return record.contentType == .video
            case .web:
                return record.contentType == .web
            case .scene:
                return record.contentType == .scene
            case .missingDependency:
                if case .missing = record.dependencyStatus {
                    return true
                }
                return false
            }
        }
        let query = downloadsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [SteamWorkshopDownloadRecord]
        if query.isEmpty {
            filtered = modeFiltered
        } else {
            let normalized = query.localizedLowercase
            let idQuery = Self.workshopItemIDSearchID(from: query)?.localizedLowercase ?? normalized
            filtered = modeFiltered.filter {
                $0.title.localizedLowercase.contains(normalized)
                || $0.description.localizedLowercase.contains(normalized)
                || $0.tags.contains(where: { $0.localizedLowercase.contains(normalized) })
                || $0.id.localizedLowercase.contains(idQuery)
                || $0.browserItem?.author.localizedLowercase.contains(normalized) == true
            }
        }
        return filtered.sorted { lhs, rhs in
            switch downloadsSortMode {
            case .updatedAt:
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison == .orderedSame {
                    return downloadsSortAscending ? (lhs.updatedAt < rhs.updatedAt) : (lhs.updatedAt > rhs.updatedAt)
                }
                return downloadsSortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
            case .size:
                let lhsSize = Self.parseByteCount(from: lhs.sizeText) ?? 0
                let rhsSize = Self.parseByteCount(from: rhs.sizeText) ?? 0
                if lhsSize == rhsSize {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return downloadsSortAscending ? (lhsSize < rhsSize) : (lhsSize > rhsSize)
            }
        }
    }

    func sanitizeDownloadSelectionAgainstDisplayedDownloads() {
        let visibleIDs = Set(displayedDownloads.map(\.id))
        let visibleSelection = selectedDownloadIDs.intersection(visibleIDs)
        let normalizedPrimaryID: String? = {
            if let selectedDownloadID, visibleIDs.contains(selectedDownloadID) {
                return selectedDownloadID
            }
            if isDownloadsMultiSelectMode {
                return firstDisplayedDownloadID(in: visibleSelection)
            }
            return nil
        }()
        let normalizedSelectedIDs = isDownloadsMultiSelectMode
            ? visibleSelection
            : (normalizedPrimaryID.map { [$0] } ?? [])
        guard normalizedPrimaryID != selectedDownloadID || normalizedSelectedIDs != selectedDownloadIDs else {
            return
        }
        publishDownloadSelectionState(
            primaryID: normalizedPrimaryID,
            selectedIDs: normalizedSelectedIDs,
            deferPublishing: true
        )
    }

    func clearFilters() {
        guard !facetFilters.isEmpty || !browserContentMode.isAll else { return }
        let wasSuppressed = suppressAutomaticBrowseNavigation
        suppressAutomaticBrowseNavigation = true
        browserContentMode = .all
        facetFilters = .none
        suppressAutomaticBrowseNavigation = wasSuppressed
        if !wasSuppressed { navigateToBrowse() }
    }
}
