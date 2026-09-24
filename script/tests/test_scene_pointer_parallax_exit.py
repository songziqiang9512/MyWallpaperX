"""Execute the AppKit pointer ingress with a recording parallax consumer."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HARNESS = r'''
import AppKit

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
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
'''


class ScenePointerParallaxExitTests(unittest.TestCase):
    def test_sampled_exit_and_tracking_exit_share_neutral_target(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-pointer-parallax-") as folder:
            root = Path(folder)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            executable = root / "harness"
            compilation = subprocess.run([
                "xcrun", "swiftc",
                str(SCENE / "Runtime/Frame/SceneSurfacePointerState.swift"),
                str(SCENE / "Rendering/Frame/SceneMetalView+Pointer.swift"),
                str(harness), "-o", str(executable),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
        self.assertEqual(payload["inside"], [0.5, 0])
        self.assertEqual(payload["outside"], [0, 0])
        self.assertEqual(payload["reentered"], [-0.5, 0.5])
        self.assertEqual(payload["explicitExit"], [0, 0])
        self.assertTrue(payload["outsideFlag"])
        self.assertEqual(payload["capturePosition"], [2, 0])
        self.assertEqual(payload["previous"], [0, 0])


if __name__ == "__main__":
    unittest.main()
