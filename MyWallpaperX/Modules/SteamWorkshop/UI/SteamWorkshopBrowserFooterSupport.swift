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

    static func text(for state: State, itemCount: Int = 0) -> String {
        switch state {
        case .hidden:
            return ""
        case .ready:
            return "已加载 \(itemCount) 个作品"
        case .loading:
            return "正在加载更多项目"
        case .failed(let message):
            return message
        case .exhausted:
            return "已加载 \(itemCount) 个作品"
        }
    }

    static func configure(_ item: AppKitSteamWorkshopBrowserFooterItem, state: State, itemCount: Int) {
        item.configure(text: text(for: state, itemCount: itemCount))
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
