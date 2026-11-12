import AppKit

final class SystemMonitor {
    static let shared = SystemMonitor()
    func refreshRuntimeStats(includeNetwork: Bool = false) {}
}

final class FocusPanelView: NSView {
    override var acceptsFirstResponder: Bool { true }
    func prepareForPresentation() {}
}

final class FocusPanelController: NSViewController {
    let panel = FocusPanelView()
    override func loadView() { view = panel }
}

final class FocusStatusItem {
    let button = NSButton(title: "panel", target: nil, action: nil)
}

final class FocusStatusBarController: NSObject {
    var statusItem: FocusStatusItem? = FocusStatusItem()
    let panelController = FocusPanelController()
    lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = panelController
        return popover
    }()

    func startObserving() {}
    func refreshApplicationStats() {}
    func refreshPanel() {}

    // PRODUCTION_TOGGLE
}

@main
struct StatusBarPanelFocusChecks {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        var checks: [String: Bool] = [:]

        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        let controller = FocusStatusBarController()
        host.contentView?.addSubview(controller.statusItem!.button)
        host.makeKeyAndOrderFront(nil)

        controller.togglePanel()
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let window = controller.popover.contentViewController?.view.window
        checks["panelShown"] = controller.popover.isShown
        checks["appActivatedForFocus"] = NSApp.isActive
        checks["panelOwnsFocus"] = window?.firstResponder === controller.panelController.panel

        let data = try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
