import AppKit

protocol SteamWorkshopKeyboardDelegate: AnyObject {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool
}

final class SteamWorkshopKeyboardCollectionView: NSCollectionView {
    weak var keyboardDelegate: SteamWorkshopKeyboardDelegate?
    var onBackgroundLeftClick: (() -> Void)?
    var accessibleItemsProvider: (() -> [Any])?
    override func accessibilityChildren() -> [Any]? { accessibleItemsProvider?() ?? super.accessibilityChildren() }
    override func isAccessibilityElement() -> Bool { accessibleItemsProvider != nil || super.isAccessibilityElement() }
    override func accessibilityRole() -> NSAccessibility.Role? { accessibleItemsProvider != nil ? .list : super.accessibilityRole() }
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var primaryClickHandler: ((IndexPath, Int) -> Bool)?
    private var primaryClickIndexPath: IndexPath?
    private var isTrackingPrimaryClick = false

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        isTrackingPrimaryClick = true
        primaryClickIndexPath = cardIndexPath(at: convert(event.locationInWindow, from: nil))
        // Selection is owned by the grid. Do not enter NSCollectionView's
        // selection tracking loop, which may consume mouseUp internally.
    }

    override func mouseUp(with event: NSEvent) {
        guard event.type == .leftMouseUp, isTrackingPrimaryClick else {
            super.mouseUp(with: event)
            return
        }
        isTrackingPrimaryClick = false
        let pressedIndexPath = primaryClickIndexPath
        primaryClickIndexPath = nil
        finishPrimaryMouseInteraction(from: event, pressedIndexPath: pressedIndexPath)
    }

    /// indexPathForItem(at:) uses hit testing. Our hitTest intentionally returns
    /// the collection for card content, so resolve identity from layout instead.
    func cardIndexPath(at point: NSPoint) -> IndexPath? {
        let rect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        return collectionViewLayout?.layoutAttributesForElements(in: rect).first {
            $0.representedElementCategory == .item && $0.frame.contains(point)
        }?.indexPath
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            // Card images/labels must reach the collection's single click owner.
            // Embedded action buttons and editable controls keep native tracking.
            if view is NSButton || (view as? NSTextField)?.isEditable == true {
                return hit
            }
            candidate = view.superview
        }
        return self
    }

    override func keyDown(with event: NSEvent) {
        if keyboardDelegate?.steamWorkshopCollectionView(self, handleKey: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = cardIndexPath(at: point)
        return contextMenuProvider?(indexPath)
    }

    override func rightMouseDown(with event: NSEvent) {
        let scroll = enclosingScrollView as? WallpaperGridScrollView
        scroll?.beginContextMenu(at: event.locationInWindow)
        defer { scroll?.endContextMenu() }
        super.rightMouseDown(with: event)
    }

    private func finishPrimaryMouseInteraction(from event: NSEvent, pressedIndexPath: IndexPath?) {
        let point = convert(event.locationInWindow, from: nil)
        let releasedIndexPath = cardIndexPath(at: point)

        if let pressedIndexPath, releasedIndexPath == pressedIndexPath {
            _ = primaryClickHandler?(pressedIndexPath, event.clickCount)
        } else if pressedIndexPath == nil, releasedIndexPath == nil {
            onBackgroundLeftClick?()
        }

    }
}
