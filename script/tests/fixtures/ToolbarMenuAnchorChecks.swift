import AppKit

// Observe the real shared popup boundary; AppKit still tracks the menu.
@MainActor enum ToolbarMenuAnchorProbe {
    static var last: (point: NSPoint, view: NSView?)?
    static func record(_ point: NSPoint, in view: NSView?) { last = (point, view) }
    static func isBelow(_ view: NSView) -> Bool {
        last?.view === view && last?.point == NSPoint(x: view.bounds.minX,
            y: view.isFlipped ? view.bounds.maxY : view.bounds.minY)
    }
}

@MainActor func toolbarMenuAnchorChecks(buttons: [NSButton]) -> [String: Bool] {
    var checks: [String: Bool] = [:]
    for button in buttons {
        let name = button.accessibilityLabel() ?? "menu"
        ToolbarMenuAnchorProbe.last = nil
        let timer = Timer(timeInterval: 0.03, repeats: false) { _ in
            MainActor.assumeIsolated { button.menu?.cancelTracking() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        button.performClick(nil)
        timer.invalidate()
        checks["toolbar-\(name)-popup-uses-button-bottom-instead-of-pointer"] = ToolbarMenuAnchorProbe.isBelow(button)
        checks["toolbar-\(name)-popup-keeps-first-real-command"] = button.menu?.items.isEmpty == false
            && button.menu?.items.first?.title != name
    }
    return checks
}
