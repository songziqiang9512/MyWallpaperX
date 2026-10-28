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
        let categories = ["综合", "动漫", "人物"].enumerated().map { index, title in
            option(title, selected: { Array($0.categories)[index] == "1" }, toggle: { query in
                var mask = Array(query.categories); mask[index] = mask[index] == "1" ? "0" : "1"
                query.categories = mask.allSatisfy { $0 == "0" } ? "111" : String(mask)
            })
        }
        let content = ["安全", "敏感", "成人（需 Key）"].enumerated().map { index, title in
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
        let ratios = [option("不限", selected: { $0.ratios.isEmpty }, toggle: { $0.ratios = [] })]
            + ["16x9", "16x10", "21x9", "32x9", "1x1", "9x16"].map { ratio in
                option(ratio.replacingOccurrences(of: "x", with: ":"), selected: { $0.ratios.contains(ratio) }, toggle: {
                    if $0.ratios.contains(ratio) { $0.ratios.removeAll { $0 == ratio } }
                    else { $0.ratios.append(ratio) }
                })
            }
        return Panel(sections: [.init(title: "分类", columns: 3, options: categories),
            .init(title: "内容", columns: 3, options: content), .init(title: "最低分辨率", columns: 2, options: resolutions),
            .init(title: "比例", columns: 4, options: ratios)], summary: {
                let query = current()
                var values: [String] = []
                if query.categories != "111" {
                    values += ["综合", "动漫", "人物"].enumerated().compactMap { Array(query.categories)[$0.offset] == "1" ? $0.element : nil }
                }
                values.append(["安全", "敏感", "成人"].enumerated().compactMap { Array(query.purity)[$0.offset] == "1" ? $0.element : nil }.joined(separator: "/"))
                if let minimum = query.minimumResolution { values.append(minimum.replacingOccurrences(of: "x", with: " × ") + " 及以上") }
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
            .init(title: "作品类型", columns: 2, options: [
                option("插画", selected: { $0.workType == .illustrations }, toggle: { $0.workType = .illustrations }),
                option("漫画", selected: { $0.workType == .manga }, toggle: { $0.workType = .manga })]),
            .init(title: "AI 作品", columns: 2, options: [
                option("全部", selected: { $0.ai == .include }, toggle: { $0.ai = .include }),
                option("隐藏 AI 与未标注", selected: { $0.ai == .hide }, toggle: { $0.ai = .hide })])
        ]
        if contentApplies {
            sections.append(.init(title: "内容范围", columns: 2, options: [
                option("仅安全内容", selected: { $0.content == .safe }, toggle: {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.content = .safe }
                }),
                option("账号允许的内容", selected: { $0.content == .accountAllowed }, toggle: {
                    if $0.authorID?.isEmpty == false || !$0.searchWord.isEmpty { $0.content = .accountAllowed }
                })]))
        }
        return Panel(sections: sections, summary: {
            let query = current()
            var values = [query.workType == .illustrations ? "插画" : "漫画"]
            if query.ai == .hide { values.append("隐藏 AI 与未标注") }
            values.append(contentApplies ? (query.content == .safe ? "安全" : "账号允许") : "排行内容跟随站点")
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
