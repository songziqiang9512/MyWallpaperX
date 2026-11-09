"""Execute the AppKit pointer ingress, surface FIFO, and parallax exit."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

if __package__:
    from .test_scene_prepared_script_resource_catalog import swift_declaration
else:
    from test_scene_prepared_script_resource_catalog import swift_declaration

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session/SceneDesktopWallpaperSession+PointerEvents.swift"
SHORTCUTS = SCENE / "Runtime/Session/SceneDesktopWallpaperSession+UserShortcuts.swift"
HARNESS = r'''
import AppKit
import QuartzCore

__SHORTCUT_INPUT__

final class RecordingSmoother {
    var target = SIMD2<Float>.zero
    func setTarget(_ target: SIMD2<Float>, timestamp: Double) { self.target = target }
}
final class SceneMetalView: NSView {
    var trackingArea: NSTrackingArea?
    var pointerState = SceneSurfacePointerState()
    var parallaxPointerSmoother = RecordingSmoother()
    var sceneScriptPointerEvents = SceneSurfacePointerEventBuffer()
}

final class SceneDesktopWallpaperSession {
    struct Surface { let window: NSWindow; let metalView: SceneMetalView }
    struct LaunchContext { let userShortcuts: ScenePlaybackShortcutConfiguration }

    let isVisible = true
    let isOutputActive = true
    let launchContext: LaunchContext? = nil
    let launchRequestID: UUID? = nil
    var userShortcutInput = SceneUserShortcutInputState()
    let surfaces: [Int: Surface]

    init(window: NSWindow, view: SceneMetalView) {
        surfaces = [1: .init(window: window, metalView: view)]
    }

    __CAPTURE_POINTER_EVENT__

    static func nativeSamples() -> [[String: Any]] {
        _ = NSApplication.shared
        let screen = NSScreen.screens[0].frame
        let cursor = NSEvent.mouseLocation
        let x = cursor.x < screen.midX ? screen.maxX - 200 : screen.minX + 100
        let window = NSWindow(contentRect: CGRect(x: x, y: screen.minY + 100, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = SceneMetalView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView = view
        let session = Self(window: window, view: view)
        func windowless(_ type: CGEventType, _ x: CGFloat, _ y: CGFloat) {
            let screenPoint = window.convertPoint(toScreen: CGPoint(x: x, y: y))
            let quartzPoint = CGPoint(x: screenPoint.x, y: screen.maxY - screenPoint.y)
            let event = NSEvent(cgEvent: CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: quartzPoint, mouseButton: .left)!)!
            precondition(event.window == nil && !window.frame.contains(NSEvent.mouseLocation))
            session.capturePointerEvent(event)
        }
        windowless(.mouseMoved, 25, 75)
        windowless(.leftMouseDown, 75, 50)
        windowless(.leftMouseUp, 50, 75)
        windowless(.leftMouseDown, 25, 25)
        windowless(.leftMouseUp, 150, 50)
        let windowBound = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 25, y: 50),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        precondition(windowBound.window === window)
        session.capturePointerEvent(windowBound)
        return view.drainSceneScriptPointerEvents().events.map {
            ["position": [$0.normalizedPosition.x, $0.normalizedPosition.y],
             "inside": $0.isInside, "down": $0.primaryButtonIsDown]
        }
    }
}

@main enum Harness {
    static func main() throws {
        let view = SceneMetalView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        func move(_ x: Double, _ y: Double) {
            let event = NSEvent.mouseEvent(
                with: .mouseMoved, location: CGPoint(x: x, y: y),
                modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            )!
            view.handlePointerEvent(event)
        }
        move(75, 50)
        let inside = view.parallaxPointerSmoother.target
        move(150, 50)
        let outside = view.parallaxPointerSmoother.target
        let outsideState = view.pointerState
        move(25, 75)
        let reentered = view.parallaxPointerSmoother.target
        view.handlePointerExit()
        let explicitExit = view.parallaxPointerSmoother.target
        func components(_ value: SIMD2<Float>) -> [Float] { [value.x, value.y] }
        let result: [String: Any] = [
            "inside": components(inside), "outside": components(outside),
            "reentered": components(reentered), "explicitExit": components(explicitExit),
            "outsideFlag": !outsideState.isInside,
            "capturePosition": components(outsideState.sceneScriptCurrent),
            "previous": components(outsideState.previous),
            "nativeSamples": SceneDesktopWallpaperSession.nativeSamples(),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
'''


class ScenePointerParallaxExitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = HARNESS.replace("__CAPTURE_POINTER_EVENT__", swift_declaration(
            SESSION.read_text(), "    private func capturePointerEvent("))
        source = source.replace("__SHORTCUT_INPUT__", swift_declaration(
            SHORTCUTS.read_text(), "nonisolated struct SceneUserShortcutInputState {"))
        with tempfile.TemporaryDirectory(prefix="mwx-pointer-parallax-") as folder:
            root = Path(folder)
            harness = root / "Harness.swift"
            harness.write_text(source, encoding="utf-8")
            executable = root / "harness"
            compilation = subprocess.run([
                "xcrun", "swiftc", "-module-cache-path", str(root / "cache"),
                str(ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift"),
                str(ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackDesktopInputAdmission.swift"),
                str(SCENE / "Runtime/Frame/SceneSurfacePointerState.swift"),
                str(SCENE / "Rendering/Frame/SceneMetalView+Pointer.swift"),
                str(harness), "-o", str(executable),
            ], capture_output=True, text=True, timeout=120)
            if compilation.returncode:
                raise AssertionError(compilation.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            if result.returncode:
                raise AssertionError(result.stderr)
            cls.payload = json.loads(result.stdout)

    def test_sampled_exit_and_tracking_exit_share_neutral_target(self) -> None:
        payload = self.payload
        self.assertEqual(payload["inside"], [0.5, 0])
        self.assertEqual(payload["outside"], [0, 0])
        self.assertEqual(payload["reentered"], [-0.5, 0.5])
        self.assertEqual(payload["explicitExit"], [0, 0])
        self.assertTrue(payload["outsideFlag"])
        self.assertEqual(payload["capturePosition"], [2, 0])
        self.assertEqual(payload["previous"], [0, 0])

    def test_native_events_preserve_event_position_in_the_surface_fifo(self) -> None:
        move, down, up, second_down, outside_up, window_bound = self.payload["nativeSamples"]
        self.assertEqual((move["position"], move["inside"]), ([-0.5, 0.5], True))
        self.assertEqual(down, {"position": [0.5, 0], "inside": True, "down": True})
        self.assertEqual(up, {"position": [0, 0.5], "inside": True, "down": False})
        self.assertEqual(second_down, {"position": [-0.5, -0.5], "inside": True, "down": True})
        self.assertEqual(outside_up, {"position": [2, 0], "inside": False, "down": False})
        self.assertEqual(window_bound, {"position": [-0.5, 0], "inside": True, "down": False})


if __name__ == "__main__":
    unittest.main()
