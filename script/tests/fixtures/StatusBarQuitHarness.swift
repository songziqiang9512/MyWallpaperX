import AppKit

@MainActor enum MainWindowCoordinator {
    static var host: NSWindow?
    static func mainWindow() -> NSWindow? { host }
}

@MainActor final class StatusBarQuitProbe: NSObject {
    let popover = NSPopover()
    let item = NSStatusBar.system.statusItem(withLength: 28)
    // PRODUCTION_CLOSE
    // PRODUCTION_QUIT
    @objc func clickQuit() { quitApp() }
}

@MainActor final class QuitDelegate: NSObject, NSApplicationDelegate {
    var accepted = false
    var cleanupFinished = false
    var dismissals = 0
    var cancel = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        precondition(!cancel, "cancelling the alert must not request termination")
        precondition(!accepted, "one confirmed action must request termination once")
        accepted = true
        trace("termination-requested")
        // The real application asynchronously flushes metadata and retires its
        // playback processes before replying. Exercise that AppKit scheduling
        // contract without opening a user's library or starting a renderer.
        Task { @MainActor in
            trace("async-cleanup-started")
            await Task.yield()
            cleanupFinished = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        precondition(accepted && cleanupFinished)
        trace("confirmed-quit-completed")
    }
}

@MainActor func trace(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}

@main enum StatusBarQuitHarness {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let mode = CommandLine.arguments[1]
        let delegate = QuitDelegate()
        delegate.cancel = mode == "closed-cancel"
        NSApp.delegate = delegate
        let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 360),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        MainWindowCoordinator.host = host
        host.center(); host.makeKeyAndOrderFront(nil); NSApp.activate()
        let probe = StatusBarQuitProbe()
        let controller = NSViewController()
        let quit = NSButton(title: "退出", target: probe, action: #selector(StatusBarQuitProbe.clickQuit))
        quit.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 80))
        controller.view.addSubview(quit)
        probe.popover.contentViewController = controller
        probe.popover.behavior = .transient
        probe.item.button!.title = "Q"

        let start = Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated {
                if mode != "open" {
                    host.close(); MainWindowCoordinator.host = nil
                    NSApp.setActivationPolicy(.accessory)
                }
                probe.popover.show(relativeTo: probe.item.button!.bounds, of: probe.item.button!, preferredEdge: .minY)
                quit.performClick(nil)
            }
        }
        RunLoop.main.add(start, forMode: .common)

        var answered = false
        let respond = Timer(timeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated {
                if answered {
                    if delegate.cancel, NSApp.modalWindow == nil, !probe.popover.isShown {
                        precondition(!delegate.accepted && delegate.dismissals == 1)
                        trace("cancel-preserved-running-app")
                        NSApp.stop(nil)
                        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                            subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
                    }
                    return
                }
                guard let window = NSApp.modalWindow ?? host.attachedSheet,
                      window.isVisible else { return }
                @MainActor func find(_ view: NSView) -> NSButton? {
                    if let button = view as? NSButton, button.title == (delegate.cancel ? "取消" : "退出") { return button }
                    return view.subviews.lazy.compactMap(find).first
                }
                guard let content = window.contentView, let answer = find(content) else { return }
                answered = true
                precondition(mode == "open" ? window.sheetParent === host : NSApp.modalWindow === window)
                delegate.dismissals += 1
                trace(mode == "open" ? "sheet-confirmed" : "no-main-window-app-modal-answered")
                answer.performClick(nil)
            }
        }
        for mode in [RunLoop.Mode.common, .modalPanel] { RunLoop.main.add(respond, forMode: mode) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            FileHandle.standardError.write(Data("status-quit-timeout\n".utf8)); exit(2)
        }
        withExtendedLifetime((delegate, probe, start, respond)) { NSApp.run() }
    }
}
