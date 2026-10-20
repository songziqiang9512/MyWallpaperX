"""Exercise both production passive input paths with desktop hit-test changes."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

HARNESS = r'''
import AppKit
typealias CGDirectDisplayID = UInt32
@MainActor final class NSEvent {
    enum EventType { case mouseMoved, leftMouseDown, leftMouseUp, leftMouseDragged, scrollWheel }
    static var mouseLocation = NSPoint(x: 25, y: 75)
    static var pressedMouseButtons: UInt32 = 0
    let type: EventType
    let buttons: Int
    let scrollingDeltaX: CGFloat = 1
    let scrollingDeltaY: CGFloat = 2
    init(_ type: EventType, buttons: Int = 0) { self.type = type; self.buttons = buttons }
}
@MainActor final class View {
    var scripts: [String] = []
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?) {
        scripts.append(script)
    }
}
struct Screen { let frame: NSRect }
struct Window { let frame = NSRect(x: 0, y: 0, width: 100, height: 100); var screen: Screen? }
@MainActor final class HostSurface {
    let id = UUID()
    let screenID: CGDirectDisplayID = 1
    let window = Window()
    let webView = View()
}
@MainActor final class Adapter {
    var surfaces: [CGDirectDisplayID: HostSurface] = [:]
    var lastPassivePointerLocation: (surfaceID: UUID, normalizedPoint: CGPoint)?
    var lastHoveredScreenID: CGDirectDisplayID?
    var desktopAllowsInput = true
    var hitTests = 0
    func shouldForwardMouseEventToWallpaper(at location: NSPoint) -> Bool {
        hitTests += 1
        return desktopAllowsInput
    }
    func eventButtonMask(_ event: NSEvent) -> Int { event.buttons }
    func pointerIdentifier(for event: NSEvent) -> Int { 1 }
    func domMouseButton(for event: NSEvent) -> Int { 0 }
    func domMouseEventType(for event: NSEvent) -> String? {
        switch event.type {
        case .mouseMoved, .leftMouseDragged: "pointermove"
        case .leftMouseDown: "pointerdown"
        case .leftMouseUp: "pointerup"
        case .scrollWheel: "wheel"
        }
    }
    // PRODUCTION_METHODS
}
@main struct PointerChecks {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    @MainActor static func main() {
        let adapter = Adapter(), surface = HostSurface()
        adapter.surfaces[1] = surface
        let point = CGPoint(x: 0.25, y: 0.25)
        let move = NSEvent(.mouseMoved)
        adapter.forwardPassiveMouseEvent(move, to: surface, normalizedPoint: point)
        // The production native-event caller records hover after passive delivery.
        adapter.lastHoveredScreenID = surface.screenID
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(surface.webView.scripts.count == 1, "event then poll should deliver one passive move")
        expect(adapter.hitTests == 1, "poll must hit-test before rejecting duplicate position")

        adapter.desktopAllowsInput = false // A window covers a stationary pointer.
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(adapter.hitTests == 2 && surface.webView.scripts.count == 2, "covering desktop clears hover at same point")
        expect(surface.webView.scripts.last!.contains("SetPassiveMouseState(false"), "desktop cover emits leave")
        adapter.desktopAllowsInput = true
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(surface.webView.scripts.count == 3, "desktop admission after leave must replay unchanged point")

        adapter.clearSyntheticHoverState()
        surface.webView.scripts.removeAll()
        adapter.forwardPolledPointerLocationToWallpaper()
        adapter.forwardPassiveMouseEvent(move, to: surface, normalizedPoint: point)
        expect(surface.webView.scripts.count == 1, "poll then event should deliver one passive move")
        NSEvent.mouseLocation.x = 25.7
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(surface.webView.scripts.count == 2, "motion beyond half a point is delivered")
        NSEvent.mouseLocation.x = 25.9
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(surface.webView.scripts.count == 2, "subthreshold samples remain coalesced")

        let beforeButtons = surface.webView.scripts.count
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel] {
            adapter.forwardPassiveMouseEvent(NSEvent(type, buttons: type == .leftMouseUp ? 0 : 1),
                                             to: surface, normalizedPoint: point)
        }
        expect(surface.webView.scripts.count == beforeButtons + 4, "gesture and wheel events cannot be position-coalesced")
        NSEvent.pressedMouseButtons = 1
        adapter.forwardPolledPointerLocationToWallpaper()
        expect(surface.webView.scripts.count == beforeButtons + 4, "poll cannot turn an external drag into passive input")
        expect(adapter.lastPassivePointerLocation == nil, "buttoned poll invalidates passive position")
        NSEvent.pressedMouseButtons = 0

        adapter.forwardPassiveMouseEvent(move, to: surface, normalizedPoint: point)
        let replacement = HostSurface()
        adapter.surfaces[1] = replacement
        adapter.forwardPassiveMouseEvent(move, to: replacement, normalizedPoint: point)
        expect(replacement.webView.scripts.count == 1, "same display and position cannot suppress a new surface")
        adapter.surfaces.removeAll()
        adapter.clearSyntheticHoverState()
        expect(adapter.lastPassivePointerLocation == nil && adapter.lastHoveredScreenID == nil,
               "teardown clears passive state even after its surface has gone")
        print("passive pointer checks passed")
    }
}
'''


class WebPassivePointerDeliveryTests(unittest.TestCase):
    def test_event_poll_coalescing_keeps_desktop_admission_and_gestures(self):
        forwarding = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift").read_text()
        hit_testing = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingHitTesting.swift").read_text()
        methods = "\n".join(method(forwarding, marker) for marker in [
            "func forwardPolledPointerLocationToWallpaper(", "func clearSyntheticHoverState(",
            "func admitPassivePointerMove(", "func forwardPassiveMouseEvent(",
        ])
        methods += "\n" + "\n".join(method(hit_testing, marker) for marker in [
            "func targetSurface(", "func normalizedPoint(",
        ])
        with tempfile.TemporaryDirectory(prefix="mwx-web-passive-pointer-") as temporary:
            source = Path(temporary) / "Harness.swift"
            binary = Path(temporary) / "harness"
            source.write_text(HARNESS.replace("// PRODUCTION_METHODS", methods))
            result = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
                                     "-parse-as-library", str(source), "-o", str(binary)],
                                    capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
