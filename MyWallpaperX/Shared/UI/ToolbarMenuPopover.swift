import AppKit

/// Native menu contents only; command owners retain their existing queries and identities.
@MainActor enum ToolbarMenu {
    struct Row {
        enum Kind { case action, info, sectionHeader, separator }
        var title: String
        var kind: Kind
        var isChecked: Bool = false
        var isEnabled: Bool = true
        var handler: (() -> Void)?
        static func separator() -> Row { Row(title: "", kind: .separator) }
        static func header(_ title: String) -> Row { Row(title: title, kind: .sectionHeader) }
    }

    static func makeMenu(rows: [Row]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for row in rows {
            switch row.kind {
            case .separator: menu.addItem(.separator())
            case .sectionHeader:
                let item = NSMenuItem.sectionHeader(title: row.title)
                item.isEnabled = false
                menu.addItem(item)
            case .info:
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .action:
                let item = ActionMenuItem(title: row.title, symbol: "") {
                    guard row.isEnabled else { return }
                    row.handler?()
                }
                item.isEnabled = row.isEnabled && row.handler != nil
                item.state = row.isChecked ? .on : .off
                menu.addItem(item)
            }
        }
        return menu
    }

    static func menuRepresentation(title: String, rows: [Row]) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = makeMenu(rows: rows)
        return entry
    }

    static func popUp(anchor: NSView, rows: [Row]) {
        let point = NSPoint(x: anchor.bounds.minX, y: anchor.isFlipped ? anchor.bounds.maxY : anchor.bounds.minY)
        makeMenu(rows: rows).popUp(positioning: nil, at: point, in: anchor)
    }
}

/// A dimming overlay can consume a gesture on the grid's behalf. Only a hit
/// on that surface itself counts; scrolling its inspector children does not.
protocol ToolbarGridScrollDismissalSurface: AnyObject {}

/// Shared by all toolbar popovers, including the dedicated Steam panels.
/// Observe real wheel input only while presented; layout/scroll restoration
/// must not dismiss menus, and the original event still reaches the grid.
@MainActor
final class ToolbarPopoverScrollDismissal: NSObject {
    private weak var popover: NSPopover?
    private weak var sourceWindow: NSWindow?
    private var monitor: Any?

    init(popover: NSPopover) {
        self.popover = popover
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stop(_:)),
            name: NSPopover.willCloseNotification, object: popover
        )
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func watch(relativeTo anchor: NSView) {
        stop()
        guard let window = anchor.window else { return }
        sourceWindow = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    @objc private func stop(_ notification: Notification? = nil) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sourceWindow = nil
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.type == .scrollWheel, let window = sourceWindow,
              event.window === window, let content = window.contentView else { return }
        let point = content.convert(event.locationInWindow, from: nil)
        guard content.bounds.contains(point) else { return }
        let hit = content.hitTest(content.convert(point, to: content.superview))
        dismissIfGridScroll(in: window, target: hit)
    }

    func dismissIfGridScroll(in window: NSWindow?, target: NSView?) {
        guard let popover, popover.isShown, let sourceWindow, window === sourceWindow else { return }
        if target is ToolbarGridScrollDismissalSurface {
            popover.performClose(nil)
            return
        }
        var candidate = target
        while let view = candidate {
            if view is NSCollectionView || (view as? NSScrollView)?.documentView is NSCollectionView {
                popover.performClose(nil)
                return
            }
            candidate = view.superview
        }
    }
}
