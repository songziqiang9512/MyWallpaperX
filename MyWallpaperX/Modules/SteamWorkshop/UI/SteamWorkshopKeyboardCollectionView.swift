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
    private var lastPrimaryClickIndexPath: IndexPath?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        var pressedIndexPathForClick: IndexPath?
        if event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            let indexPath = indexPathForItem(at: point)
            lastPrimaryClickIndexPath = indexPath
            if let indexPath {
                pressedCardIndexPath = indexPath
                pressedIndexPathForClick = indexPath
                pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
                cardPressStateHandler?(indexPath, true)
            }
        }

        super.mouseDown(with: event)

        guard event.type == .leftMouseDown else { return }
        finishPrimaryMouseInteraction(from: event, pressedIndexPath: pressedIndexPathForClick)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }

    override func keyDown(with event: NSEvent) {
        if keyboardDelegate?.steamWorkshopCollectionView(self, handleKey: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        return contextMenuProvider?(indexPath)
    }

    private func finishPrimaryMouseInteraction(from event: NSEvent, pressedIndexPath: IndexPath?) {
        let releaseLocationInWindow = window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow
        let point = convert(releaseLocationInWindow, from: nil)
        let releasedIndexPath = indexPathForItem(at: point)

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

        lastPrimaryClickIndexPath = nil
    }
}
