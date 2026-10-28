import AppKit

/// Native queue mouse, drag and key delivery for Editor, Picker and login.
/// Each blocked run is bracketed by an unblocked positive control; direct
/// window.sendEvent would bypass native document-modal event routing.
/// Wheel routing requires separate real-input runtime evidence. This helper
/// neither synthesizes wheel events nor claims automatic wheel coverage.
@MainActor final class WallpaperModalInputProbe: NSView {
    private(set) var clicks = 0, drags = 0, keys = 0
    var values: [Int] { [clicks, drags, keys] }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func mouseDragged(with event: NSEvent) { drags += 1 }
    override func keyDown(with event: NSEvent) { keys += 1 }

    static func install(in host: NSWindow) -> WallpaperModalInputProbe {
        let probe = WallpaperModalInputProbe(frame: host.contentView!.bounds)
        probe.autoresizingMask = [.width, .height]
        host.contentView!.addSubview(probe)
        return probe
    }

    func deliver() async throws {
        guard let window else { throw CocoaError(.coderInvalidValue) }
        precondition(window.makeFirstResponder(self))
        let time = ProcessInfo.processInfo.systemUptime
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp].enumerated() {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 12, y: 12), modifierFlags: [],
                timestamp: time + Double(index) * 0.001, windowNumber: window.windowNumber, context: nil,
                eventNumber: index, clickCount: 1, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
        // A native sheet may route a key to its own editor. Keep the event
        // observable by this probe without inserting text into that draft.
        let functionKey = String(UnicodeScalar(NSF20FunctionKey)!)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: time + 0.003,
            windowNumber: window.windowNumber, context: nil, characters: functionKey, charactersIgnoringModifiers: functionKey, isARepeat: false, keyCode: 90)!
        NSApp.postEvent(key, atStart: false)
        try await Task.sleep(for: .milliseconds(50))
    }

    static func hasOneDelivery(_ before: [Int], _ after: [Int]) -> Bool {
        before.count == 3 && after.count == 3 && zip(before, after).allSatisfy { $0.1 == $0.0 + 1 }
    }
}
