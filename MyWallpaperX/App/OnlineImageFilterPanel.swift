import AppKit

/// Source-specific query edits over the shared native filter presentation.
@MainActor enum OnlineImageFilterPanel {
    typealias Query = OnlineImageBrowserSession.Query
    typealias Edit = (@escaping (Query) -> Query) -> Void
    typealias Panel = WallpaperFilterPanelController

    static func make(session: OnlineImageBrowserSession, edit: @escaping Edit) -> Panel {
        switch session.state.query {
        case .wallhaven: return wallhaven(session: session, edit: edit)
        case .pixiv: return pixiv(session: session, edit: edit)
        }
    }

    private static func wallhaven(session: OnlineImageBrowserSession, edit: @escaping Edit) -> Panel {
        func current() -> WallhavenQuery {
            if case .wallhaven(let value) = session.state.query { return value }
            return .init()
        }
        func option(_ title: String, selected: @escaping (WallhavenQuery) -> Bool,
                    toggle: @escaping (inout WallhavenQuery) -> Void) -> Panel.Option {
            .init(title: title, isSelected: { selected(current()) }, toggle: {
                edit { query in
                    guard case .wallhaven(var value) = query else { return query }
                    toggle(&value)
                    return .wallhaven(value)
                }
            })
        }
        let categories = [String(localized: "General"), String(localized: "Anime"), String(localized: "People")].enumerated().map { index, title in
            option(title, selected: { Array($0.categories)[index] == "1" }, toggle: { query in
                var mask = Array(query.categories); mask[index] = mask[index] == "1" ? "0" : "1"
                query.categories = mask.allSatisfy { $0 == "0" } ? "111" : String(mask)
            })
        }
        let content = [String(localized: "Safe"), String(localized: "Sensitive"), String(localized: "Adult (Key Required)")].enumerated().map { index, title in
            option(title, selected: { Array($0.purity)[index] == "1" }, toggle: { query in
                var mask = Array(query.purity); mask[index] = mask[index] == "1" ? "0" : "1"
                query.purity = mask.allSatisfy { $0 == "0" } ? "100" : String(mask)
            })
        }
        let resolutions = Panel.minimumResolutions.map { size in
            let value: String? = size.width == 0 ? nil : "\(size.width)x\(size.height)"
            return option(size.title, selected: { $0.minimumResolution == value }, toggle: {
                $0.minimumResolution = $0.minimumResolution == value ? nil : value
            })
        }
        let ratios = [option(String(localized: "Any"), selected: { $0.ratios.isEmpty }, toggle: { $0.ratios = [] })]
            + ["16x9", "16x10", "21x9", "32x9", "1x1", "9x16"].map { ratio in
                option(ratio.replacingOccurrences(of: "x", with: ":"), selected: { $0.ratios.contains(ratio) }, toggle: {
                    if $0.ratios.contains(ratio) { $0.ratios.removeAll { $0 == ratio } }
                    else { $0.ratios.append(ratio) }
                })
            }
        return Panel(sections: [.init(title: String(localized: "Categories"), columns: 3, options: categories),
            .init(title: String(localized: "Content"), columns: 3, options: content), .init(title: String(localized: "Minimum Resolution"), columns: 2, options: resolutions),
            .init(title: String(localized: "Aspect Ratio"), columns: 4, options: ratios)], summary: {
                let query = current()
                var values: [String] = []
                if query.categories != "111" {
                    values += [String(localized: "General"), String(localized: "Anime"), String(localized: "People")].enumerated().compactMap { Array(query.categories)[$0.offset] == "1" ? $0.element : nil }
                }
                values.append([String(localized: "Safe"), String(localized: "Sensitive"), String(localized: "Adult")].enumerated().compactMap { Array(query.purity)[$0.offset] == "1" ? $0.element : nil }.joined(separator: "/"))
                if let minimum = query.minimumResolution { values.append(minimum.replacingOccurrences(of: "x", with: " × ") + String(localized: " and up")) }
                values += query.ratios.map { $0.replacingOccurrences(of: "x", with: ":") }
                return values.joined(separator: " · ")
            }, canClear: {
                let query = current()
                return query.categories != "111" || query.purity != "100" || query.minimumResolution != nil
                    || !query.ratios.isEmpty
            }, clear: {
                edit { query in
                    guard case .wallhaven(var value) = query else { return query }
                    value.categories = "111"; value.purity = "100"; value.minimumResolution = nil
                    value.ratios = []
                    return .wallhaven(value)
                }
            })
    }

    private static func pixiv(session: OnlineImageBrowserSession, edit: @escaping Edit) -> Panel {
        func current() -> PixivQuery {
            if case .pixiv(let value) = session.state.query { return value }
            return .init()
        }
        func option(_ title: String, selected: @escaping (PixivQuery) -> Bool,
                    toggle: @escaping (inout PixivQuery) -> Void) -> Panel.Option {
            .init(title: title, isSelected: { selected(current()) }, toggle: {
                edit { query in
                    guard case .pixiv(var value) = query else { return query }
                    toggle(&value)
                    return .pixiv(value)
                }
            })
        }
        let contentApplies = current().authorID?.isEmpty == false || !current().searchWord.isEmpty
        var sections: [Panel.Section] = [
            .init(title: String(localized: "Artwork Type"), columns: 2, options: [
                option(String(localized: "Illustrations"), selected: { $0.workType == .illustrations }, toggle: { $0.workType = .illustrations }),
                option(String(localized: "Manga"), selected: { $0.workType == .manga }, toggle: { $0.workType = .manga })]),
            .init(title: String(localized: "AI Art"), columns: 2, options: [
                option(String(localized: "All"), selected: { $0.ai == .include }, toggle: { $0.ai = .include }),
                option(String(localized: "Hide AI and Unmarked"), selected: { $0.ai == .hide }, toggle: { $0.ai = .hide })])
        ]
        if contentApplies {
            sections.append(.init(title: String(localized: "Content Scope"), columns: 2, options: [
                option(String(localized: "Safe Content Only"), selected: { $0.content == .safe }, toggle: {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.content = .safe }
                }),
                option(String(localized: "Content allowed by the account"), selected: { $0.content == .accountAllowed }, toggle: {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.content = .accountAllowed }
                })]))
        }
        return Panel(sections: sections, summary: {
            let query = current()
            var values = [query.workType == .illustrations ? String(localized: "Illustrations") : String(localized: "Manga")]
            if query.ai == .hide { values.append(String(localized: "Hide AI and Unmarked")) }
            values.append(contentApplies ? (query.content == .safe ? String(localized: "Safe") : String(localized: "Allowed by account")) : String(localized: "Rankings follow the site"))
            return values.joined(separator: " · ")
        }, canClear: {
            let query = current()
            return query.workType != .illustrations || query.ai != .include || (contentApplies && query.content != .safe)
        }, clear: {
            edit { query in
                guard case .pixiv(var value) = query else { return query }
                value.workType = .illustrations; value.ai = .include; value.content = .safe
                return .pixiv(value)
            }
        })
    }
}
