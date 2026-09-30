//
//  SidebarViews+DataSource.swift
//  MyWallpaperX
//

import AppKit

extension AppKitSidebarContainerView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else {
            return rootNodes.count
        }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else {
            return rootNodes[index]
        }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? SidebarNode else { return nil }
        let pasteboardItem = NSPasteboardItem()
        switch node.kind {
        case .tag(let tag):
            pasteboardItem.setString("tag:\(tag)", forType: .string)
            return pasteboardItem
        case .silTag(let tag):
            pasteboardItem.setString("silTag:\(tag)", forType: .string)
            return pasteboardItem
        default:
            return nil
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        writeItems items: [Any],
        to pasteboard: NSPasteboard
    ) -> Bool {
        guard let node = items.first as? SidebarNode else { return false }
        switch node.kind {
        case .tag(let tag):
            pasteboard.clearContents()
            pasteboard.setString("tag:\(tag)", forType: .string)
            return true
        case .silTag(let tag):
            pasteboard.clearContents()
            pasteboard.setString("silTag:\(tag)", forType: .string)
            return true
        default:
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let str = info.draggingPasteboard.string(forType: .string) else { return false }
        if str.hasPrefix("tag:") {
            let tag = String(str.dropFirst(4))
            return wallpaperManager.tags.contains(tag)
        }
        if str.hasPrefix("silTag:") {
            let tag = String(str.dropFirst(7))
            return SILService.shared.silTags.contains(tag)
        }
        return false
    }
}
