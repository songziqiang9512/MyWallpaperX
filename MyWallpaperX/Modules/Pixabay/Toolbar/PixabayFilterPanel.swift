import AppKit

@MainActor enum PixabayFilterPanel {
    static func make(service: PixabayService,
                     edit: @escaping (@escaping (inout PixabaySearchParams) -> Void) -> Void) -> WallpaperFilterPanelController {
        typealias Panel = WallpaperFilterPanelController
        func option(_ title: String, selected: @escaping (PixabaySearchParams) -> Bool,
                    toggle: @escaping (inout PixabaySearchParams) -> Void) -> Panel.Option {
            .init(title: title, isSelected: { selected(service.currentParams) }, toggle: { edit(toggle) })
        }
        let categories = PixabayCategory.allCases.map { category in
            option(category.displayName, selected: { $0.category == category }, toggle: {
                $0.category = $0.category == category ? .all : category
            })
        }
        let types = PixabayVideoType.allCases.map { type in
            option(type.displayName, selected: { $0.videoType == type }, toggle: {
                $0.videoType = $0.videoType == type ? .all : type
            })
        }
        let resolutions = Panel.minimumResolutions.map { size in
            option(size.title, selected: { $0.minWidth == size.width && $0.minHeight == size.height }, toggle: {
                let clear = $0.minWidth == size.width && $0.minHeight == size.height
                $0.minWidth = clear ? 0 : size.width; $0.minHeight = clear ? 0 : size.height
            })
        }
        return Panel(sections: [.init(title: "分类", columns: 3, options: categories),
            .init(title: "视频类型", columns: 3, options: types), .init(title: "最低分辨率", columns: 2, options: resolutions),
            .init(title: "内容", columns: 2, options: [
                option("编辑精选", selected: { $0.editorsChoice }, toggle: { $0.editorsChoice.toggle() }),
                option("安全搜索", selected: { $0.safeSearch }, toggle: { $0.safeSearch.toggle() })])], summary: {
                let query = service.currentParams
                var values = [query.category == .all ? "全部分类" : query.category.displayName]
                if query.videoType != .all { values.append(query.videoType.displayName) }
                if query.minWidth > 0 || query.minHeight > 0 { values.append("\(query.minWidth) × \(query.minHeight) 及以上") }
                if query.editorsChoice { values.append("精选") }
                if query.safeSearch { values.append("安全") }
                return values.joined(separator: " · ")
            }, canClear: { service.currentParams.hasFilters }, clear: { edit { $0.clearFilters() } })
    }
}
