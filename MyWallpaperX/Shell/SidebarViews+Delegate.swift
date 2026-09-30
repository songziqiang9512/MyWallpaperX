//
//  SidebarViews+Delegate.swift
//  MyWallpaperX
//

import AppKit

extension AppKitSidebarContainerView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return node.isGroup
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.isGroup
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SidebarNode else { return 28 }
        return node.isGroup ? 24 : 30
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let node = item as? SidebarNode,
              !node.isGroup else {
            return nil
        }
        let rowView = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("SidebarRowView"), owner: self) as? SidebarRowView ?? {
            let view = SidebarRowView()
            view.identifier = NSUserInterfaceItemIdentifier("SidebarRowView")
            return view
        }()
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("SidebarGroupCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
                let newCell = NSTableCellView()
                newCell.identifier = identifier
                let textField = NSTextField(labelWithString: "")
                textField.font = .systemFont(ofSize: 12, weight: .semibold)
                textField.textColor = .secondaryLabelColor
                textField.translatesAutoresizingMaskIntoConstraints = false
                newCell.addSubview(textField)
                newCell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor)
                ])
                return newCell
            }()
            cell.textField?.stringValue = node.title
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("SidebarLeafCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? SidebarRowCellView ?? {
            let newCell = SidebarRowCellView()
            newCell.identifier = identifier
            return newCell
        }()
        cell.configure(
            title: node.title,
            symbolName: node.symbolName,
            count: node.count
        )
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              let selected = node.selectedItem else {
            return
        }
        currentSelectedItem = selected
        selectedItemSetter?(selected)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        guard let node = draggedItems.first as? SidebarNode else {
            liveDraggedTag = nil; isLiveTagReordering = false; liveTagOrder = nil; lastLiveDropDestination = nil
            liveSILDraggedTag = nil; isLiveSILTagReordering = false; liveSILTagOrder = nil; lastLiveSILDropDestination = nil
            return
        }
        // 视频库标签
        if case .tag(let tag) = node.kind {
            liveDraggedTag = tag
            isLiveTagReordering = true
            liveTagOrder = wallpaperManager.tags
            lastLiveDropDestination = nil
            liveTagNodeByTag = tagsSectionNode()?.children.reduce(into: [:]) { r, n in
                if case .tag(let t) = n.kind { r[t] = n }
            }
            session.animatesToStartingPositionsOnCancelOrFail = false
            if let row = rowIndex(for: .tag(tag)),
               let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
                rowView.suppressSelectionDuringDrag = true
                rowView.needsDisplay = true
            }
            DispatchQueue.main.async { [weak self] in self?.updateDraggingPresentation() }
            return
        }
        // 图片库标签
        if case .silTag(let tag) = node.kind {
            liveSILDraggedTag = tag
            isLiveSILTagReordering = true
            liveSILTagOrder = SILService.shared.silTags
            lastLiveSILDropDestination = nil
            liveSILTagNodeByTag = silTagsSectionNode()?.children.filter {
                if case .silTag = $0.kind { return true }; return false
            }.reduce(into: [:]) { r, n in
                if case .silTag(let t) = n.kind { r[t] = n }
            }
            session.animatesToStartingPositionsOnCancelOrFail = false
            if let row = rowIndex(for: .silTag(tag)),
               let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
                rowView.suppressSelectionDuringDrag = true
                rowView.needsDisplay = true
            }
            DispatchQueue.main.async { [weak self] in self?.updateSILDraggingPresentation() }
            return
        }
        liveDraggedTag = nil; isLiveTagReordering = false; liveTagOrder = nil; lastLiveDropDestination = nil
        liveSILDraggedTag = nil; isLiveSILTagReordering = false; liveSILTagOrder = nil; lastLiveSILDropDestination = nil
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // 视频库标签排序保存
        if let liveTagOrder, liveTagOrder != wallpaperManager.tags {
            wallpaperManager.tags = liveTagOrder
            wallpaperManager.saveTags()
        }
        isLiveTagReordering = false
        liveDraggedTag = nil
        self.liveTagOrder = nil
        lastLiveDropDestination = nil
        liveTagNodeByTag = nil
        // 图片库标签排序保存
        if let liveSILTagOrder, liveSILTagOrder != SILService.shared.silTags {
            SILService.shared.reorderSILTags(liveSILTagOrder)
        }
        isLiveSILTagReordering = false
        liveSILDraggedTag = nil
        self.liveSILTagOrder = nil
        lastLiveSILDropDestination = nil
        liveSILTagNodeByTag = nil
        // 恢复选中行视觉
        if let row = rowIndex(for: currentSelectedItem),
           let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView {
            rowView.suppressSelectionDuringDrag = false
            rowView.needsDisplay = true
        }
        updateDraggingPresentation()
        updateSILDraggingPresentation()
        rebuildRowIndexMap()
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let str = info.draggingPasteboard.string(forType: .string) else { return [] }
        if str.hasPrefix("tag:") {
            let tag = String(str.dropFirst(4))
            return wallpaperManager.tags.contains(tag) ? .move : []
        }
        if str.hasPrefix("silTag:") {
            let tag = String(str.dropFirst(7))
            return SILService.shared.silTags.contains(tag) ? .move : []
        }
        return []
    }

}
