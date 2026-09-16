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
    var primaryClickHandler: ((IndexPath) -> Bool)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?
    private var isTrackingPrimaryClick = false

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil
        if let previous = pressedCardIndexPath {
            cardPressStateHandler?(previous, false)
        }
        isTrackingPrimaryClick = true
        pressedCardIndexPath = cardIndexPath(at: convert(event.locationInWindow, from: nil))
        pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
        if let indexPath = pressedCardIndexPath {
            cardPressStateHandler?(indexPath, true)
        }
        // Selection is owned by the grid. Do not enter NSCollectionView's
        // selection tracking loop, which may consume mouseUp internally.
    }

    override func mouseUp(with event: NSEvent) {
        guard event.type == .leftMouseUp, isTrackingPrimaryClick else {
            super.mouseUp(with: event)
            return
        }
        isTrackingPrimaryClick = false
        finishPrimaryMouseInteraction(from: event, pressedIndexPath: pressedCardIndexPath)
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

    private func finishPrimaryMouseInteraction(from event: NSEvent, pressedIndexPath: IndexPath?) {
        let point = convert(event.locationInWindow, from: nil)
        let releasedIndexPath = cardIndexPath(at: point)

        if let pressedCardIndexPath {
            let elapsed = ProcessInfo.processInfo.systemUptime - pressedCardTimestamp
            let remaining = max(0, UIInteractionAnimation.minimumPressVisualDuration - elapsed)
            let releaseWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.cardPressStateHandler?(pressedCardIndexPath, false)
                self.pressedCardIndexPath = nil
            }
            pendingPressReleaseWorkItem = releaseWork
            if remaining <= 0 {
                releaseWork.perform()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: releaseWork)
            }
        }

        if let pressedIndexPath, releasedIndexPath == pressedIndexPath {
            _ = primaryClickHandler?(pressedIndexPath)
        } else if pressedIndexPath == nil, releasedIndexPath == nil {
            onBackgroundLeftClick?()
        }

    }
}
