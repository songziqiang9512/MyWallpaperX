//
//  SteamWorkshopBrowserFooterSupport.swift
//  MyWallpaperX
//

import AppKit

enum SteamWorkshopBrowserFooterSupport {
    enum State: Equatable {
        case hidden
        case ready
        case loading
        case failed(String)
        case exhausted
    }

    static let itemID = "__steam_workshop_grid_footer__"

    static func resolvedState(
        failureMessage: String?,
        isLoadingMore: Bool,
        hasMore: Bool,
        itemIDs: [String]
    ) -> State {
        if isLoadingMore {
            return .loading
        }
        if let failureMessage, hasMore {
            return .failed(failureMessage)
        }
        if hasMore { return .ready }
        return itemIDs.isEmpty ? .hidden : .exhausted
    }

    static func text(for state: State) -> String {
        switch state {
        case .hidden:
            return ""
        case .ready:
            return "继续下滑以加载更多项目。"
        case .loading:
            return "正在加载更多项目…"
        case .failed(let message):
            return message
        case .exhausted:
            return "已到达底部，更多作品请以 Steam 官方页面为准。"
        }
    }

    static func configure(
        _ item: AppKitSteamWorkshopBrowserFooterItem,
        state: State,
        onRetry: @escaping () -> Void
    ) {
        let symbol: (name: String, accessibilityDescription: String)
        switch state {
        case .ready:
            symbol = ("arrow.down.circle", "可以加载更多内容")
        case .failed:
            symbol = ("exclamationmark.triangle", "加载更多内容失败")
        case .exhausted, .hidden:
            symbol = ("checkmark.circle", "没有更多内容")
        case .loading:
            symbol = ("arrow.down.circle", "正在加载更多内容")
        }
        let showsRetry: Bool
        if state == .ready {
            showsRetry = true
        } else if case .failed = state {
            showsRetry = true
        } else {
            showsRetry = false
        }
        item.configure(
            text: text(for: state),
            showsProgress: state == .loading,
            showsRetry: showsRetry,
            retryTitle: state == .ready ? "继续加载" : "重试",
            symbolName: symbol.name,
            symbolAccessibilityDescription: symbol.accessibilityDescription,
            onRetry: onRetry
        )
    }

    static func size(
        for state: State,
        boundsWidth: CGFloat,
        sectionInset: NSEdgeInsets
    ) -> NSSize {
        let width = max(120, boundsWidth - sectionInset.left - sectionInset.right)
        let height: CGFloat
        switch state {
        case .exhausted, .failed:
            height = 52
        default:
            height = 40
        }
        return NSSize(width: floor(width), height: height)
    }
}
