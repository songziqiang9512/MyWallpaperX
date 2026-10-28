import AppKit
import Combine

/// Steam owns its query rules; the shared panel supplies native checkbox geometry.
@MainActor final class SteamWorkshopFilterPanelController: WallpaperFilterPanelController {
    private var cancellables = Set<AnyCancellable>()

    init(service: SteamWorkshopService, apply: @escaping (() -> Void) -> Void = { $0() }) {
        func facet(_ title: String, marked: @escaping (SteamWorkshopBrowseFacetFilters) -> Bool,
                   toggle: @escaping (inout SteamWorkshopBrowseFacetFilters) -> Void) -> Option {
            .init(title: title, isSelected: { [weak service] in service.map { marked($0.facetFilters) } ?? false },
                toggle: { [weak service] in
                    guard let service else { return }
                    apply { var filters = service.facetFilters; toggle(&filters); service.facetFilters = filters }
                })
        }
        let content = SteamWorkshopBrowserContentMode.allCases.map { mode in
            Option(title: mode.shortDisplayName, isSelected: { [weak service] in
                guard let current = service?.browserContentMode else { return false }
                return mode == .all ? current.isAll : !current.isAll && current.contains(mode)
            }, toggle: { [weak service] in
                guard let service else { return }
                apply { var selection = service.browserContentMode; selection.toggle(mode); service.browserContentMode = selection }
            })
        }
        let themes = [facet("全部", marked: { $0.themes.isEmpty }, toggle: { $0.themes = [] })]
            + SteamWorkshopThemeFilter.allCases.filter { $0 != .all }.map { value in
                facet(value.displayName, marked: { $0.themes.contains(value) }, toggle: { $0.themes.formSymmetricDifference([value]) })
            }
        let ratings = [facet("全部", marked: { $0.ageRating == .all }, toggle: { $0.ageRating = .all })]
            + SteamWorkshopAgeRatingFilter.selectableRatings.map { value in
                facet(value.displayName, marked: { $0.ageRating != .all && $0.ageRating.contains(value) }, toggle: { filters in
                    if filters.ageRating == .all { filters.ageRating = value; return }
                    filters.ageRating.formSymmetricDifference(value)
                    if filters.ageRating.isEmpty { filters.ageRating = .all }
                })
            }
        let resolutions = [facet("全部", marked: { $0.resolutions.isEmpty }, toggle: { $0.resolutions = [] })]
            + SteamWorkshopResolutionFilter.allCases.filter { $0 != .all }.map { value in
                facet(value.displayName, marked: { $0.resolutions.contains(value) }, toggle: { $0.resolutions.formSymmetricDifference([value]) })
            }
        super.init(sections: [.init(title: "分类", columns: 4, options: content),
            .init(title: "类型", columns: 4, options: themes), .init(title: "分级", columns: 2, options: ratings),
            .init(title: "分辨率", columns: 3, options: resolutions)],
            summary: { [weak service] in service?.activeFilterSummary ?? "全部" },
            canClear: { [weak service] in service.map { !$0.facetFilters.isEmpty || !$0.browserContentMode.isAll } ?? false },
            clear: { [weak service] in apply { service?.clearFilters() } })
        service.$facetFilters.combineLatest(service.$browserContentMode)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.synchronize() }.store(in: &cancellables)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
